pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

Singleton {
    id: root

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
