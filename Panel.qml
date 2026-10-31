import QtQuick
import qs.Commons
import qs.Ui
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
  // "main": the devices; "icons": the bar icon picker; "settings": the gear
  // page; "addon:<id>": a built-in add-on's page, which goes back to wherever
  // it was opened from (Settings or a device's drawer).
  property string page: "main"
  property string backPage: "main"
  // The device whose drawer is open, by id; "" for none.
  property string drawerId: ""
  // Settings' notification switches, folded away until asked for.
  property bool notificationsOpen: false

  // Keyboard-cursor targets for the current page, in reading order.
  readonly property var actions: {
    if (page === "icons") {
      // Mirrors PanelContent.qml's picker sections and their order exactly
      // (SOLAAR, then the DEVICES rows, each led by its auto pick, then YOUR
      // OWN) so arrow-key navigation always matches the tile grid it walks,
      // rather than relying on icons.js's flat list happening to be in that
      // order.
      var pickerIcons = [Icons.byId("solaar")]
        .concat(Icons.deviceRow("filled"))
        .concat(Icons.deviceRow("outline"))
        .concat(w ? w.customIcons : [])
      var picker = ["back"]
      for (var i = 0; i < pickerIcons.length; i++) picker.push("icon:" + pickerIcons[i].id)
      // The "+" tile closes the grid, exactly as it is drawn.
      picker.push("icon-add")
      return picker
    }
    if (page === "settings") {
      var settings = ["back"]
      if (!w) return settings
      for (var b = 0; b < w.builtins.length; b++) {
        settings.push("addon-on:" + w.builtins[b].id)
        if (w.builtins[b].page !== "") settings.push("addon-page:" + w.builtins[b].id)
      }
      settings.push("notify-more")
      if (notificationsOpen)
        settings.push("notify-low", "low-minus", "low-plus", "notify-critical", "notify-connection")
      settings.push("hide-bar")
      for (var h = 0; h < w.hiddenDevices.length; h++) settings.push("unhide:" + w.hiddenDevices[h].id)
      for (var c = 0; c < w.curatedAddons.length; c++) {
        var curated = w.curatedAddons[c]
        if (w.installedAddon(curated.id)) settings.push("addon-toggle:" + curated.id)
        else {
          if (curated.repo) settings.push("link:" + curated.repo)
          if (curated.page) settings.push("link:" + curated.page)
        }
      }
      for (var o = 0; o < w.otherAddons.length; o++) settings.push("addon-toggle:" + w.otherAddons[o].id)
      return settings
    }
    if (page.indexOf("addon:") === 0) {
      var service = w ? w.services[page.slice(6)] : null
      return ["back"].concat(service && service.pageActions ? service.pageActions : [])
    }
    var list = ["icons", "settings", "refresh", "solaar"]
    if (w) {
      for (var j = 0; j < w.shown.length; j++) {
        var d = w.shown[j]
        if (d.backlight) list.push("backlight:" + d.id)
        list.push("drawer:" + d.id)
        if (String(d.id) !== drawerId) continue
        var sections = w.drawerSections(d).sections
        for (var s = 0; s < sections.length; s++) {
          for (var a = 0; a < sections[s].addons.length; a++) {
            var addon = sections[s].addons[a]
            var own = w.services[addon.id]
            if (own && typeof own.drawerActions === "function") list = list.concat(own.drawerActions(d))
            else if (addon.panel) list.push("addon:" + addon.id + ":" + d.id)
          }
        }
        list.push("hide:" + d.id)
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
    if (name.indexOf("addon:") === 0 && page.indexOf("addon:") !== 0) backPage = page
    page = name
    cursorIndex = -1
    scroll.contentY = 0
    // Leaving a page from a text field on it must not leave the keys with a
    // hidden field.
    restoreFocus()
  }

  function goBack() { showPage(page.indexOf("addon:") === 0 ? backPage : "main") }

  function toggleDrawer(id) {
    drawerId = drawerId === String(id) ? "" : String(id)
  }

  // On a short screen the card scrolls: keep the cursor's control in view.
  // Every cursor target carries a hasCursor flag, so one walk finds it.
  function revealCursor() {
    var hit = cursorItem(content.item)
    if (!hit) return
    var y = hit.mapToItem(content, 0, 0).y
    var pad = Style.space(8)
    if (y - pad < scroll.contentY) scroll.contentY = Math.max(0, y - pad)
    else if (y + hit.height + pad > scroll.contentY + scroll.height)
      scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, y + hit.height + pad - scroll.height))
  }

  function cursorItem(item) {
    if (!item || !item.visible) return null
    if (item.hasCursor === true) return item
    for (var i = 0; i < item.children.length; i++) {
      var found = cursorItem(item.children[i])
      if (found) return found
    }
    return null
  }

  onCursorIndexChanged: if (cursorIndex >= 0 && scroll.interactive) Qt.callLater(revealCursor)

  // After typing in a text field: arrows and Enter drive the cursor again.
  function restoreFocus() { keyCatcher.forceActiveFocus() }

  function hasCursorOn(action) {
    return cursorIndex >= 0 && actions[cursorIndex] === action
  }

  function hoverAction(action, isHovered) {
    if (isHovered) cursorIndex = actions.indexOf(action)
  }

  // Two links to one unit share an id; prefer the online one, so a lookup
  // never stops on the asleep receiver slot.
  function deviceById(id) {
    var chosen = null
    for (var i = 0; i < w.shown.length; i++) {
      if (String(w.shown[i].id) !== id) continue
      if (!chosen || w.shown[i].online) chosen = w.shown[i]
    }
    return chosen
  }

  function runAction(name) {
    var colon = name.indexOf(":")
    var arg = colon >= 0 ? name.slice(colon + 1) : ""
    var verb = colon >= 0 ? name.slice(0, colon) : name
    var device = arg !== "" && ["icon", "addon", "addon-toggle", "link", "addon-on", "addon-page"].indexOf(verb) < 0
      ? deviceById(arg) : null
    if (verb === "icons") showPage("icons")
    else if (verb === "settings") showPage("settings")
    else if (verb === "back") goBack()
    else if (verb === "refresh") w.refresh()
    else if (verb === "solaar") w.openSolaar()
    else if (verb === "icon-add") w.pickCustomIcon()
    else if (verb === "icon") w.chooseIcon(arg)
    else if (verb === "backlight") { if (device && device.backlight) w.toggleBacklight(device) }
    else if (verb === "drawer") toggleDrawer(arg)
    else if (verb === "link") w.openLink(arg)
    else if (verb === "addon-toggle") {
      var addon = w.installedAddon(arg)
      if (addon) w.setAddonEnabled(addon, !addon.enabled)
    }
    else if (verb === "hide") {
      if (device) { drawerId = ""; w.setHidden(device, true) }
    }
    else if (verb === "unhide") {
      for (var i = 0; i < w.hiddenDevices.length; i++)
        if (String(w.hiddenDevices[i].id) === arg) w.setHidden(w.hiddenDevices[i], false)
    }
    else if (verb === "addon") {
      // "addon:<add-on id>:<device id>"; add-on ids have no colon.
      var cut = arg.indexOf(":")
      var target = deviceById(arg.slice(cut + 1))
      for (var k = 0; k < w.addons.length; k++)
        if (w.addons[k].id === arg.slice(0, cut) && target) w.openAddonPanel(w.addons[k], target)
    }
    else if (verb === "addon-on") {
      var builtin = w.builtinById(arg)
      if (builtin) w.setBuiltinOn(builtin, !w.addonOn(builtin))
    }
    else if (verb === "addon-page") showPage("addon:" + arg)
    else if (verb.indexOf(".") > 0) {
      // A built-in add-on's own control: "<add-on id>.<verb>[:<device id>]".
      var service = w.services[verb.slice(0, verb.indexOf("."))]
      if (service) service.run(verb.slice(verb.indexOf(".") + 1), device)
    }
    else if (verb === "notify-more") notificationsOpen = !notificationsOpen
    else if (verb === "notify-low") w.saveSetting("notifyLowBattery", !w.notifyLowBattery)
    else if (verb === "notify-critical") w.saveSetting("notifyCritical", !w.notifyCritical)
    else if (verb === "notify-connection") w.saveSetting("notifyConnection", !w.notifyConnection)
    else if (verb === "hide-bar") w.saveSetting("hideWhenDisconnected", !w.hideWhenDisconnected)
    else if (verb === "low-minus") w.stepSetting("lowThreshold", w.lowThreshold, -5, 5, 50)
    else if (verb === "low-plus") w.stepSetting("lowThreshold", w.lowThreshold, 5, 5, 50)
    // An action that adds or drops others (a drawer, the reset button next
    // to a switch) keeps the cursor on the control it was on.
    if (cursorIndex >= 0 && actions.indexOf(name) >= 0) cursorIndex = actions.indexOf(name)
  }

  onOpenedChanged: {
    // Always start keyboard nav fresh on open. But only snap back to the
    // devices page on a real close: a Tab hand-off to another bar widget's
    // panel closes this one via closeForPopoutSwitch() first (which sets
    // popoutSwitchClosing before this fires), and Tabbing back should find
    // the panel exactly as it was left, not reset to "main".
    if (opened) { cursorIndex = -1; return }
    if (!popoutSwitchClosing) {
      page = "main"
      drawerId = ""
      notificationsOpen = false
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(290))
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
      // Escape on a sub-page steps back first.
      onCloseRequested: root.page !== "main" ? root.goBack() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      // Scrolls only when the card is clamped to a short screen (Settings
      // with add-ons, several open sections), as the stock panels do.
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        // Built once the bar widget has injected itself, with both references
        // passed at creation so no binding ever sees them unset.
        Loader {
          id: content
          width: scroll.width
        }
      }
    }
  }

  onWChanged: {
    if (w && !content.item)
      content.setSource(Qt.resolvedUrl("PanelContent.qml"), { w: w, view: root })
  }
}
