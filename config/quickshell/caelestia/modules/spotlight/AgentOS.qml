pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services

// AGENT OS — Cockpit multi-agents Liquid Glass façon Katana (Super + Maj + A).
// Goutte de verre réfractive qui sort de la Dynamic Island :
//  - Canvas spatial déplaçable (nœud Orchestrateur + liaisons Bézier + cartes agents draggables)
//  - Cockpit & Inspecteur live (timeline outils/étapes, Git status, CHAT DIRECT vers l'agent dans son terminal)
//  - Commandant IA (« Katana AI » propulsé par Gemini qui comprend tes ordres et pilote réellement tous tes agents)
//  - Escouade (Swarm Dispatch multi-moteurs sur tous tes projets auto-découverts)
Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    property Item island

    readonly property bool shown: screenState?.agentos ?? false

    // ── Ouverture : la goutte de verre part de l'île et se déploie au centre ──
    property real morph: shown ? 1 : 0
    readonly property real offsetScale: 1 - morph
    property real fromX
    property real fromW: 220
    property real fromBottom: 38
    property real fromR: 19
    readonly property real fromTop: -70
    readonly property real hMorph: Math.min(1, morph)
    readonly property real curX: fromX + (x - fromX) * hMorph
    readonly property real curW: fromW + (width - fromW) * hMorph
    readonly property real curTop: fromTop + (y - fromTop) * morph
    readonly property real curBottom: fromBottom + (y + height - fromBottom) * morph
    readonly property real curR: fromR + (30 - fromR) * hMorph
    readonly property real reveal: Math.max(0, Math.min(1, (morph - 0.4) / 0.6))

    // ── Palette Liquid Glass ──
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color fgDim: Qt.alpha(fg, 0.58)
    readonly property color fgMute: Qt.alpha(fg, 0.36)
    readonly property color fgFaint: Qt.alpha(fg, 0.08)
    readonly property color accent: Colours.palette.m3primary
    readonly property color leadTint: Agents.waiting > 0 ? "#ff9f0a" : (Agents.lead ? Agents.kindColour(Agents.lead.kind) : accent)
    readonly property color aiTint: "#a78bfa"
    readonly property color green: "#32d74b"
    readonly property color orange: "#ff9f0a"
    readonly property color red: "#ff453a"
    readonly property string agentsBin: "caelestia-agents"
    readonly property string dictateBin: "caelestia-dictate"

    // ── État de l'application ──
    property int viewTab: 0 // 0 = Canvas, 1 = Cockpit & Chat agent, 2 = Commandant IA, 3 = Escouade
    property string selectedId: ""
    property string kindFilter: "all"
    property var cardOffsets: ({})
    property var projects: []
    property int projectIdx: 0
    property string dockTarget: "ai" // "ai" (Commandant IA) ou un moteur ("agy", "claude", "codex", "copilot", "opencode", "antigravity")
    property var swarmKinds: ({ claude: true, codex: true, copilot: false, opencode: false, agy: true, antigravity: false })
    property var detailData: ({ id: "", events: [], steps: [], gitStatus: [] })
    property var chatHistory: [] // [{ role: "user"|"ai", text: "", executed: [] }]
    property bool aiThinking: false
    property bool sendingDirect: false
    property bool dictating: false
    property string toastMsg: ""

    readonly property var visibleAgents: {
        const src = Agents.shown;
        if (kindFilter === "all")
            return src;
        if (kindFilter === "active")
            return src.filter(a => a.status !== "idle");
        return src.filter(a => a.kind === kindFilter);
    }

    readonly property var selectedAgent: {
        if (selectedId) {
            const found = Agents.shown.find(a => a.id === selectedId);
            if (found)
                return found;
        }
        return Agents.shown[0] ?? null;
    }

    // Agent déjà ouvert correspondant au moteur choisi dans le Command Dock
    readonly property var dockExistingAgent: {
        if (dockTarget === "ai")
            return null;
        return Agents.shown.find(a => a.kind === dockTarget && a.alive) ?? Agents.shown.find(a => a.kind === dockTarget) ?? null;
    }

    readonly property color dockTint: dockTarget === "ai" ? aiTint : Agents.kindColour(dockTarget)

    readonly property var currentProject: projects.length > 0 ? projects[Math.max(0, Math.min(projectIdx, projects.length - 1))] : null

    readonly property int swarmCount: {
        let n = 0;
        for (const k of Agents.launchKinds)
            if (swarmKinds[k])
                n += 1;
        return n;
    }

    function close(): void {
        screenState.agentos = false;
    }

    function flashToast(msg: string): void {
        toastMsg = msg;
        toastTimer.restart();
    }

    function refreshProjects(): void {
        if (!projProc.running)
            projProc.running = true;
    }

    function refreshHistory(): void {
        if (!histProc.running)
            histProc.running = true;
    }

    function clearHistory(): void {
        chatHistory = [];
        Quickshell.execDetached([root.agentsBin, "history-clear"]);
    }

    function toggleDictation(): void {
        if (dictating) {
            if (dictProc.running)
                dictProc.write('{"stop":true}\n');
            dictating = false;
            return;
        }
        dictating = true;
        flashToast(I18n.tr("Écoute micro… reclique pour valider"));
        dictProc.running = true;
    }

    function refreshDetail(): void {
        const ag = selectedAgent;
        if (!ag || !ag.id) {
            detailData = { id: "", events: [], steps: [], gitStatus: [] };
            return;
        }
        if (detailProc.running)
            return;
        detailProc.command = [root.agentsBin, "detail", ag.id];
        detailProc.running = true;
    }

    function inspectAgent(agent: var, focusChat: bool): void {
        if (!agent?.id)
            return;
        selectedId = agent.id;
        viewTab = 1;
        refreshDetail();
        if (focusChat)
            directFocusTimer.restart();
    }

    function resetCanvasLayout(): void {
        cardOffsets = ({});
        canvasWires.requestPaint();
        flashToast(I18n.tr("Canvas réaligné"));
    }

    function setCardOffset(id: string, dx: real, dy: real): void {
        const next = Object.assign({}, cardOffsets);
        next[id] = { dx: dx, dy: dy };
        cardOffsets = next;
        canvasWires.requestPaint();
    }

    function toggleSwarmKind(k: string): void {
        const next = Object.assign({}, swarmKinds);
        next[k] = !next[k];
        swarmKinds = next;
    }

    // Parler directement à un agent précis (via Kitty remote ou reprise de session)
    function sendDirectToAgent(agent: var, text: string): void {
        const msg = (text || "").trim();
        if (!agent?.id || !msg)
            return;
        if (sendProc.running)
            return;
        sendingDirect = true;
        sendProc.command = [root.agentsBin, "send", agent.id, msg];
        sendProc.running = true;
    }

    // Parler au Commandant IA (Katana AI)
    function askCommander(text: string): void {
        const msg = (text || "").trim();
        if (!msg || aiThinking)
            return;
        const next = chatHistory.slice(-18);
        next.push({ role: "user", text: msg, executed: [] });
        chatHistory = next;
        viewTab = 2;
        aiThinking = true;
        const cwd = currentProject?.cwd ?? "";
        commanderProc.command = cwd ? [root.agentsBin, "commander", "--cwd", cwd, msg] : [root.agentsBin, "commander", msg];
        commanderProc.running = true;
    }

    // Exécution depuis la barre inférieure (Command Dock)
    function submitDock(promptText: string): void {
        const msg = (promptText || "").trim();
        if (dockTarget === "ai") {
            if (!msg) {
                viewTab = 2;
                return;
            }
            askCommander(msg);
            return;
        }
        // Si une session de ce moteur existe déjà et qu'on écrit un ordre, on lui parle en direct !
        if (msg && dockExistingAgent) {
            sendDirectToAgent(dockExistingAgent, msg);
            return;
        }
        const cwd = currentProject?.cwd ?? "";
        Agents.dispatch(dockTarget, cwd, msg);
        flashToast(I18n.tr("%1 lancé sur %2").arg(Agents.kindName(dockTarget)).arg(currentProject?.name ?? "~"));
    }

    function launchSwarm(promptText: string): void {
        const cwd = currentProject?.cwd ?? "";
        const chosen = Agents.launchKinds.filter(k => !!swarmKinds[k]);
        if (chosen.length === 0) {
            flashToast(I18n.tr("Sélectionne au moins un agent"));
            return;
        }
        for (const k of chosen)
            Agents.dispatch(k, cwd, promptText.trim());
        flashToast(I18n.tr("Escouade de %1 agent(s) déployée sur %2").arg(chosen.length).arg(currentProject?.name ?? "~"));
        viewTab = 0;
    }

    visible: morph > 0.001
    implicitWidth: Math.min(1160, Math.max(900, Math.round((screen?.width ?? 1920) * 0.63)))
    implicitHeight: Math.min(700, Math.max(570, Math.round((screen?.height ?? 1080) * 0.66)))

    Behavior on morph {
        NumberAnimation {
            duration: root.shown ? 560 : 340
            easing.type: root.shown ? Easing.OutBack : Easing.InOutCubic
            easing.overshoot: 0.65
        }
    }

    onShownChanged: {
        if (shown) {
            if (island && island.h > 1) {
                fromX = island.x;
                fromW = island.w;
                fromBottom = island.y + island.h;
                fromR = island.radius;
            } else {
                fromX = island ? island.x + island.width / 2 - 110 : x;
                fromW = 220;
                fromBottom = island ? island.y + 38 : 38;
                fromR = 19;
            }
            refreshProjects();
            refreshHistory();
            if (!selectedId && Agents.shown.length > 0)
                selectedId = Agents.shown[0].id;
            refreshDetail();
            canvasWires.requestPaint();
            dockInput.forceActiveFocus();
            openFocusTimer.restart();
        } else if (dictating && dictProc.running) {
            dictProc.write('{"cancel":true}\n');
            dictating = false;
        }
    }

    onSelectedIdChanged: {
        if (shown && viewTab === 1)
            refreshDetail();
    }

    onViewTabChanged: {
        if (viewTab === 1)
            refreshDetail();
        if (viewTab === 0)
            canvasWires.requestPaint();
        if (viewTab === 2)
            openFocusTimer.restart();
    }

    Connections {
        target: Agents

        function onListChanged(): void {
            if (root.shown && root.viewTab === 0)
                canvasWires.requestPaint();
        }
    }

    Timer {
        id: openFocusTimer

        interval: 120
        onTriggered: {
            if (root.shown)
                dockInput.forceActiveFocus();
        }
    }

    Timer {
        id: directFocusTimer

        interval: 90
        onTriggered: {
            if (root.shown && root.viewTab === 1)
                directReplyInput.forceActiveFocus();
        }
    }

    Timer {
        id: toastTimer

        interval: 3200
        onTriggered: root.toastMsg = ""
    }

    Timer {
        interval: 2500
        repeat: true
        running: root.shown && root.viewTab === 1 && !!root.selectedAgent
        onTriggered: root.refreshDetail()
    }

    Process {
        id: projProc

        command: [root.agentsBin, "projects"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    if (Array.isArray(arr)) {
                        root.projects = arr;
                        if (root.projectIdx >= arr.length)
                            root.projectIdx = 0;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: histProc

        command: [root.agentsBin, "history"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text);
                    if (Array.isArray(arr) && arr.length > 0 && !root.aiThinking)
                        root.chatHistory = arr;
                } catch (e) {}
            }
        }
    }

    Process {
        id: dictProc

        command: [root.dictateBin, "--stdout-only"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: data => {
                let m;
                try {
                    m = JSON.parse(data);
                } catch (e) {
                    return;
                }
                if (m.stage === "text" && m.text) {
                    dockInput.text = m.text;
                } else if (m.stage === "state" && m.state === "erreur") {
                    root.dictating = false;
                    root.flashToast("✕ " + (m.detail || I18n.tr("Erreur micro")));
                } else if (m.stage === "done") {
                    root.dictating = false;
                    if (m.text) {
                        dockInput.text = m.text;
                        dockInput.forceActiveFocus();
                    }
                }
            }
        }
        onExited: root.dictating = false
    }

    Process {
        id: detailProc

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d && typeof d === "object")
                        root.detailData = d;
                } catch (e) {}
            }
        }
    }

    Process {
        id: sendProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.sendingDirect = false;
                try {
                    const r = JSON.parse(text);
                    root.flashToast((r.ok ? "✓ " : "✕ ") + (r.detail || ""));
                } catch (e) {
                    root.flashToast(I18n.tr("Message envoyé"));
                }
                if (root.viewTab === 1)
                    root.refreshDetail();
            }
        }
        onExited: root.sendingDirect = false
    }

    Process {
        id: commanderProc

        stdout: StdioCollector {
            onStreamFinished: {
                root.aiThinking = false;
                let reply = I18n.tr("Réponse reçue.");
                let executed = [];
                try {
                    const r = JSON.parse(text);
                    reply = r.reply || reply;
                    executed = r.executed ?? [];
                } catch (e) {
                    reply = text.trim() || I18n.tr("Erreur de réponse du Commandant IA.");
                }
                const next = root.chatHistory.slice(-18);
                next.push({ role: "ai", text: reply, executed: executed });
                root.chatHistory = next;
            }
        }
        onExited: root.aiThinking = false
    }

    // ════════════════════ Contenu principal ════════════════════
    Item {
        id: mainBody

        anchors.fill: parent
        opacity: root.reveal
        scale: 0.96 + 0.04 * root.reveal

        Keys.onEscapePressed: root.close()

        // Aura supérieure colorée par l'agent leader
        Rectangle {
            x: 24
            y: 10
            width: Math.round(parent.width * 0.45)
            height: 64
            radius: 32
            opacity: Colours.light ? 0.28 : 0.48
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.35; color: Qt.alpha(root.leadTint, 0.16) }
                GradientStop { position: 0.78; color: Qt.alpha(root.leadTint, 0.04) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // Reflet spéculaire supérieur sur le bord du verre
        Rectangle {
            anchors.top: parent.top
            anchors.topMargin: 1.5
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - 80
            height: 1
            opacity: Colours.light ? 0.5 : 0.24
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.25; color: "#ffffff" }
                GradientStop { position: 0.75; color: "#ffffff" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // ── 1. BARRE SUPÉRIEURE : Command Header ──
        Item {
            id: topBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 14
            height: 44

            // Gauche : Identité AGENT OS + KPI temps réel
            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 34
                    radius: 12
                    border.width: 0.75
                    border.color: Qt.alpha(root.leadTint, 0.46)
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(root.leadTint, 0.26) }
                        GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.05) }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "hub"
                        color: root.leadTint
                        fontStyle: Tokens.font.icon.size(18).build()
                        fill: 1
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Row {
                        spacing: 6

                        StyledText {
                            text: I18n.tr("AGENT OS")
                            color: root.fg
                            font.pointSize: 10.5
                            font.weight: Font.Black
                            font.letterSpacing: 1.0
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: katBadge.implicitWidth + 10
                            height: 15
                            radius: 7.5
                            color: Qt.alpha(root.aiTint, 0.18)
                            border.width: 0.5
                            border.color: Qt.alpha(root.aiTint, 0.42)

                            StyledText {
                                id: katBadge

                                anchors.centerIn: parent
                                text: "KATANA AI"
                                color: root.aiTint
                                font.pointSize: 6.1
                                font.weight: Font.Black
                                font.letterSpacing: 0.7
                            }
                        }
                    }

                    StyledText {
                        text: {
                            const parts = [];
                            if (Agents.working > 0)
                                parts.push(I18n.tr("%1 actif(s)").arg(Agents.working));
                            if (Agents.waiting > 0)
                                parts.push(I18n.tr("%1 en attente").arg(Agents.waiting));
                            if (Agents.totalSubagents > 0)
                                parts.push(I18n.tr("+%1 sub").arg(Agents.totalSubagents));
                            if (parts.length === 0)
                                parts.push(Agents.shown.length > 0 ? I18n.tr("%1 session(s) prêtes").arg(Agents.shown.length) : I18n.tr("Orchestrateur prêt"));
                            if (Agents.totalTokens > 0)
                                parts.push(`${Agents.fmtTokens(Agents.totalTokens)} tok`);
                            return parts.join(" · ");
                        }
                        color: Agents.waiting > 0 ? root.orange : root.fgDim
                        font.pointSize: 7.6
                        font.weight: Font.Medium
                        font.features: { "tnum": 1 }
                    }
                }
            }

            // Centre : Switch 4 vues (Canvas · Cockpit · Commandant · Escouade)
            Rectangle {
                anchors.centerIn: parent
                width: tabRow.implicitWidth + 8
                height: 34
                radius: 17
                color: Qt.alpha(root.fg, 0.07)
                border.width: 0.5
                border.color: Qt.alpha(root.fg, 0.14)

                Row {
                    id: tabRow

                    anchors.centerIn: parent
                    spacing: 3

                    Repeater {
                        model: [
                            { idx: 0, icon: "hub", label: I18n.tr("Canvas") },
                            { idx: 1, icon: "terminal", label: I18n.tr("Cockpit") },
                            { idx: 2, icon: "auto_awesome", label: I18n.tr("Commandant") },
                            { idx: 3, icon: "groups", label: I18n.tr("Escouade") }
                        ]

                        Rectangle {
                            id: vTab

                            required property var modelData
                            readonly property bool active: root.viewTab === modelData.idx
                            readonly property color tCol: modelData.idx === 2 ? root.aiTint : root.leadTint

                            width: vTabRow.implicitWidth + 18
                            height: 26
                            radius: 13
                            color: active ? Qt.alpha(tCol, 0.24) : (vTabArea.containsMouse ? Qt.alpha(root.fg, 0.08) : "transparent")
                            border.width: active ? 0.5 : 0
                            border.color: Qt.alpha(tCol, 0.54)

                            Behavior on color { ColorAnimation { duration: 140 } }

                            Row {
                                id: vTabRow

                                anchors.centerIn: parent
                                spacing: 5

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: vTab.modelData.icon
                                    color: vTab.active ? vTab.tCol : root.fgDim
                                    fontStyle: Tokens.font.icon.size(14).build()
                                    fill: vTab.active ? 1 : 0
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: vTab.modelData.label
                                    color: vTab.active ? root.fg : root.fgDim
                                    font.pointSize: 8.1
                                    font.weight: vTab.active ? Font.Bold : Font.Medium
                                }
                            }

                            MouseArea {
                                id: vTabArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.viewTab = vTab.modelData.idx
                            }
                        }
                    }
                }
            }

            // Droite : Nettoyer, Dictée vocale, Fermer
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Rectangle {
                    visible: Agents.doneShown > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: hdrCleanRow.implicitWidth + 16
                    height: 28
                    radius: 14
                    color: Qt.alpha(root.fg, hdrCleanArea.containsMouse ? 0.14 : 0.07)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.16)

                    Row {
                        id: hdrCleanRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "cleaning_services"
                            color: root.fgDim
                            fontStyle: Tokens.font.icon.size(13).build()
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Nettoyer")
                            color: root.fg
                            font.pointSize: 7.8
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: hdrCleanArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Agents.clean()
                    }
                }

                // Bouton Dictée vocale intégrée dans Agent OS (Voice-First façon Katana)
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: root.dictating ? Qt.alpha(root.red, 0.34) : Qt.alpha(root.aiTint, voiceArea.containsMouse ? 0.26 : 0.14)
                    border.width: root.dictating ? 1 : 0.5
                    border.color: root.dictating ? Qt.alpha(root.red, 0.8) : Qt.alpha(root.aiTint, 0.44)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: root.dictating ? "stop" : "mic"
                        color: root.dictating ? root.red : root.aiTint
                        fontStyle: Tokens.font.icon.size(15).build()
                        fill: 1
                    }

                    MouseArea {
                        id: voiceArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleDictation()
                    }
                }

                // Bouton Fermer
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: Qt.alpha(root.fg, closeArea.containsMouse ? 0.18 : 0.08)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.18)

                    MaterialIcon {
                        anchors.centerIn: parent
                        text: "close"
                        color: root.fg
                        fontStyle: Tokens.font.icon.size(15).build()
                    }

                    MouseArea {
                        id: closeArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }

        // Séparateur optique
        Rectangle {
            id: topSep

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topBar.bottom
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            anchors.topMargin: 8
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.15; color: Qt.alpha(root.fg, 0.14) }
                GradientStop { position: 0.85; color: Qt.alpha(root.fg, 0.14) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        // ── 2. BANDEAU PERMISSION PRIORITAIRE ──
        Rectangle {
            id: permBanner

            readonly property var perm: Agents.perm
            visible: !!perm
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: topSep.bottom
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: visible ? 10 : 0
            height: visible ? 54 : 0
            radius: 16
            color: Qt.alpha(root.orange, 0.14)
            border.width: 0.75
            border.color: Qt.alpha(root.orange, 0.45)

            Row {
                anchors.left: parent.left
                anchors.right: permBtns.left
                anchors.leftMargin: 14
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "gpp_maybe"
                    color: root.orange
                    fontStyle: Tokens.font.icon.size(20).build()
                    fill: 1
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 34
                    spacing: 1

                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: `${permBanner.perm?.label ?? ""} · ${permBanner.perm?.project ?? ""}`
                        color: root.fg
                        font.pointSize: 8.8
                        font.weight: Font.Bold
                    }
                    StyledText {
                        width: parent.width
                        elide: Text.ElideRight
                        text: permBanner.perm?.detail ?? ""
                        color: root.fgDim
                        font.family: "monospace"
                        font.pointSize: 7.6
                    }
                }
            }

            Row {
                id: permBtns

                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                ActionChip {
                    label: I18n.tr("Terminal")
                    tint: root.fg
                    onClicked: {
                        const p = permBanner.perm;
                        Agents.answer(p.id, "terminal");
                        Agents.focusPid(p.agentPid);
                    }
                }
                ActionChip {
                    label: I18n.tr("Refuser")
                    tint: root.red
                    onClicked: Agents.answer(permBanner.perm.id, "deny")
                }
                ActionChip {
                    label: I18n.tr("Autoriser")
                    tint: root.green
                    filled: true
                    onClicked: Agents.answer(permBanner.perm.id, "allow")
                }
            }
        }

        // ── 3. ZONE CENTRALE (Canvas / Cockpit / Commandant / Escouade) ──
        Item {
            id: workArea

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: permBanner.bottom
            anchors.bottom: commandDock.top
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.topMargin: 10
            anchors.bottomMargin: 10

            // ════════════════ VUE 0 : CANVAS SPATIAL KATANA ════════════════
            Item {
                id: canvasView

                anchors.fill: parent
                visible: root.viewTab === 0

                Rectangle {
                    anchors.fill: parent
                    radius: 20
                    color: Qt.alpha(root.fg, Colours.light ? 0.03 : 0.04)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.12)
                    clip: true

                    Canvas {
                        id: canvasWires

                        anchors.fill: parent
                        onPaint: {
                            const ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);

                            ctx.fillStyle = Colours.light ? "rgba(0,0,0,0.08)" : "rgba(255,255,255,0.08)";
                            const step = 28;
                            for (let gx = 18; gx < width; gx += step) {
                                for (let gy = 18; gy < height; gy += step) {
                                    ctx.fillRect(gx, gy, 1.5, 1.5);
                                }
                            }

                            const list = root.visibleAgents;
                            if (list.length === 0)
                                return;

                            const hubX = width / 2;
                            const hubY = 44;

                            for (let i = 0; i < Math.min(list.length, 6); i++) {
                                const a = list[i];
                                const col = i % 3;
                                const row = Math.floor(i / 3);
                                const colsInRow = Math.min(3, Math.min(6, list.length) - row * 3);
                                const cardW = 328;
                                const cardH = 194;
                                const gapX = 18;
                                const totalW = colsInRow * cardW + (colsInRow - 1) * gapX;
                                const baseX = Math.round((width - totalW) / 2) + col * (cardW + gapX);
                                const baseY = 92 + row * (cardH + 18);
                                const off = root.cardOffsets[a.id] ?? { dx: 0, dy: 0 };
                                const cx = baseX + off.dx + cardW / 2;
                                const cy = baseY + off.dy;

                                const isWait = a.status === "waiting";
                                const isWork = a.status === "working";
                                const cHex = isWait ? "#ff9f0a" : (isWork ? String(Agents.kindColour(a.kind)) : "#32d74b");

                                ctx.save();
                                ctx.beginPath();
                                ctx.moveTo(hubX, hubY + 18);
                                const midY = (hubY + 18 + cy) / 2;
                                ctx.bezierCurveTo(hubX, midY, cx, midY, cx, cy + 4);
                                ctx.strokeStyle = cHex;
                                ctx.globalAlpha = isWork || isWait ? 0.52 : 0.25;
                                ctx.lineWidth = isWork || isWait ? 2.0 : 1.25;
                                ctx.stroke();

                                ctx.beginPath();
                                ctx.arc(cx, cy + 4, 3.5, 0, Math.PI * 2);
                                ctx.fillStyle = cHex;
                                ctx.globalAlpha = 0.85;
                                ctx.fill();
                                ctx.restore();
                            }
                        }
                    }

                    // Nœud central Orchestrateur (clic = ouvre Commandant IA)
                    Rectangle {
                        id: hubNode

                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 20
                        width: hubRow.implicitWidth + 26
                        height: 36
                        radius: 18
                        border.width: 0.75
                        border.color: Qt.alpha(root.aiTint, hubArea.containsMouse ? 0.72 : 0.48)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.alpha(root.aiTint, 0.24) }
                            GradientStop { position: 1.0; color: Qt.alpha(root.fg, 0.05) }
                        }

                        Row {
                            id: hubRow

                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7
                                height: 7
                                radius: 3.5
                                color: Agents.activeCount > 0 ? root.leadTint : root.green
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("KATANA AI · ORCHESTRATEUR")
                                color: root.fg
                                font.pointSize: 7.5
                                font.weight: Font.Black
                                font.letterSpacing: 0.75
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: `${Agents.shown.length} ${Agents.shown.length > 1 ? I18n.tr("agents") : I18n.tr("agent")}`
                                color: root.fgDim
                                font.pointSize: 7.4
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }

                        MouseArea {
                            id: hubArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.viewTab = 2
                        }
                    }

                    // Filtres moteurs
                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        y: 24
                        spacing: 5

                        FilterChip {
                            label: I18n.tr("Tous")
                            count: Agents.shown.length
                            selected: root.kindFilter === "all"
                            tint: root.fg
                            onClicked: {
                                root.kindFilter = "all";
                                canvasWires.requestPaint();
                            }
                        }

                        Repeater {
                            model: Agents.presentKinds

                            FilterChip {
                                required property var modelData
                                label: Agents.kindName(modelData.kind)
                                count: modelData.total
                                selected: root.kindFilter === modelData.kind
                                tint: Agents.kindColour(modelData.kind)
                                onClicked: {
                                    root.kindFilter = root.kindFilter === modelData.kind ? "all" : modelData.kind;
                                    canvasWires.requestPaint();
                                }
                            }
                        }
                    }

                    // Bouton Réaligner
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        y: 24
                        visible: Object.keys(root.cardOffsets).length > 0
                        width: alignRow.implicitWidth + 14
                        height: 26
                        radius: 13
                        color: Qt.alpha(root.fg, alignArea.containsMouse ? 0.15 : 0.08)
                        border.width: 0.5
                        border.color: Qt.alpha(root.fg, 0.2)

                        Row {
                            id: alignRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "grid_view"
                                color: root.fgDim
                                fontStyle: Tokens.font.icon.size(12).build()
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: I18n.tr("Réaligner")
                                color: root.fg
                                font.pointSize: 7.4
                                font.weight: Font.DemiBold
                            }
                        }

                        MouseArea {
                            id: alignArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetCanvasLayout()
                        }
                    }

                    // Cartes agents draggables sur le Canvas
                    Repeater {
                        model: root.visibleAgents.slice(0, 6)

                        Item {
                            id: kCard

                            required property var modelData
                            required property int index

                            readonly property bool working: modelData.status === "working"
                            readonly property bool waiting: modelData.status === "waiting"
                            readonly property bool done: !working && !waiting
                            readonly property color tint: Agents.kindColour(modelData.kind)
                            readonly property color stateCol: waiting ? root.orange : working ? tint : root.green
                            readonly property int col: index % 3
                            readonly property int row: Math.floor(index / 3)
                            readonly property int colsInRow: Math.min(3, Math.min(6, root.visibleAgents.length) - row * 3)
                            readonly property real baseX: Math.round((canvasView.width - (colsInRow * width + (colsInRow - 1) * 18)) / 2) + col * (width + 18)
                            readonly property real baseY: 92 + row * (height + 18)
                            readonly property var off: root.cardOffsets[modelData.id] ?? ({ dx: 0, dy: 0 })

                            width: 328
                            height: 194
                            x: Math.max(12, Math.min(canvasView.width - width - 12, baseX + off.dx))
                            y: Math.max(66, Math.min(canvasView.height - height - 12, baseY + off.dy))
                            z: dragArea.pressed ? 20 : (cardHover.hovered ? 10 : 1)

                            Rectangle {
                                anchors.fill: parent
                                radius: 18
                                border.width: dragArea.pressed || cardHover.hovered ? 1 : 0.6
                                border.color: Qt.alpha(kCard.stateCol, dragArea.pressed ? 0.72 : cardHover.hovered ? 0.52 : 0.28)
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.alpha(kCard.stateCol, Colours.light ? 0.14 : 0.18) }
                                    GradientStop { position: 0.45; color: Qt.alpha(Colours.palette.m3surface, Colours.light ? 0.68 : 0.44) }
                                    GradientStop { position: 1.0; color: Qt.alpha(Colours.palette.m3surface, Colours.light ? 0.78 : 0.58) }
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.topMargin: 1
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 18
                                    anchors.rightMargin: 18
                                    height: 1
                                    color: "#ffffff"
                                    opacity: Colours.light ? 0.45 : 0.22
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 7
                                    y: 18
                                    width: 3
                                    height: 44
                                    radius: 1.5
                                    color: kCard.stateCol
                                }
                            }

                            MouseArea {
                                id: dragArea

                                property real startMouseX
                                property real startMouseY
                                property real startDx
                                property real startDy

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 146
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                onPressed: mouse => {
                                    const pt = mapToItem(canvasView, mouse.x, mouse.y);
                                    startMouseX = pt.x;
                                    startMouseY = pt.y;
                                    startDx = kCard.off.dx;
                                    startDy = kCard.off.dy;
                                }
                                onPositionChanged: mouse => {
                                    if (!pressed)
                                        return;
                                    const pt = mapToItem(canvasView, mouse.x, mouse.y);
                                    root.setCardOffset(kCard.modelData.id, startDx + (pt.x - startMouseX), startDy + (pt.y - startMouseY));
                                }
                                onDoubleClicked: root.inspectAgent(kCard.modelData, true)
                            }

                            Column {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 14
                                anchors.topMargin: 12
                                anchors.bottomMargin: 10
                                spacing: 7

                                Item {
                                    width: parent.width
                                    height: 32

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 8

                                        MiniSpinner {
                                            size: 30
                                            tint: kCard.stateCol
                                            spinning: kCard.working && root.shown && root.viewTab === 0
                                            done: kCard.done
                                            letter: Agents.kindLetter(kCard.modelData.kind)
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 1

                                            Row {
                                                spacing: 5

                                                Rectangle {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: kcKindTxt.implicitWidth + 10
                                                    height: 16
                                                    radius: 8
                                                    color: Qt.alpha(kCard.tint, 0.2)
                                                    border.width: 0.5
                                                    border.color: Qt.alpha(kCard.tint, 0.45)

                                                    StyledText {
                                                        id: kcKindTxt

                                                        anchors.centerIn: parent
                                                        text: Agents.kindShort(kCard.modelData.kind)
                                                        color: kCard.tint
                                                        font.pointSize: 6.2
                                                        font.weight: Font.Black
                                                        font.letterSpacing: 0.45
                                                    }
                                                }

                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    width: 140
                                                    elide: Text.ElideRight
                                                    text: kCard.modelData.project
                                                    color: root.fg
                                                    font.pointSize: 9.4
                                                    font.weight: Font.Bold
                                                }
                                            }

                                            Row {
                                                spacing: 6

                                                StyledText {
                                                    visible: Boolean(kCard.modelData.model)
                                                    text: kCard.modelData.model
                                                    color: Qt.alpha(kCard.tint, 0.92)
                                                    font.pointSize: 6.9
                                                    font.weight: Font.DemiBold
                                                }
                                                StyledText {
                                                    visible: Boolean(kCard.modelData.branch)
                                                    text: `⎇ ${kCard.modelData.branch}`
                                                    color: root.fgDim
                                                    font.pointSize: 6.9
                                                }
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: kcTimeTxt.implicitWidth + 12
                                        height: 20
                                        radius: 10
                                        color: Qt.alpha(kCard.stateCol, 0.16)
                                        border.width: 0.5
                                        border.color: Qt.alpha(kCard.stateCol, 0.38)

                                        StyledText {
                                            id: kcTimeTxt

                                            anchors.centerIn: parent
                                            text: Agents.elapsed(kCard.modelData.since)
                                            color: kCard.stateCol
                                            font.pointSize: 7.4
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }

                                StyledText {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: kCard.modelData.title || I18n.tr("Session active")
                                    color: root.fg
                                    font.pointSize: 8.2
                                    font.weight: Font.Medium
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 44
                                    radius: 10
                                    color: Qt.alpha(root.fg, Colours.light ? 0.055 : 0.075)
                                    border.width: 0.5
                                    border.color: Qt.alpha(kCard.stateCol, 0.2)

                                    StyledText {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        verticalAlignment: Text.AlignVCenter
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: kCard.waiting
                                            ? `▲ ${kCard.modelData.tool || I18n.tr("Attend ta validation")}`
                                            : kCard.working
                                                ? `❯ ${kCard.modelData.focus || kCard.modelData.tool || I18n.tr("Réfléchit…")}`
                                                : `✓ ${kCard.modelData.reply || I18n.tr("Prêt à recevoir un ordre")}`
                                        color: kCard.waiting ? root.orange : root.fg
                                        font.family: "monospace"
                                        font.pointSize: 7.3
                                    }
                                }

                                Row {
                                    width: parent.width
                                    spacing: 8

                                    Row {
                                        visible: (kCard.modelData.stepTotal ?? 0) > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 48
                                            height: 4
                                            radius: 2
                                            color: Qt.alpha(root.fg, 0.14)

                                            Rectangle {
                                                width: Math.max(4, parent.width * Math.min(1, (kCard.modelData.stepDone ?? 0) / Math.max(1, kCard.modelData.stepTotal ?? 1)))
                                                height: parent.height
                                                radius: 2
                                                color: kCard.stateCol
                                            }
                                        }
                                        StyledText {
                                            text: `${kCard.modelData.stepDone}/${kCard.modelData.stepTotal}`
                                            color: kCard.stateCol
                                            font.pointSize: 7
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                    }

                                    StyledText {
                                        visible: (kCard.modelData.files ?? 0) > 0
                                        text: I18n.tr("%1 fich.").arg(kCard.modelData.files)
                                        color: root.fgDim
                                        font.pointSize: 7.1
                                        font.features: { "tnum": 1 }
                                    }
                                    StyledText {
                                        visible: (kCard.modelData.tokens ?? 0) > 0
                                        text: `${Agents.fmtTokens(kCard.modelData.tokens)} tok`
                                        color: root.fgDim
                                        font.pointSize: 7.1
                                        font.features: { "tnum": 1 }
                                    }
                                    StyledText {
                                        visible: (kCard.modelData.subagents ?? 0) > 0
                                        text: I18n.tr("+%1 sub").arg(kCard.modelData.subagents)
                                        color: root.aiTint
                                        font.pointSize: 7.1
                                        font.weight: Font.Bold
                                    }
                                }

                                // Pied de carte : Parler (direct dans Studio) · Ouvrir · Stop
                                Item {
                                    width: parent.width
                                    height: 24

                                    Row {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 5

                                        ActionChip {
                                            label: I18n.tr("Parler")
                                            icon: "chat"
                                            tint: kCard.tint
                                            filled: true
                                            onClicked: root.inspectAgent(kCard.modelData, true)
                                        }
                                        ActionChip {
                                            label: I18n.tr("Ouvrir")
                                            icon: "open_in_new"
                                            tint: root.fg
                                            onClicked: {
                                                Agents.focus(kCard.modelData);
                                                root.close();
                                            }
                                        }
                                        ActionChip {
                                            visible: kCard.working && kCard.modelData.canStop
                                            label: I18n.tr("Stop")
                                            icon: "stop"
                                            tint: root.red
                                            onClicked: Agents.stop(kCard.modelData)
                                        }
                                    }

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: kCard.done
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: Qt.alpha(root.fg, kcDismissArea.containsMouse ? 0.18 : 0.08)

                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            text: "close"
                                            color: root.fgDim
                                            fontStyle: Tokens.font.icon.size(12).build()
                                        }

                                        MouseArea {
                                            id: kcDismissArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Agents.dismiss(kCard.modelData)
                                        }
                                    }
                                }
                            }

                            HoverHandler {
                                id: cardHover
                            }
                        }
                    }

                    // État vide du Canvas
                    Column {
                        visible: root.visibleAgents.length === 0
                        anchors.centerIn: parent
                        spacing: 14

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Déploie un agent sur ton canvas")
                            color: root.fg
                            font.pointSize: 12
                            font.weight: Font.Bold
                        }

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("Parle à Katana AI dans la barre du bas ou clique sur un moteur")
                            color: root.fgDim
                            font.pointSize: 8.6
                        }

                        Flow {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 680
                            spacing: 10

                            Repeater {
                                model: Agents.launchKinds

                                Rectangle {
                                    id: spawnTile

                                    required property string modelData
                                    readonly property color tint: Agents.kindColour(modelData)

                                    width: 216
                                    height: 62
                                    radius: 16
                                    scale: spawnArea.pressed ? 0.96 : 1
                                    color: Qt.alpha(tint, spawnArea.containsMouse ? 0.22 : 0.11)
                                    border.width: 0.75
                                    border.color: Qt.alpha(tint, spawnArea.containsMouse ? 0.56 : 0.28)

                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        MiniSpinner {
                                            size: 32
                                            tint: spawnTile.tint
                                            spinning: false
                                            done: false
                                            letter: Agents.kindLetter(spawnTile.modelData)
                                        }

                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                text: Agents.kindName(spawnTile.modelData)
                                                color: root.fg
                                                font.pointSize: 9.4
                                                font.weight: Font.Bold
                                            }
                                            StyledText {
                                                text: I18n.tr("Lancer une session")
                                                color: root.fgDim
                                                font.pointSize: 7.4
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: spawnArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Agents.dispatch(spawnTile.modelData, root.currentProject?.cwd ?? "", "")
                                    }
                                }
                            }
                        }
                    }

                    // Rangée rapide d'invocation en bas du canvas
                    Column {
                        visible: root.visibleAgents.length > 0 && root.visibleAgents.length <= 3
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 34
                        spacing: 7

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: I18n.tr("INVOQUER UN AGENT SUR LE CANVAS")
                            color: root.fgMute
                            font.pointSize: 6.8
                            font.weight: Font.Black
                            font.letterSpacing: 0.8
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8

                            Repeater {
                                model: Agents.launchKinds

                                Rectangle {
                                    id: qSpawn

                                    required property string modelData
                                    readonly property color tint: Agents.kindColour(modelData)

                                    width: qSpawnRow.implicitWidth + 22
                                    height: 36
                                    radius: 18
                                    scale: qSpawnArea.pressed ? 0.95 : 1
                                    color: Qt.alpha(tint, qSpawnArea.containsMouse ? 0.22 : 0.1)
                                    border.width: 0.6
                                    border.color: Qt.alpha(tint, qSpawnArea.containsMouse ? 0.56 : 0.28)

                                    Behavior on scale { NumberAnimation { duration: 100 } }

                                    Row {
                                        id: qSpawnRow

                                        anchors.centerIn: parent
                                        spacing: 6

                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Agents.kindLetter(qSpawn.modelData)
                                            color: qSpawn.tint
                                            font.pointSize: 8.6
                                            font.weight: Font.Black
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Agents.kindName(qSpawn.modelData)
                                            color: root.fg
                                            font.pointSize: 8
                                            font.weight: Font.DemiBold
                                        }
                                    }

                                    MouseArea {
                                        id: qSpawnArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Agents.dispatch(qSpawn.modelData, root.currentProject?.cwd ?? "", "")
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: root.visibleAgents.length > 0
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: 12
                        text: I18n.tr("Glisse une carte pour organiser · Double-clic pour parler à l'agent")
                        color: root.fgMute
                        font.pointSize: 7.2
                    }
                }
            }

            // ════════════════ VUE 1 : COCKPIT, INSPECTEUR & CHAT DIRECT AGENT ════════════════
            Row {
                anchors.fill: parent
                visible: root.viewTab === 1
                spacing: 12

                // Flotte gauche
                Rectangle {
                    width: 320
                    height: parent.height
                    radius: 18
                    color: Qt.alpha(root.fg, 0.045)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.12)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 8

                        StyledText {
                            text: I18n.tr("FLOTTE (%1)").arg(Agents.shown.length)
                            color: root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.Black
                            font.letterSpacing: 0.7
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - 26
                            contentWidth: width
                            contentHeight: fleetCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: fleetCol

                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: Agents.shown

                                    Rectangle {
                                        id: fItem

                                        required property var modelData
                                        readonly property bool sel: root.selectedAgent?.id === modelData.id
                                        readonly property bool working: modelData.status === "working"
                                        readonly property bool waiting: modelData.status === "waiting"
                                        readonly property color tint: Agents.kindColour(modelData.kind)
                                        readonly property color stateCol: waiting ? root.orange : working ? tint : root.green

                                        width: fleetCol.width
                                        height: 64
                                        radius: 14
                                        color: sel ? Qt.alpha(tint, 0.18) : Qt.alpha(root.fg, fItemArea.containsMouse ? 0.09 : 0.04)
                                        border.width: sel ? 1 : 0.5
                                        border.color: sel ? Qt.alpha(tint, 0.56) : Qt.alpha(root.fg, 0.12)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 9

                                            MiniSpinner {
                                                anchors.verticalCenter: parent.verticalCenter
                                                size: 28
                                                tint: fItem.stateCol
                                                spinning: fItem.working && root.shown && root.viewTab === 1
                                                done: !fItem.working && !fItem.waiting
                                                letter: Agents.kindLetter(fItem.modelData.kind)
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 86
                                                spacing: 2

                                                Row {
                                                    spacing: 5

                                                    StyledText {
                                                        text: Agents.kindShort(fItem.modelData.kind)
                                                        color: fItem.tint
                                                        font.pointSize: 6.4
                                                        font.weight: Font.Black
                                                    }
                                                    StyledText {
                                                        width: 130
                                                        elide: Text.ElideRight
                                                        text: fItem.modelData.project
                                                        color: root.fg
                                                        font.pointSize: 8.6
                                                        font.weight: Font.Bold
                                                    }
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                    text: fItem.modelData.focus || fItem.modelData.tool || fItem.modelData.title || I18n.tr("Prêt")
                                                    color: root.fgDim
                                                    font.pointSize: 7.4
                                                }
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: Agents.elapsed(fItem.modelData.since)
                                                color: fItem.stateCol
                                                font.pointSize: 7.4
                                                font.weight: Font.Bold
                                                font.features: { "tnum": 1 }
                                            }
                                        }

                                        MouseArea {
                                            id: fItemArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.selectedId = fItem.modelData.id;
                                                directFocusTimer.restart();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Inspecteur droite + Chat direct vers l'agent
                Rectangle {
                    id: inspectorPane

                    readonly property var ag: root.selectedAgent
                    readonly property color tint: ag ? Agents.kindColour(ag.kind) : root.accent

                    width: parent.width - 332
                    height: parent.height
                    radius: 18
                    color: Qt.alpha(root.fg, 0.045)
                    border.width: 0.5
                    border.color: Qt.alpha(tint, ag ? 0.28 : 0.12)

                    StyledText {
                        visible: !inspectorPane.ag
                        anchors.centerIn: parent
                        text: I18n.tr("Sélectionne un agent à inspecter ou commander")
                        color: root.fgDim
                        font.pointSize: 9.5
                    }

                    Column {
                        visible: !!inspectorPane.ag
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        // En-tête inspecteur
                        Item {
                            width: parent.width
                            height: 42

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10

                                MiniSpinner {
                                    size: 36
                                    tint: inspectorPane.tint
                                    spinning: (inspectorPane.ag?.status ?? "") === "working" && root.shown && root.viewTab === 1
                                    done: (inspectorPane.ag?.status ?? "") === "idle"
                                    letter: Agents.kindLetter(inspectorPane.ag?.kind ?? "")
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Row {
                                        spacing: 6

                                        StyledText {
                                            text: Agents.kindName(inspectorPane.ag?.kind ?? "")
                                            color: inspectorPane.tint
                                            font.pointSize: 10
                                            font.weight: Font.Black
                                        }
                                        StyledText {
                                            text: `· ${inspectorPane.ag?.project ?? ""}`
                                            color: root.fg
                                            font.pointSize: 10
                                            font.weight: Font.Bold
                                        }
                                        StyledText {
                                            visible: Boolean(inspectorPane.ag?.model)
                                            text: `(${inspectorPane.ag?.model ?? ""})`
                                            color: root.fgDim
                                            font.pointSize: 8.1
                                        }
                                    }
                                    StyledText {
                                        width: 350
                                        elide: Text.ElideMiddle
                                        text: inspectorPane.ag?.cwd || inspectorPane.ag?.title || ""
                                        color: root.fgDim
                                        font.family: "monospace"
                                        font.pointSize: 7.3
                                    }
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                ActionChip {
                                    label: I18n.tr("Ouvrir")
                                    icon: "open_in_new"
                                    tint: inspectorPane.tint
                                    filled: true
                                    onClicked: {
                                        Agents.focus(inspectorPane.ag);
                                        root.close();
                                    }
                                }
                                ActionChip {
                                    visible: Boolean(inspectorPane.ag?.cwd)
                                    label: I18n.tr("Terminal")
                                    icon: "terminal"
                                    tint: root.fg
                                    onClicked: Agents.openTerminal(inspectorPane.ag.cwd)
                                }
                                ActionChip {
                                    visible: Boolean(inspectorPane.ag?.canStop) && (inspectorPane.ag?.status ?? "") === "working"
                                    label: I18n.tr("Stop")
                                    icon: "stop"
                                    tint: root.orange
                                    onClicked: Agents.stop(inspectorPane.ag)
                                }
                                ActionChip {
                                    visible: Boolean(inspectorPane.ag?.canStop)
                                    label: I18n.tr("Tuer")
                                    icon: "power_settings_new"
                                    tint: root.red
                                    onClicked: Agents.kill(inspectorPane.ag)
                                }
                            }
                        }

                        // 4 Tuiles KPI
                        Row {
                            width: parent.width
                            spacing: 8

                            KpiBox {
                                width: (parent.width - 24) / 4
                                label: I18n.tr("STATUT")
                                value: (inspectorPane.ag?.status ?? "") === "working" ? I18n.tr("Actif") : (inspectorPane.ag?.status ?? "") === "waiting" ? I18n.tr("Attente") : I18n.tr("Prêt")
                                sub: Agents.elapsed(inspectorPane.ag?.since ?? Agents.now)
                                tint: (inspectorPane.ag?.status ?? "") === "waiting" ? root.orange : (inspectorPane.ag?.status ?? "") === "working" ? inspectorPane.tint : root.green
                            }
                            KpiBox {
                                width: (parent.width - 24) / 4
                                label: I18n.tr("FICHIERS")
                                value: String(inspectorPane.ag?.files ?? 0)
                                sub: inspectorPane.ag?.branch ? `⎇ ${inspectorPane.ag.branch}` : "—"
                                tint: root.fg
                            }
                            KpiBox {
                                width: (parent.width - 24) / 4
                                label: I18n.tr("TOKENS")
                                value: Agents.fmtTokens(inspectorPane.ag?.tokens ?? 0) || "—"
                                sub: inspectorPane.ag?.model || "—"
                                tint: inspectorPane.tint
                            }
                            KpiBox {
                                width: (parent.width - 24) / 4
                                label: I18n.tr("SOUS-AGENTS")
                                value: String(inspectorPane.ag?.subagents ?? 0)
                                sub: (inspectorPane.ag?.stepTotal ?? 0) > 0 ? I18n.tr("Étapes %1/%2").arg(inspectorPane.ag.stepDone).arg(inspectorPane.ag.stepTotal) : I18n.tr("Flux direct")
                                tint: root.aiTint
                            }
                        }

                        // Timeline + Étapes & Git
                        Row {
                            width: parent.width
                            height: parent.height - 176
                            spacing: 10

                            Rectangle {
                                width: (root.detailData.steps?.length ?? 0) > 0 || (root.detailData.gitStatus?.length ?? 0) > 0
                                    ? Math.round(parent.width * 0.63)
                                    : parent.width
                                height: parent.height
                                radius: 14
                                color: Qt.alpha(root.fg, 0.04)
                                border.width: 0.5
                                border.color: Qt.alpha(root.fg, 0.1)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 6

                                    StyledText {
                                        text: I18n.tr("JOURNAL D'ACTIVITÉ EN DIRECT")
                                        color: root.fgDim
                                        font.pointSize: 7.2
                                        font.weight: Font.Black
                                        font.letterSpacing: 0.65
                                    }

                                    Flickable {
                                        width: parent.width
                                        height: parent.height - 22
                                        contentWidth: width
                                        contentHeight: evCol.implicitHeight
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds

                                        Column {
                                            id: evCol

                                            width: parent.width
                                            spacing: 5

                                            Repeater {
                                                model: root.detailData.events ?? []

                                                Row {
                                                    required property var modelData
                                                    width: evCol.width
                                                    spacing: 7

                                                    Rectangle {
                                                        y: 4
                                                        width: 6
                                                        height: 6
                                                        radius: 3
                                                        color: modelData.kind === "tool" ? inspectorPane.tint
                                                            : modelData.kind === "focus" ? root.aiTint
                                                            : modelData.kind === "reply" ? root.green
                                                            : modelData.kind === "file" ? root.orange
                                                            : root.fgDim
                                                    }

                                                    StyledText {
                                                        width: parent.width - 16
                                                        wrapMode: Text.Wrap
                                                        maximumLineCount: 2
                                                        elide: Text.ElideRight
                                                        text: modelData.text ?? ""
                                                        color: modelData.kind === "reply" ? root.fg : root.fgDim
                                                        font.family: modelData.kind === "tool" ? "monospace" : Tokens.font.body.medium.family
                                                        font.pointSize: modelData.kind === "tool" ? 7.4 : 7.8
                                                    }
                                                }
                                            }

                                            StyledText {
                                                visible: (root.detailData.events?.length ?? 0) === 0
                                                text: inspectorPane.ag?.reply || inspectorPane.ag?.tool || I18n.tr("Session prête — écris un ordre ci-dessous pour piloter cet agent en direct.")
                                                color: root.fgDim
                                                font.pointSize: 8
                                                width: parent.width
                                                wrapMode: Text.Wrap
                                            }
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                visible: (root.detailData.steps?.length ?? 0) > 0 || (root.detailData.gitStatus?.length ?? 0) > 0
                                width: parent.width - Math.round(parent.width * 0.63) - 10
                                height: parent.height
                                radius: 14
                                color: Qt.alpha(root.fg, 0.04)
                                border.width: 0.5
                                border.color: Qt.alpha(root.fg, 0.1)

                                Flickable {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    contentWidth: width
                                    contentHeight: sideDetCol.implicitHeight
                                    clip: true

                                    Column {
                                        id: sideDetCol

                                        width: parent.width
                                        spacing: 8

                                        StyledText {
                                            visible: (root.detailData.steps?.length ?? 0) > 0
                                            text: I18n.tr("ÉTAPES")
                                            color: root.fgDim
                                            font.pointSize: 7.2
                                            font.weight: Font.Black
                                            font.letterSpacing: 0.65
                                        }

                                        Repeater {
                                            model: root.detailData.steps ?? []

                                            Row {
                                                required property var modelData
                                                width: sideDetCol.width
                                                spacing: 6

                                                MaterialIcon {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.status === "done" ? "check_circle" : modelData.status === "in_progress" ? "pending" : "radio_button_unchecked"
                                                    color: modelData.status === "done" ? root.green : modelData.status === "in_progress" ? inspectorPane.tint : root.fgMute
                                                    fontStyle: Tokens.font.icon.size(13).build()
                                                    fill: modelData.status === "done" ? 1 : 0
                                                }
                                                StyledText {
                                                    width: parent.width - 20
                                                    elide: Text.ElideRight
                                                    text: modelData.title ?? ""
                                                    color: modelData.status === "done" ? root.fgDim : root.fg
                                                    font.pointSize: 7.6
                                                }
                                            }
                                        }

                                        StyledText {
                                            visible: (root.detailData.gitStatus?.length ?? 0) > 0
                                            text: I18n.tr("FICHIERS GIT")
                                            color: root.fgDim
                                            font.pointSize: 7.2
                                            font.weight: Font.Black
                                            font.letterSpacing: 0.65
                                        }

                                        Repeater {
                                            model: root.detailData.gitStatus ?? []

                                            StyledText {
                                                required property string modelData
                                                width: sideDetCol.width
                                                elide: Text.ElideMiddle
                                                text: modelData
                                                color: root.fgDim
                                                font.family: "monospace"
                                                font.pointSize: 7.1
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // BARRE DE CHAT DIRECT VERS CET AGENT (injection Kitty / reprise session)
                        Rectangle {
                            width: parent.width
                            height: 44
                            radius: 22
                            color: Qt.alpha(inspectorPane.tint, directReplyInput.activeFocus ? 0.14 : 0.08)
                            border.width: directReplyInput.activeFocus ? 1 : 0.6
                            border.color: Qt.alpha(inspectorPane.tint, directReplyInput.activeFocus ? 0.72 : 0.34)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: directReplyInput.forceActiveFocus()
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 6
                                spacing: 8

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "send"
                                    color: inspectorPane.tint
                                    fontStyle: Tokens.font.icon.size(15).build()
                                    fill: 1
                                }

                                TextInput {
                                    id: directReplyInput

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 118
                                    height: 32
                                    verticalAlignment: Text.AlignVCenter
                                    color: root.fg
                                    font.pointSize: 8.6
                                    clip: true
                                    selectByMouse: true
                                    activeFocusOnPress: true
                                    Keys.onEscapePressed: root.close()
                                    onAccepted: {
                                        if (text.trim()) {
                                            root.sendDirectToAgent(inspectorPane.ag, text);
                                            text = "";
                                        }
                                    }

                                    StyledText {
                                        visible: directReplyInput.text.length === 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: I18n.tr("Écrire directement à %1 (%2)…").arg(Agents.kindName(inspectorPane.ag?.kind ?? "")).arg(inspectorPane.ag?.project ?? "")
                                        color: root.fgMute
                                        font.pointSize: 8.3
                                    }
                                }

                                ActionChip {
                                    anchors.verticalCenter: parent.verticalCenter
                                    label: root.sendingDirect ? I18n.tr("Envoi…") : I18n.tr("Envoyer")
                                    tint: inspectorPane.tint
                                    filled: true
                                    onClicked: {
                                        if (directReplyInput.text.trim()) {
                                            root.sendDirectToAgent(inspectorPane.ag, directReplyInput.text);
                                            directReplyInput.text = "";
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ════════════════ VUE 2 : COMMANDANT IA (KATANA AI CHEF D'ORCHESTRE) ════════════════
            Rectangle {
                anchors.fill: parent
                visible: root.viewTab === 2
                radius: 20
                color: Qt.alpha(root.fg, 0.04)
                border.width: 0.6
                border.color: Qt.alpha(root.aiTint, 0.3)

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 12

                    // En-tête Commandant IA
                    Item {
                        width: parent.width
                        height: 36

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Rectangle {
                                width: 32
                                height: 32
                                radius: 16
                                color: Qt.alpha(root.aiTint, 0.22)
                                border.width: 0.6
                                border.color: Qt.alpha(root.aiTint, 0.5)

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    text: "auto_awesome"
                                    color: root.aiTint
                                    fontStyle: Tokens.font.icon.size(16).build()
                                    fill: 1
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: I18n.tr("KATANA AI · MÉMOIRE & ACTIONS ANO-GPT")
                                    color: root.fg
                                    font.pointSize: 9.4
                                    font.weight: Font.Black
                                    font.letterSpacing: 0.65
                                }
                                StyledText {
                                    text: I18n.tr("Pilote tous tes agents + tout ton PC (apps, réglages, musique, web, fichiers) avec la mémoire d'ANO-GPT")
                                    color: root.fgDim
                                    font.pointSize: 7.8
                                }
                            }
                        }

                        ActionChip {
                            visible: root.chatHistory.length > 0
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            label: I18n.tr("Effacer")
                            icon: "delete_sweep"
                            tint: root.fg
                            onClicked: root.clearHistory()
                        }
                    }

                    // Fil de discussion ou suggestions rapides
                    Flickable {
                        id: chatFlick

                        width: parent.width
                        height: parent.height - 48
                        contentWidth: width
                        contentHeight: Math.max(height, chatCol.implicitHeight)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        onContentHeightChanged: {
                            if (contentHeight > height)
                                contentY = contentHeight - height;
                        }

                        Column {
                            id: chatCol

                            width: chatFlick.width
                            spacing: 10

                            // Accueil + Suggestions rapides quand vide
                            Column {
                                visible: root.chatHistory.length === 0 && !root.aiThinking
                                width: parent.width
                                topPadding: 44
                                spacing: 14

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: I18n.tr("Que veux-tu ordonner à tes agents ?")
                                    color: root.fg
                                    font.pointSize: 13
                                    font.weight: Font.Bold
                                }

                                Flow {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Math.min(760, parent.width - 20)
                                    spacing: 8

                                    Repeater {
                                        model: [
                                            I18n.tr("Fais-moi un bilan de tous mes agents en cours"),
                                            I18n.tr("Dis à AGY CLI d'analyser l'état git du projet"),
                                            I18n.tr("Lance Codex sur flutter_kali_cours pour vérifier dart analyze"),
                                            I18n.tr("Déploie Claude et Copilot en parallèle sur ce projet"),
                                            I18n.tr("Ouvre OpenCode sur ANO-GPT pour auditer la latence"),
                                            I18n.tr("Stoppe les agents CLI qui tournent")
                                        ]

                                        Rectangle {
                                            id: sugChip

                                            required property string modelData
                                            width: sugTxt.implicitWidth + 24
                                            height: 34
                                            radius: 17
                                            scale: sugArea.pressed ? 0.96 : 1
                                            color: Qt.alpha(root.aiTint, sugArea.containsMouse ? 0.22 : 0.1)
                                            border.width: 0.6
                                            border.color: Qt.alpha(root.aiTint, sugArea.containsMouse ? 0.56 : 0.28)

                                            Behavior on scale { NumberAnimation { duration: 100 } }

                                            StyledText {
                                                id: sugTxt

                                                anchors.centerIn: parent
                                                text: sugChip.modelData
                                                color: root.fg
                                                font.pointSize: 8.1
                                                font.weight: Font.Medium
                                            }

                                            MouseArea {
                                                id: sugArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.askCommander(sugChip.modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            // Messages de la conversation
                            Repeater {
                                model: root.chatHistory

                                Item {
                                    id: msgWrap

                                    required property var modelData
                                    readonly property bool isUser: modelData.role === "user"

                                    width: chatCol.width
                                    height: msgBubble.implicitHeight + 4

                                    Rectangle {
                                        id: msgBubble

                                        anchors.right: msgWrap.isUser ? parent.right : undefined
                                        anchors.left: msgWrap.isUser ? undefined : parent.left
                                        width: Math.min(Math.round(parent.width * 0.78), msgCol.implicitWidth + 28)
                                        implicitHeight: msgCol.implicitHeight + 20
                                        radius: 16
                                        color: msgWrap.isUser ? Qt.alpha(root.aiTint, 0.2) : Qt.alpha(root.fg, 0.07)
                                        border.width: 0.6
                                        border.color: msgWrap.isUser ? Qt.alpha(root.aiTint, 0.48) : Qt.alpha(root.fg, 0.14)

                                        Column {
                                            id: msgCol

                                            anchors.fill: parent
                                            anchors.margins: 10
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 14
                                            spacing: 6

                                            StyledText {
                                                width: Math.min(implicitWidth, Math.round(msgWrap.width * 0.78) - 28)
                                                wrapMode: Text.Wrap
                                                text: msgWrap.modelData.text
                                                color: root.fg
                                                font.pointSize: 8.8
                                            }

                                            // Badges d'actions réellement exécutées par Katana AI
                                            Flow {
                                                visible: (msgWrap.modelData.executed?.length ?? 0) > 0
                                                width: Math.min(Math.round(msgWrap.width * 0.74), 680)
                                                spacing: 6

                                                Repeater {
                                                    model: msgWrap.modelData.executed ?? []

                                                    Rectangle {
                                                        id: exBadge

                                                        required property var modelData
                                                        readonly property color bCol: modelData.ok ? root.green : root.red

                                                        width: exTxt.implicitWidth + 16
                                                        height: 22
                                                        radius: 11
                                                        color: Qt.alpha(bCol, 0.16)
                                                        border.width: 0.5
                                                        border.color: Qt.alpha(bCol, 0.45)

                                                        StyledText {
                                                            id: exTxt

                                                            anchors.centerIn: parent
                                                            text: `${exBadge.modelData.ok ? "✓" : "✕"} ${exBadge.modelData.label}`
                                                            color: exBadge.bCol
                                                            font.pointSize: 7.3
                                                            font.weight: Font.Bold
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Indicateur réflexion Katana AI
                            Row {
                                visible: root.aiThinking
                                spacing: 8

                                MiniSpinner {
                                    size: 22
                                    tint: root.aiTint
                                    spinning: root.aiThinking
                                    done: false
                                    letter: "✦"
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Katana AI analyse ta flotte et transmet les ordres…")
                                    color: root.aiTint
                                    font.pointSize: 8.4
                                    font.weight: Font.DemiBold
                                }
                            }
                        }
                    }
                }
            }

            // ════════════════ VUE 3 : ESCOUADE (SWARM DISPATCH & PROJETS) ════════════════
            Row {
                anchors.fill: parent
                visible: root.viewTab === 3
                spacing: 12

                Rectangle {
                    width: 390
                    height: parent.height
                    radius: 18
                    color: Qt.alpha(root.fg, 0.045)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.12)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8

                        StyledText {
                            text: I18n.tr("PROJETS DÉTECTÉS (%1)").arg(root.projects.length)
                            color: root.fgDim
                            font.pointSize: 7.5
                            font.weight: Font.Black
                            font.letterSpacing: 0.7
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - 26
                            contentWidth: width
                            contentHeight: projCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: projCol

                                width: parent.width
                                spacing: 5

                                Repeater {
                                    model: root.projects

                                    Rectangle {
                                        id: pRow

                                        required property var modelData
                                        required property int index
                                        readonly property bool sel: root.projectIdx === index

                                        width: projCol.width
                                        height: 48
                                        radius: 12
                                        color: sel ? Qt.alpha(root.leadTint, 0.18) : Qt.alpha(root.fg, pRowArea.containsMouse ? 0.09 : 0.04)
                                        border.width: sel ? 0.8 : 0.5
                                        border.color: sel ? Qt.alpha(root.leadTint, 0.52) : Qt.alpha(root.fg, 0.1)

                                        Row {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 8

                                            MaterialIcon {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "folder_code"
                                                color: pRow.sel ? root.leadTint : root.fgDim
                                                fontStyle: Tokens.font.icon.size(16).build()
                                                fill: pRow.sel ? 1 : 0
                                            }

                                            Column {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: parent.width - 96
                                                spacing: 1

                                                StyledText {
                                                    width: parent.width
                                                    elide: Text.ElideRight
                                                    text: pRow.modelData.name
                                                    color: root.fg
                                                    font.pointSize: 8.6
                                                    font.weight: Font.Bold
                                                }
                                                StyledText {
                                                    width: parent.width
                                                    elide: Text.ElideMiddle
                                                    text: pRow.modelData.cwd
                                                    color: root.fgDim
                                                    font.family: "monospace"
                                                    font.pointSize: 6.9
                                                }
                                            }

                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: Boolean(pRow.modelData.branch)
                                                text: `⎇ ${pRow.modelData.branch}`
                                                color: pRow.modelData.active ? root.green : root.fgDim
                                                font.pointSize: 7.2
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        MouseArea {
                                            id: pRowArea

                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.projectIdx = pRow.index
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width - 402
                    height: parent.height
                    radius: 18
                    color: Qt.alpha(root.fg, 0.045)
                    border.width: 0.5
                    border.color: Qt.alpha(root.leadTint, 0.24)

                    Column {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 14

                        Column {
                            spacing: 2

                            StyledText {
                                text: I18n.tr("DÉPLOIEMENT ESCOUADE (MULTI-AGENTS)")
                                color: root.fg
                                font.pointSize: 9.2
                                font.weight: Font.Black
                                font.letterSpacing: 0.7
                            }
                            StyledText {
                                text: I18n.tr("Coche plusieurs moteurs et lance une mission en parallèle sur %1").arg(root.currentProject?.name ?? "~")
                                color: root.fgDim
                                font.pointSize: 8.2
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 8

                            Repeater {
                                model: Agents.launchKinds

                                Rectangle {
                                    id: swBox

                                    required property string modelData
                                    readonly property bool on: !!root.swarmKinds[modelData]
                                    readonly property color tint: Agents.kindColour(modelData)

                                    width: Math.floor((parent.width - 16) / 3)
                                    height: 54
                                    radius: 14
                                    color: on ? Qt.alpha(tint, 0.22) : Qt.alpha(root.fg, swBoxArea.containsMouse ? 0.09 : 0.04)
                                    border.width: on ? 1 : 0.5
                                    border.color: on ? Qt.alpha(tint, 0.62) : Qt.alpha(root.fg, 0.14)

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 9

                                        MiniSpinner {
                                            size: 28
                                            tint: swBox.tint
                                            spinning: false
                                            done: false
                                            letter: Agents.kindLetter(swBox.modelData)
                                        }
                                        Column {
                                            anchors.verticalCenter: parent.verticalCenter

                                            StyledText {
                                                text: Agents.kindName(swBox.modelData)
                                                color: root.fg
                                                font.pointSize: 8.8
                                                font.weight: Font.Bold
                                            }
                                            StyledText {
                                                text: swBox.on ? I18n.tr("Sélectionné") : I18n.tr("Cliquer pour ajouter")
                                                color: swBox.on ? swBox.tint : root.fgDim
                                                font.pointSize: 7.1
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: swBoxArea

                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleSwarmKind(swBox.modelData)
                                    }
                                }
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 6

                            Repeater {
                                model: [
                                    I18n.tr("Audite le projet et liste les bugs prioritaires"),
                                    I18n.tr("Vérifie le lint, les types et corrige les erreurs"),
                                    I18n.tr("Explique l'architecture et propose 3 améliorations"),
                                    I18n.tr("Prépare un résumé git des derniers changements")
                                ]

                                ActionChip {
                                    required property string modelData
                                    label: modelData
                                    tint: root.fg
                                    onClicked: {
                                        swarmInput.text = modelData;
                                        swarmInput.forceActiveFocus();
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 92
                            radius: 14
                            color: Qt.alpha(root.fg, 0.06)
                            border.width: 0.75
                            border.color: swarmInput.activeFocus ? Qt.alpha(root.leadTint, 0.65) : Qt.alpha(root.fg, 0.14)

                            MouseArea {
                                anchors.fill: parent
                                onClicked: swarmInput.forceActiveFocus()
                            }

                            TextEdit {
                                id: swarmInput

                                anchors.fill: parent
                                anchors.margins: 12
                                color: root.fg
                                font.pointSize: 9
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                activeFocusOnPress: true
                                Keys.onEscapePressed: root.close()

                                StyledText {
                                    visible: swarmInput.text.length === 0
                                    text: I18n.tr("Écris ici la mission commune à envoyer à ton escouade d'agents…")
                                    color: root.fgMute
                                    font.pointSize: 9
                                }
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            width: deployRow.implicitWidth + 28
                            height: 38
                            radius: 19
                            scale: deployArea.pressed ? 0.96 : 1
                            color: Qt.alpha(root.leadTint, deployArea.containsMouse ? 0.34 : 0.24)
                            border.width: 1
                            border.color: Qt.alpha(root.leadTint, 0.65)

                            Behavior on scale { NumberAnimation { duration: 100 } }

                            Row {
                                id: deployRow

                                anchors.centerIn: parent
                                spacing: 7

                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "rocket_launch"
                                    color: root.leadTint
                                    fontStyle: Tokens.font.icon.size(16).build()
                                    fill: 1
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.tr("Déployer l'escouade (%1)").arg(root.swarmCount)
                                    color: root.fg
                                    font.pointSize: 8.8
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                id: deployArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.launchSwarm(swarmInput.text)
                            }
                        }
                    }
                }
            }

            // Toast de confirmation
            Rectangle {
                visible: root.toastMsg.length > 0
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 12
                z: 40
                width: toastTxt.implicitWidth + 26
                height: 30
                radius: 15
                color: Qt.alpha(Colours.palette.m3surface, 0.94)
                border.width: 0.75
                border.color: Qt.alpha(root.leadTint, 0.55)

                StyledText {
                    id: toastTxt

                    anchors.centerIn: parent
                    text: root.toastMsg
                    color: root.fg
                    font.pointSize: 8.2
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── 4. BARRE INFÉRIEURE : Katana Command Dock (Katana AI ou moteur direct) ──
        Rectangle {
            id: commandDock

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            anchors.bottomMargin: 14
            height: 54
            radius: 27
            color: Qt.alpha(root.fg, Colours.light ? 0.065 : 0.085)
            border.width: dockInput.activeFocus ? 1.0 : 0.75
            border.color: dockInput.activeFocus ? Qt.alpha(root.dockTint, 0.75) : Qt.alpha(root.fg, 0.18)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 7

                // Pilules rapides : Katana AI (par défaut) + tous les moteurs
                Row {
                    id: dockEnginesRow

                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    // Pilule Commandant IA (Katana AI)
                    Rectangle {
                        readonly property bool sel: root.dockTarget === "ai"

                        width: sel ? dAiRow.implicitWidth + 14 : 30
                        height: 30
                        radius: 15
                        color: sel ? Qt.alpha(root.aiTint, 0.28) : Qt.alpha(root.aiTint, dAiArea.containsMouse ? 0.18 : 0.1)
                        border.width: sel ? 0.9 : 0.5
                        border.color: Qt.alpha(root.aiTint, sel ? 0.72 : 0.32)

                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                        Row {
                            id: dAiRow

                            anchors.centerIn: parent
                            spacing: 4

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "auto_awesome"
                                color: root.aiTint
                                fontStyle: Tokens.font.icon.size(13).build()
                                fill: 1
                            }
                            StyledText {
                                visible: root.dockTarget === "ai"
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Katana AI"
                                color: root.fg
                                font.pointSize: 7.4
                                font.weight: Font.Black
                            }
                        }

                        MouseArea {
                            id: dAiArea

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.dockTarget = "ai";
                                dockInput.forceActiveFocus();
                            }
                        }
                    }

                    Repeater {
                        model: Agents.launchKinds

                        Rectangle {
                            id: dKind

                            required property string modelData
                            readonly property bool sel: root.dockTarget === modelData
                            readonly property bool hasLive: Agents.shown.some(a => a.kind === modelData && a.alive)
                            readonly property color tint: Agents.kindColour(modelData)

                            width: sel ? dKindRow.implicitWidth + 14 : 28
                            height: 28
                            radius: 14
                            anchors.verticalCenter: parent.verticalCenter
                            color: sel ? Qt.alpha(tint, 0.24) : Qt.alpha(tint, dKindArea.containsMouse ? 0.16 : 0.08)
                            border.width: sel ? 0.8 : 0.5
                            border.color: Qt.alpha(tint, sel ? 0.65 : 0.25)

                            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                            Row {
                                id: dKindRow

                                anchors.centerIn: parent
                                spacing: 4

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Agents.kindLetter(dKind.modelData)
                                    color: dKind.tint
                                    font.pointSize: 8
                                    font.weight: Font.Black
                                }
                                StyledText {
                                    visible: dKind.sel
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Agents.kindName(dKind.modelData)
                                    color: root.fg
                                    font.pointSize: 7.4
                                    font.weight: Font.Bold
                                }
                            }

                            // Petit point vert si ce moteur a déjà une session vivante
                            Rectangle {
                                visible: dKind.hasLive
                                anchors.top: parent.top
                                anchors.right: parent.right
                                width: 6
                                height: 6
                                radius: 3
                                color: root.green
                            }

                            MouseArea {
                                id: dKindArea

                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.dockTarget = dKind.modelData;
                                    dockInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                // Sélecteur projet rapide
                Rectangle {
                    id: projChip

                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(148, projChipRow.implicitWidth + 16)
                    height: 30
                    radius: 15
                    color: Qt.alpha(root.fg, projChipArea.containsMouse ? 0.14 : 0.07)
                    border.width: 0.5
                    border.color: Qt.alpha(root.fg, 0.16)

                    Row {
                        id: projChipRow

                        anchors.centerIn: parent
                        spacing: 4

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "folder"
                            color: root.fgDim
                            fontStyle: Tokens.font.icon.size(13).build()
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 108)
                            elide: Text.ElideRight
                            text: root.currentProject?.name ?? "~"
                            color: root.fg
                            font.pointSize: 7.6
                            font.weight: Font.DemiBold
                        }
                    }

                    MouseArea {
                        id: projChipArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.projects.length > 0)
                                root.projectIdx = (root.projectIdx + 1) % root.projects.length;
                            dockInput.forceActiveFocus();
                        }
                    }
                }

                // Champ texte principal (focus garanti au clic et à l'ouverture !)
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(160, commandDock.width - dockEnginesRow.width - projChip.width - goBtn.width - 42)
                    height: 36

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.IBeamCursor
                        onClicked: dockInput.forceActiveFocus()
                    }

                    TextInput {
                        id: dockInput

                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        color: root.fg
                        font.pointSize: 8.8
                        clip: true
                        selectByMouse: true
                        activeFocusOnPress: true
                        Keys.onEscapePressed: root.close()
                        onAccepted: {
                            root.submitDock(text);
                            text = "";
                        }

                        StyledText {
                            visible: dockInput.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.dockTarget === "ai"
                                ? I18n.tr("Parle à Katana AI : « Dis à AGY CLI de… », « Lance Codex sur… »")
                                : root.dockExistingAgent
                                    ? I18n.tr("Écrire en direct à %1 (%2)…").arg(Agents.kindName(root.dockTarget)).arg(root.dockExistingAgent.project)
                                    : I18n.tr("Lancer %1 sur %2 avec une mission…").arg(Agents.kindName(root.dockTarget)).arg(root.currentProject?.name ?? "~")
                            color: root.fgMute
                            font.pointSize: 8.3
                        }
                    }
                }

                // Bouton Envoyer / Lancer
                Rectangle {
                    id: goBtn

                    anchors.verticalCenter: parent.verticalCenter
                    width: goRow.implicitWidth + 20
                    height: 34
                    radius: 17
                    scale: goArea.pressed ? 0.94 : 1
                    color: Qt.alpha(root.dockTint, goArea.containsMouse ? 0.34 : 0.22)
                    border.width: 0.8
                    border.color: Qt.alpha(root.dockTint, 0.65)

                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Row {
                        id: goRow

                        anchors.centerIn: parent
                        spacing: 5

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.dockTarget === "ai" ? "auto_awesome" : (root.dockExistingAgent ? "send" : "play_arrow")
                            color: root.dockTint
                            fontStyle: Tokens.font.icon.size(15).build()
                            fill: 1
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.aiThinking
                                ? I18n.tr("…")
                                : root.dockTarget === "ai"
                                    ? I18n.tr("Ordonner")
                                    : root.dockExistingAgent
                                        ? I18n.tr("Envoyer")
                                        : I18n.tr("Lancer")
                            color: root.fg
                            font.pointSize: 8.1
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        id: goArea

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.submitDock(dockInput.text);
                            dockInput.text = "";
                            dockInput.forceActiveFocus();
                        }
                    }
                }
            }
        }
    }

    // ════════════════════ Sous-composants réutilisables ════════════════════

    component MiniSpinner: Item {
        id: ms

        property color tint
        property bool spinning
        property bool done
        property string letter
        property real size: 28
        readonly property bool animOn: ms.spinning && !ms.done

        width: size
        height: size

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(ms.tint, 0.16)
            border.width: 0.6
            border.color: Qt.alpha(ms.tint, 0.38)
        }

        Shape {
            anchors.fill: parent
            visible: !ms.done
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 2.4
                strokeColor: ms.tint
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap

                PathAngleArc {
                    centerX: ms.size / 2
                    centerY: ms.size / 2
                    radiusX: ms.size / 2 - 2
                    radiusY: ms.size / 2 - 2
                    startAngle: -90
                    sweepAngle: ms.animOn ? 125 : 360
                }
            }

            RotationAnimation on rotation {
                running: ms.animOn
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 1100
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: !ms.done
            text: ms.letter || "✦"
            color: ms.tint
            font.pointSize: ms.size >= 34 ? 10.5 : 8.8
            font.weight: Font.Black
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: ms.done
            text: "check"
            color: ms.tint
            fontStyle: Tokens.font.icon.size(ms.size >= 34 ? 17 : 14).build()
            fill: 1
        }
    }

    component ActionChip: Rectangle {
        id: ac

        property string label
        property string icon
        property color tint: root.fg
        property bool filled: false
        signal clicked

        width: acRow.implicitWidth + 16
        height: 24
        radius: 12
        scale: acArea.pressed ? 0.94 : 1
        color: filled
            ? Qt.alpha(tint, acArea.containsMouse ? 0.3 : 0.2)
            : Qt.alpha(tint, acArea.containsMouse ? 0.16 : 0.08)
        border.width: 0.5
        border.color: Qt.alpha(tint, filled ? 0.52 : 0.24)

        Behavior on scale { NumberAnimation { duration: 100 } }

        Row {
            id: acRow

            anchors.centerIn: parent
            spacing: 4

            MaterialIcon {
                visible: ac.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: ac.icon
                color: ac.filled ? ac.tint : root.fgDim
                fontStyle: Tokens.font.icon.size(12).build()
                fill: 1
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: ac.label
                color: ac.filled ? ac.tint : root.fg
                font.pointSize: 7.4
                font.weight: Font.Bold
            }
        }

        MouseArea {
            id: acArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ac.clicked()
        }
    }

    component FilterChip: Rectangle {
        id: fc

        property string label
        property int count: 0
        property bool selected: false
        property color tint: root.fg
        signal clicked

        width: fcTxt.implicitWidth + 16
        height: 24
        radius: 12
        color: selected ? Qt.alpha(tint, 0.22) : Qt.alpha(root.fg, fcArea.containsMouse ? 0.12 : 0.06)
        border.width: 0.5
        border.color: selected ? Qt.alpha(tint, 0.56) : Qt.alpha(root.fg, 0.14)

        StyledText {
            id: fcTxt

            anchors.centerIn: parent
            text: `${fc.label} (${fc.count})`
            color: fc.selected ? fc.tint : root.fgDim
            font.pointSize: 7.3
            font.weight: fc.selected ? Font.Bold : Font.DemiBold
            font.features: { "tnum": 1 }
        }

        MouseArea {
            id: fcArea

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fc.clicked()
        }
    }

    component KpiBox: Rectangle {
        id: kb

        property string label
        property string value
        property string sub
        property color tint: root.fg

        height: 60
        radius: 14
        color: Qt.alpha(kb.tint, 0.08)
        border.width: 0.5
        border.color: Qt.alpha(kb.tint, 0.22)

        Column {
            anchors.fill: parent
            anchors.margins: 9
            spacing: 1

            StyledText {
                text: kb.label
                color: root.fgDim
                font.pointSize: 6.5
                font.weight: Font.Black
                font.letterSpacing: 0.6
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: kb.value
                color: kb.tint
                font.pointSize: 11.5
                font.weight: Font.Black
                font.features: { "tnum": 1 }
            }
            StyledText {
                width: parent.width
                elide: Text.ElideRight
                text: kb.sub
                color: root.fgDim
                font.pointSize: 6.9
            }
        }
    }
}
