/*
 *   Copyright 2012-2013 Daniel Nicoletti <dantti12@gmail.com>
 *   Copyright 2013, 2015 Kai Uwe Broulik <kde@privat.broulik.de>
 *
 *   This program is free software; you can redistribute it and/or modify
 *   it under the terms of the GNU Library General Public License as
 *   published by the Free Software Foundation; either version 2 or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details
 *
 *   You should have received a copy of the GNU Library General Public
 *   License along with this program; if not, write to the
 *   Free Software Foundation, Inc.,
 *   51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

import QtQuick 2.0
import QtQuick.Layouts 1.1
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 2.0 as Components
import org.kde.kquickcontrolsaddons 2.0

ColumnLayout {
    property alias enabled: pmCheckBox.checked

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: units.smallSpacing

        Components.CheckBox {
            id: pmCheckBox
            Layout.fillWidth: true
            text: i18nc("Minimize the length of this string as much as possible", "Allow automatic sleep and screen locking")
            checked: true
        }

        Components.ToolButton {
            iconSource: "configure"
            onClicked: batterymonitor.action_powerdevilkcm()
            tooltip: i18n("Configure Power Saving...")
            visible: batterymonitor.kcmsAuthorized
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.leftMargin: units.gridUnit + units.smallSpacing // width of checkbox and spacer
        spacing: units.smallSpacing

        InhibitionHint {
            Layout.fillWidth: true
            visible: pmSource.data["PowerDevil"] && pmSource.data["PowerDevil"]["Is Lid Present"] && !pmSource.data["PowerDevil"]["Triggers Lid Action"] ? true : false
            iconSource: "computer-laptop"
            text: i18nc("Minimize the length of this string as much as possible", "Your notebook is configured not to sleep when closing the lid while an external monitor is connected.")
        }

        Components.Label {
            id: inhibitionExplanation
            Layout.fillWidth: true
            // Don't need to show the inhibitions when power management
            // isn't enabled anyway
            visible: inhibitions.length > 0 && pmCheckBox.checked
            font: theme.smallestFont
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 3
            text: {
                if (inhibitions.length === 1) {
                    return i18n("An application is preventing sleep and screen locking:")
                } else if (inhibitions.length > 1) {
                    return i18np("%1 application is preventing sleep and screen locking:",
                                 "%1 applications are preventing sleep and screen locking:",
                                 inhibitions.length)
                } else {
                    return ""
                }
            }
        }
        Repeater {
            model: inhibitionExplanation.visible ? inhibitions.length : null

            InhibitionHint {
                Layout.fillWidth: true
                iconSource: inhibitions[index].Icon || ""
                text: inhibitions[index].Reason ?
                                                i18nc("Application name: reason for preventing sleep and screen locking", "%1: %2", inhibitions[index].Name, inhibitions[index].Reason)
                                                : i18nc("Application name: reason for preventing sleep and screen locking", "%1: unknown reason", inhibitions[index].Name)
            }
        }
    }
}

