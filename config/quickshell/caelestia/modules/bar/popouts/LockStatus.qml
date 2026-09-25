import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small

    StyledText {
        text: qsTr("Verr. Maj : %1").arg(Hypr.capsLock ? "Enabled" : "Disabled")
    }

    StyledText {
        text: qsTr("Verr. Num : %1").arg(Hypr.numLock ? "Enabled" : "Disabled")
    }
}
