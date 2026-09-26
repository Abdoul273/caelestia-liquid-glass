import QtQuick
import qs.services

// Apparition en cascade façon macOS des cartes d'une page du tableau de bord.
// Trouve les cartes toute seule (rectangles et éléments feuilles des layouts), les trie
// dans l'ordre de lecture et les fait monter en fondu l'une après l'autre.
// Une seule animation pilote tout (pas un objet par carte) : léger en CPU.
Item {
    id: root

    property Item target
    property int stagger: 38
    property int duration: 460
    property real rise: 14

    property real t
    property var entries: []

    function isCard(item: Item): bool {
        return item.radius !== undefined && item.color !== undefined && item.color.a > 0;
    }

    function collect(item: Item, depth: int): list<var> {
        const kids = [];
        for (const c of item.children)
            if (c.width > 0 && c.height > 0)
                kids.push(c);
        if (depth > 0 && (isCard(item) || kids.length === 0 || depth >= 4))
            return [item];
        let out = [];
        for (const c of kids)
            out = out.concat(collect(c, depth + 1));
        return out;
    }

    function play(): void {
        if (!Motion.enabled || !target)
            return;
        finish();
        const items = collect(target, 0);
        if (items.length < 2)
            return;
        const pos = it => it.mapToItem(root.target, 0, 0);
        items.sort((a, b) => {
            const pa = pos(a), pb = pos(b);
            return Math.abs(pa.y - pb.y) > 30 ? pa.y - pb.y : pa.x - pb.x;
        });
        entries = items.map((it, i) => {
            let tr = null;
            if (it.transform.length === 0) {
                tr = Qt.createQmlObject("import QtQuick; Translate {}", it);
                it.transform = [tr];
            }
            return {
                item: it,
                tr: tr,
                opacity: it.opacity,
                delay: i * stagger
            };
        });
        t = 0;
        apply();
        anim.duration = (entries.length - 1) * stagger + duration;
        anim.restart();
    }

    function ease(x: real): real {
        // Ressort court avec un soupçon de dépassement
        const c = 1.2;
        return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2);
    }

    function apply(): void {
        for (const e of entries) {
            const p = Math.max(0, Math.min(1, (t - e.delay) / duration));
            e.item.opacity = e.opacity * Math.min(1, p * 2);
            if (e.tr)
                e.tr.y = (1 - ease(p)) * rise;
        }
    }

    function finish(): void {
        anim.stop();
        for (const e of entries) {
            if (!e.item)
                continue;
            e.item.opacity = e.opacity;
            if (e.tr)
                e.tr.y = 0;
        }
        entries = [];
    }

    onTChanged: apply()

    NumberAnimation {
        id: anim

        target: root
        property: "t"
        from: 0
        to: duration
        easing.type: Easing.Linear
        onFinished: root.finish()
    }

    Component.onDestruction: finish()
}
