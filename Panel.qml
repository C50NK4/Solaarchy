import QtQuick
import qs.Commons
import qs.Ui
import "haptics.js" as Haptics
import "icons.js" as Icons

// Solaarchy panel. Loaded by BarWidget.qml, which owns the device state and
// injects itself as hostWidget; this file only draws that state.
Panel {
  id: root
  moduleName: "io.github.c50nk4.solaarchy"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var w: hostWidget

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  // w (hostWidget, i.e. BarWidget.qml) already derives this from bar; reuse
  // its value instead of re-deriving independently from the same bar.
  readonly property color urgent: w ? w.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property int cursorIndex: -1
  // "main": the devices; "icons": the bar icon picker sub-panel; "haptics":
  // the level of hapticDeviceId and the events that buzz; "wave": the
  // waveform picker for the event named by hapticEvent.
  property string page: "main"
  property string hapticDeviceId: ""
  property string hapticEvent: ""
  readonly property var hapticDevice: {
    if (!w) return null
    for (var i = 0; i < w.devices.length; i++)
      if (String(w.devices[i].id) === hapticDeviceId && w.devices[i].haptics) return w.devices[i]
    return null
  }
  // The device can drop out from under the page (its reading lost haptics).
  onHapticDeviceChanged: if ((page === "haptics" || page === "wave") && !hapticDevice) showPage("main")

  // Keyboard-cursor targets for the current page, in reading order.
  readonly property var actions: {
    if (page === "icons") {
      // Mirrors PanelContent.qml's picker sections and their order exactly
      // (SOLAAR, then DEVICES filled/outline, then YOUR OWN) so arrow-key
      // navigation always matches the tile grid it walks, rather than relying
      // on icons.js's flat list happening to be in that order.
      var pickerIcons = [Icons.byId("solaar")]
        .concat(Icons.inGroup("device", "filled"))
        .concat(Icons.inGroup("device", "outline"))
        .concat(w ? w.customIcons : [])
      var picker = ["back"]
      for (var i = 0; i < pickerIcons.length; i++) picker.push("icon:" + pickerIcons[i].id)
      // The "+" tile closes the grid, exactly as it is drawn.
      picker.push("icon-add")
      return picker
    }
    if (page === "haptics") {
      // Mirrors PanelContent.qml's haptics page: the level buttons, the alert
      // rows, the desktop rows and the fullscreen switch, as they are drawn.
      var haptic = ["back"]
      for (var l = 0; l < Haptics.levels.length; l++) haptic.push("level:" + Haptics.levels[l].value)
      var rows = Haptics.inGroup("alerts").concat(Haptics.inGroup("desktop"))
      for (var r = 0; r < rows.length; r++) haptic.push("event:" + rows[r].setting)
      haptic.push("pause")
      return haptic
    }
    if (page === "wave") {
      // The picker: Off, then the waveform tiles in their order.
      var picker2 = ["back", "wave:off"]
      var waves = Haptics.forDevice(hapticDevice ? hapticDevice.haptics : null)
      for (var k = 0; k < waves.length; k++) picker2.push("wave:" + waves[k].key)
      return picker2
    }
    var list = ["icons", "refresh", "solaar"]
    if (w) {
      for (var j = 0; j < w.devices.length; j++) {
        if (w.devices[j].backlight) list.push("backlight:" + w.devices[j].id)
        if (w.devices[j].haptics) list.push("haptics:" + w.devices[j].id)
      }
    }
    return list
  }

  function open() { root.controller.show() }
  function close() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function showPage(name) {
    page = name
    cursorIndex = -1
  }

  function showHaptics(device) {
    hapticDeviceId = String(device.id)
    showPage("haptics")
  }

  function showWavePicker(setting) {
    hapticEvent = setting
    showPage("wave")
  }

  // Back from a page: the picker returns to the haptics page it came from,
  // every other sub-page to the devices.
  function back() {
    showPage(page === "wave" ? "haptics" : "main")
  }

  function hasCursorOn(action) {
    return cursorIndex >= 0 && actions[cursorIndex] === action
  }

  function hoverAction(action, isHovered) {
    if (isHovered) cursorIndex = actions.indexOf(action)
  }

  function runAction(name) {
    if (name === "icons") showPage("icons")
    else if (name === "back") back()
    else if (name === "refresh") w.refresh()
    else if (name === "solaar") w.openSolaar()
    else if (name === "icon-add") w.pickCustomIcon()
    else if (name.indexOf("icon:") === 0) w.chooseIcon(name.slice(5))
    else if (name.indexOf("backlight:") === 0) {
      for (var i = 0; i < w.devices.length; i++)
        if (String(w.devices[i].id) === name.slice(10)) w.toggleBacklight(w.devices[i])
    }
    else if (name.indexOf("haptics:") === 0) {
      for (var j = 0; j < w.devices.length; j++)
        if (String(w.devices[j].id) === name.slice(8)) showHaptics(w.devices[j])
    }
    else if (name.indexOf("level:") === 0) w.setHapticLevel(hapticDevice, parseInt(name.slice(6), 10))
    else if (name.indexOf("event:") === 0) showWavePicker(name.slice(6))
    else if (name === "pause") w.setHapticPauseFullscreen(!w.hapticPauseFullscreen)
    else if (name.indexOf("wave:") === 0) w.setHapticEvent(hapticEvent, name.slice(5))
  }

  onOpenedChanged: {
    // Always start keyboard nav fresh on open. But only snap back to the
    // devices page on a real close: a Tab hand-off to another bar widget's
    // panel closes this one via closeForPopoutSwitch() first (which sets
    // popoutSwitchClosing before this fires), and Tabbing back should find
    // the icon picker exactly as it was left, not reset to "main".
    if (opened) { cursorIndex = -1; return }
    if (!popoutSwitchClosing) page = "main"
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    // The haptics pages run wider, so an event's name and its waveform fit
    // side by side on one row.
    contentWidth: panel.fittedContentWidth(Style.space(root.page === "haptics" || root.page === "wave" ? 330 : 290))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        var n = root.actions.length
        if (root.cursorIndex < 0) { root.cursorIndex = 0; return }
        var step = dy !== 0 ? dy : dx
        root.cursorIndex = ((root.cursorIndex + step) % n + n) % n
      }
      onActivateRequested: {
        if (root.cursorIndex >= 0) root.runAction(root.actions[root.cursorIndex])
      }
      // Escape on a sub-panel steps back to the devices first.
      onCloseRequested: root.page !== "main" ? root.back() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Built once the bar widget has injected itself, with both references
      // passed at creation so no binding ever sees them unset.
      Loader {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
      }
    }
  }

  onWChanged: {
    if (w && !content.item)
      content.setSource(Qt.resolvedUrl("PanelContent.qml"), { w: w, view: root })
  }
}
