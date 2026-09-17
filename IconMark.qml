import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "icons.js" as Icons

// One icon in a single colour: either a built-in from icons.js, drawn as a
// vector path, or a user-supplied SVG file (iconData from Icons.custom()),
// rendered from disk and tinted flat the way the shell tints symbolic tray
// icons. Both follow the theme colour and stay sharp at any scale. Callers set
// only the height; the width follows the icon.
Item {
  id: root

  property string iconId: Icons.defaultId
  // A custom icon record, drawn instead of iconId when set.
  property var iconData: null
  property color color: "white"

  readonly property var icon: iconData || Icons.byId(iconId)
  readonly property bool isCustom: !!icon.custom

  implicitHeight: 16
  implicitWidth: height * icon.width / icon.height

  Shape {
    visible: !root.isCustom
    width: root.icon.width
    height: root.icon.height
    scale: root.height / root.icon.height
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: -1
      fillColor: root.color
      fillRule: ShapePath.OddEvenFill
      PathSvg { path: root.icon.path || "" }
    }
  }

  Image {
    id: customImage
    anchors.fill: parent
    source: root.isCustom ? root.icon.source : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    smooth: true
    // Kept as a hidden layer so the effect can sample it as a texture; the
    // tint, not the file's own colours, is what ends up on screen.
    visible: false
    layer.enabled: root.isCustom
    sourceSize.height: Math.round(root.height * Screen.devicePixelRatio)
  }

  MultiEffect {
    anchors.fill: customImage
    source: customImage
    visible: root.isCustom
    // The source is already flat white (Icons.flattenSvg), so this lands on
    // exactly the theme colour instead of scaling the file's own brightness.
    colorization: 1.0
    colorizationColor: root.color
  }
}
