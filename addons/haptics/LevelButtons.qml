import QtQuick
import qs.Commons
import qs.Ui
import "events.js" as Events

// One device's haptic level: Off and four steps, Solaar's own 25/50/75/100.
// A level set elsewhere (60 from Solaar, say) lights the nearest button.
ButtonGroup {
  id: group

  property var view
  property var service
  property var device

  readonly property int level: service.level(device)
  function action(index) { return "haptics.level-" + Events.levels[index].value + ":" + device.id }

  focusable: false
  enabled: device.online
  opacity: enabled ? 1.0 : 0.55
  options: Events.levels.map(function(l) {
    return { "value": String(l.value), "label": l.label, "tooltip": l.value === 0 ? "Haptics off on this device" : "Level " + l.value }
  })
  value: level < 0 ? "" : String(Events.nearestLevel(level))
  foreground: view.fg
  fontFamily: view.fontFamily
  fontSize: Style.font.bodySmall
  cursorIndex: {
    for (var i = 0; i < Events.levels.length; i++)
      if (view.hasCursorOn(action(i))) return i
    return -1
  }
  onChanged: function(value) { view.runAction("haptics.level-" + value + ":" + device.id) }
  onHovered: function(index, h) { view.hoverAction(action(index), h) }
}
