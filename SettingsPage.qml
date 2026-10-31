import QtQuick
import qs.Commons
import qs.Ui

// The gear page: what applies to every device. Each device's own choices
// live in its drawer on the devices page.
Column {
  id: page

  // Set at creation by PanelContent.qml: the bar widget and the panel.
  property var w
  property var view

  width: parent ? parent.width : 0
  spacing: Style.space(14)

  PageHeader {
    view: page.view
    title: "Settings"
    backTooltip: "Back to devices"
  }

  PanelSeparator { foreground: page.view.fg }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "DARK HOURS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰖔"
      label: "Backlight at night"
      captionUrgent: page.w.twilightError !== ""
      caption: page.w.twilightError !== "" ? page.w.twilightError
        : page.w.backlitKeyboards.length === 0 ? "On at dusk, off at dawn. No backlit keyboard yet."
        : page.w.darkTimesText !== "" ? page.w.darkTimesText.charAt(0).toUpperCase() + page.w.darkTimesText.slice(1)
        : "On at dusk, off at dawn"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.darkHours
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("dark-toggle")
        onToggled: page.w.setDarkHours(!page.w.darkHours)
        onHovered: function(h) { page.view.hoverAction("dark-toggle", h) }
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅂"
        tooltipText: "Times, offset and location"
        foreground: page.view.fg
        fontFamily: page.view.fontFamily
        hasCursor: page.view.hasCursorOn("dark-page")
        onClicked: page.view.showPage("darkhours")
        onHovered: function(h) { page.view.hoverAction("dark-page", h) }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "NOTIFICATIONS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰂃"
      label: "Low battery"
      caption: "Once per charge"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyLowBattery
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-low")
        onToggled: page.w.saveSetting("notifyLowBattery", !page.w.notifyLowBattery)
        onHovered: function(h) { page.view.hoverAction("notify-low", h) }
      }
    }

    OptionRow {
      view: page.view
      glyph: "󰁺"
      label: "Warn below"
      caption: "Also turns the bar icon red"

      Stepper {
        anchors.verticalCenter: parent.verticalCenter
        view: page.view
        text: page.w.lowThreshold + " %"
        minusAction: "low-minus"
        plusAction: "low-plus"
        atMin: page.w.lowThreshold <= 5
        atMax: page.w.lowThreshold >= 50
        onMinus: page.w.stepSetting("lowThreshold", page.w.lowThreshold, -5, 5, 50)
        onPlus: page.w.stepSetting("lowThreshold", page.w.lowThreshold, 5, 5, 50)
      }
    }

    OptionRow {
      view: page.view
      glyph: "󱃍"
      label: "Critical battery"
      caption: "One more warning at " + page.w.criticalLevel + " %"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyCritical
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-critical")
        onToggled: page.w.saveSetting("notifyCritical", !page.w.notifyCritical)
        onHovered: function(h) { page.view.hoverAction("notify-critical", h) }
      }
    }

    OptionRow {
      view: page.view
      glyph: "󰌷"
      label: "Connections"
      caption: "Gone after 5 minutes without a link, and back again. Asleep and off look the same."

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.notifyConnection
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("notify-connection")
        onToggled: page.w.saveSetting("notifyConnection", !page.w.notifyConnection)
        onHovered: function(h) { page.view.hoverAction("notify-connection", h) }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "BAR"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    OptionRow {
      view: page.view
      glyph: "󰈉"
      label: "Hide when no receiver"
      caption: "Back as soon as one is plugged in"

      ToggleSwitch {
        anchors.verticalCenter: parent.verticalCenter
        checked: page.w.hideWhenDisconnected
        foreground: page.view.fg
        hasCursor: page.view.hasCursorOn("hide-bar")
        onToggled: page.w.saveSetting("hideWhenDisconnected", !page.w.hideWhenDisconnected)
        onHovered: function(h) { page.view.hoverAction("hide-bar", h) }
      }
    }
  }

  Column {
    visible: page.w.hiddenDevices.length > 0
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "HIDDEN DEVICES"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.w.hiddenDevices

      OptionRow {
        id: hiddenRow
        required property var modelData
        view: page.view
        glyph: page.w.kindIcon(modelData.kind)
        label: modelData.name

        PanelActionButton {
          anchors.verticalCenter: parent.verticalCenter
          iconText: "󰈈"
          tooltipText: "Show it again"
          foreground: page.view.fg
          fontFamily: page.view.fontFamily
          hasCursor: page.view.hasCursorOn("unhide:" + hiddenRow.modelData.id)
          onClicked: page.view.runAction("unhide:" + hiddenRow.modelData.id)
          onHovered: function(h) { page.view.hoverAction("unhide:" + hiddenRow.modelData.id, h) }
        }
      }
    }
  }

  Column {
    width: parent.width
    spacing: Style.space(10)

    PanelSectionHeader {
      text: "ADD-ONS"
      foreground: page.view.fg
      fontFamily: page.view.fontFamily
    }

    Repeater {
      model: page.w.addons

      OptionRow {
        required property var modelData
        view: page.view
        glyph: modelData.icon !== "" ? modelData.icon : "󰐱"
        label: modelData.name
        caption: page.w.categoryLabel(modelData.category)
          + (modelData.enabled ? (modelData.panel ? " · opens from a device's drawer" : " · in a device's drawer")
                               : " · turned off in Omarchy's plugins")
      }
    }

    // Known add-ons that aren't installed yet.
    Repeater {
      model: page.w.knownAddons.filter(function(k) {
        return !page.w.addons.some(function(a) { return a.category === k.category })
      })

      OptionRow {
        required property var modelData
        opacity: 0.5
        view: page.view
        glyph: "󰕦"
        label: modelData.label
        caption: "In development"
      }
    }

    Text {
      visible: page.w.addonErrors.length > 0
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: page.w.addonErrors.join("\n")
      color: page.view.urgent
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: "An add-on is an Omarchy plugin with a solaarchy-addon.json next to its manifest. "
        + "ADDONS.md in Solaarchy's repository shows how to write one."
      color: page.view.dim
      font.family: page.view.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
