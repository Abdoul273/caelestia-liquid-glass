pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property string soundsDir: Paths.sounds

    function play(soundName: string): void {
        const filePath = `${soundsDir}/${soundName}.wav`;
        const proc = soundComp.createObject(root, {
            command: ["pw-play", filePath]
        });
        if (proc) {
            proc.running = true;
        }
    }

    function playNotification(): void {
        play("notification");
    }

    function playPlug(): void {
        play("plug");
    }

    function playUnplug(): void {
        play("unplug");
    }

    function playBatteryLow(): void {
        play("battery_low");
    }

    function playScreenshot(): void {
        play("screenshot");
    }

    function playDeviceConnect(): void {
        play("device_connect");
    }

    function playDeviceDisconnect(): void {
        play("device_disconnect");
    }

    component SoundProcess: Process {
        id: proc
        onExited: proc.destroy()
    }

    Component {
        id: soundComp
        SoundProcess {}
    }
}
