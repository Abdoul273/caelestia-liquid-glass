import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

ColumnLayout {
    spacing: Tokens.spacing.small

    StyledText {
        text: I18n.tr("Verr. Maj : %1").arg(Hypr.capsLock ? "Enabled" : "Disabled")
    }

    StyledText {
        text: I18n.tr("Verr. Num : %1").arg(Hypr.numLock ? "Enabled" : "Disabled")
    }
}
