pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

Singleton {
    id: root

    property var pendingConnections: ({})

    function isBusy(device): bool {
        return !!device && (!!pendingConnections[device.address] || device.pairing
            || device.state === BluetoothDeviceState.Connecting
            || device.state === BluetoothDeviceState.Disconnecting);
    }

    function toggleConnection(device): void {
        if (!device || isBusy(device))
            return;
        if (device.connected)
            device.disconnect();
        else
            connectDevice(device);
    }

    function connectDevice(device): void {
        if (!device || isBusy(device) || device.blocked)
            return;
        if (device.paired || device.bonded || device.trusted) {
            device.trusted = true;
            device.connect();
            return;
        }
        const operation = pairComp.createObject(root, { device: device, address: device.address });
        const pending = Object.assign({}, pendingConnections);
        pending[device.address] = operation;
        pendingConnections = pending;
        operation.start();
    }

    function finishConnection(address): void {
        const pending = Object.assign({}, pendingConnections);
        delete pending[address];
        pendingConnections = pending;
    }

    // Keep pairing alive when its list delegate disappears, then connect
    // the profiles: pairing alone can leave a temporary, unusable link.
    component PairConnection: Item {
        id: operation

        required property BluetoothDevice device
        required property string address
        property bool finished: false
        property bool sawPairing: false

        function finish(): void {
            if (finished)
                return;
            finished = true;
            timeout.stop();
            root.finishConnection(address);
            destroy();
        }

        function connectPaired(): void {
            if (finished || !device || !device.paired || device.pairing)
                return;
            device.trusted = true;
            device.connect();
            finish();
        }

        function start(): void {
            timeout.start();
            device.pair();
        }

        Connections {
            target: operation.device
            function onPairedChanged(): void { operation.connectPaired(); }
            function onPairingChanged(): void {
                if (operation.device?.pairing)
                    operation.sawPairing = true;
                else
                    Qt.callLater(operation.completePairing);
            }
        }

        function completePairing(): void {
            if (finished)
                return;
            if (device?.paired)
                connectPaired();
            else if (sawPairing && !device?.pairing) {
                console.warn("Bluetooth : échec de l'appairage", address);
                finish();
            }
        }

        Timer {
            id: timeout
            interval: 60000
            onTriggered: {
                console.warn("Bluetooth : délai d'appairage dépassé", operation.address);
                if (operation.device?.pairing)
                    operation.device.cancelPair();
                operation.finish();
            }
        }
    }

    Component {
        id: pairComp
        PairConnection {}
    }

    // Completely unpair a Bluetooth device: drop trust, disconnect, remove
    // the BlueZ object, then wipe leftover cache via bluetoothctl so the
    // next pairing asks for the PIN/code again instead of silently failing.
    function forgetDevice(device): void {
        if (!device)
            return;

        const address = String(device.address || "");
        const adapterPath = device.adapter ? String(device.adapter.dbusPath || "") : "";
        const devicePath = String(device.dbusPath || "");
        const adapter = device.adapter;

        try {
            device.trusted = false;
        } catch (e) {}

        const remove = () => {
            try {
                device.forget();
            } catch (e) {}

            const proc = removeComp.createObject(root);
            proc.exec(["bash", "-lc", `
addr="$1"
adapter="$2"
path="$3"
if [ -n "$addr" ]; then
    bluetoothctl untrust "$addr" >/dev/null 2>&1 || true
    bluetoothctl disconnect "$addr" >/dev/null 2>&1 || true
    bluetoothctl remove "$addr" >/dev/null 2>&1 || true
fi
if [ -n "$adapter" ] && [ -n "$path" ]; then
    busctl call org.bluez "$adapter" org.bluez.Adapter1 RemoveDevice o "$path" >/dev/null 2>&1 || true
fi
`, "caelestia-bt-forget", address, adapterPath, devicePath]);

            if (adapter) {
                try {
                    adapter.discovering = true;
                } catch (e) {}
            }
        };

        if (device.connected) {
            try {
                device.connected = false;
            } catch (e) {}
            delayedRemove.callback = remove;
            delayedRemove.restart();
        } else {
            remove();
        }
    }

    Timer {
        id: delayedRemove

        property var callback: null

        interval: 250
        repeat: false
        onTriggered: {
            if (delayedRemove.callback)
                delayedRemove.callback();
            delayedRemove.callback = null;
        }
    }

    component RemoveProcess: Process {
        id: proc

        environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

        onExited: proc.destroy()
    }

    Component {
        id: removeComp

        RemoveProcess {}
    }
}
