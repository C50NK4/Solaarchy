.pragma library

// Bar icons for Solaarchy. Each icon is one SVG path, normalised to a height
// of 100 and filled even-odd in a single theme colour. `barScale` is its
// height in the bar as a share of the icon canvas; device icons derive it from
// one shared scale so filled and outline pairs, and all devices, keep equal
// stroke weights. Sources and licences: THIRD_PARTY.md.
//
// Solaarchy ships no vendor logos of its own. Anyone who wants one points the
// plugin at an SVG file they supply themselves; those become records of the
// same shape through custom(), so the bar, the picker and every sizing helper
// treat them exactly like a built-in icon.

var defaultId = "solaar"

var list = [
  {"id": "solaar", "label": "Solaar", "group": "solaar", "trademark": false, "credit": "Solaar icon by Daniel Pavel, CC BY-SA 3.0", "barScale": 0.8, "width": 100.0, "height": 100.0, "path": "M 17.98 0 C 8.02 0 0 8.02 0 17.98 L 0 82.02 C 0 91.98 8.02 100 17.98 100 L 82.02 100 C 91.98 100 100 91.98 100 82.02 L 100 17.98 C 100 8.02 91.98 0 82.02 0 L 17.98 0 Z M 36.17 12.57 L 46.31 30.13 C 47.51 29.91 48.74 29.78 50 29.78 C 51.26 29.78 52.49 29.91 53.69 30.13 L 63.83 12.57 L 75.49 19.31 L 65.34 36.87 C 66.94 38.73 68.19 40.9 69.03 43.26 L 89.33 43.26 L 89.33 56.74 L 69.03 56.74 C 68.19 59.1 66.94 61.27 65.34 63.13 L 75.49 80.69 L 63.83 87.43 L 53.69 69.87 C 52.49 70.09 51.26 70.22 50 70.22 C 48.74 70.22 47.51 70.09 46.31 69.87 L 36.17 87.43 L 24.51 80.69 L 34.66 63.13 C 33.06 61.27 31.81 59.1 30.97 56.74 L 10.67 56.74 L 10.67 43.26 L 30.97 43.26 C 31.81 40.9 33.06 38.73 34.66 36.87 L 24.51 19.31 L 36.17 12.57 Z M 63.48 50 C 63.48 57.45 57.45 63.48 50 63.48 C 42.55 63.48 36.52 57.45 36.52 50 C 36.52 42.55 42.55 36.52 50 36.52 C 57.45 36.52 63.48 42.55 63.48 50 Z"},
  {"id": "mouse", "label": "Mouse", "group": "device", "variant": "filled", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.85, "width": 68.29, "height": 100, "path": "M 34.146 100 q -14.268 0 -24.207 -9.939 T 0 65.854 v -24.39 h 68.293 v 24.39 q 0 14.268 -9.939 24.207 T 34.146 100 Z M 0 34.146 q 0 -13.171 8.72 -22.866 T 30.488 0.244 v 33.902 H 0 Z m 37.805 0 v -33.902 q 13.049 1.341 21.768 11.037 T 68.293 34.146 H 37.805 Z"},
  {"id": "keyboard", "label": "Keyboard", "group": "device", "variant": "filled", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.5805, "width": 142.86, "height": 100, "path": "M 10.714 100 q -4.286 0 -7.5 -3.304 T 0 89.286 v -78.571 q 0 -4.286 3.214 -7.5 t 7.5 -3.214 h 121.429 q 4.286 0 7.5 3.214 t 3.214 7.5 v 78.571 q 0 4.107 -3.214 7.411 T 132.143 100 H 10.714 Z m 28.571 -22.321 h 64.286 v -10.714 H 39.286 v 10.714 Z m -17.321 -22.321 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z M 21.964 33.036 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z"},
  {"id": "combo", "label": "Keyboard + mouse", "group": "device", "variant": "filled", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.85, "width": 173.17, "height": 100, "path": "M 7.317 100 q -2.927 0 -5.122 -2.256 T 0 92.683 v -53.659 q 0 -2.927 2.195 -5.122 t 5.122 -2.195 h 82.927 q 2.927 0 5.122 2.195 t 2.195 5.122 v 53.659 q 0 2.805 -2.195 5.061 T 90.244 100 H 7.317 Z m 19.512 -15.244 h 43.902 v -7.317 H 26.829 v 7.317 Z m -11.829 -15.244 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z M 15 54.268 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z M 139.024 100 q -14.268 0 -24.207 -9.939 T 104.878 65.854 v -24.39 h 68.293 v 24.39 q 0 14.268 -9.939 24.207 T 139.024 100 Z M 104.878 34.146 q 0 -13.171 8.72 -22.866 T 135.366 0.244 v 33.902 H 104.878 Z m 37.805 0 v -33.902 q 13.049 1.341 21.768 11.037 T 173.171 34.146 H 142.683 Z"},
  {"id": "mouse-outline", "label": "Mouse", "group": "device", "variant": "outline", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.85, "width": 68.29, "height": 100, "path": "M 34.146 100 q -14.39 0 -24.268 -9.878 t -9.878 -24.268 v -31.707 q 0 -14.39 9.878 -24.268 t 24.268 -9.878 q 14.39 0 24.268 9.878 t 9.878 24.268 v 31.707 q 0 14.39 -9.878 24.268 T 34.146 100 Z m 3.659 -65.854 h 23.171 q 0 -9.878 -6.463 -17.561 t -16.707 -9.024 v 26.585 Z m -30.488 0 h 23.171 v -26.585 q -10.244 1.341 -16.707 9.024 t -6.463 17.561 Z m 26.804 58.537 q 11.123 0 18.989 -7.848 Q 60.976 76.988 60.976 65.854 v -24.39 H 7.317 v 24.39 q 0 11.134 7.84 18.982 Q 22.998 92.683 34.121 92.683 Z m 0.026 -51.22 Z m 3.659 -7.317 Z m -7.317 0 Z m 3.659 7.317 Z"},
  {"id": "keyboard-outline", "label": "Keyboard", "group": "device", "variant": "outline", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.5805, "width": 142.86, "height": 100, "path": "M 10.714 100 q -4.286 0 -7.5 -3.304 T 0 89.286 v -78.571 q 0 -4.286 3.214 -7.5 t 7.5 -3.214 h 121.429 q 4.286 0 7.5 3.214 t 3.214 7.5 v 78.571 q 0 4.107 -3.214 7.411 T 132.143 100 H 10.714 Z m 0 -10.714 h 121.429 v -78.571 H 10.714 v 78.571 Z m 28.571 -11.607 h 64.286 v -10.714 H 39.286 v 10.714 Z m -17.321 -22.321 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z M 21.964 33.036 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 22.143 0 h 10.714 v -10.714 h -10.714 v 10.714 Z m 21.964 0 h 10.714 v -10.714 h -10.714 v 10.714 Z M 10.714 89.286 v -78.571 v 78.571 Z"},
  {"id": "combo-outline", "label": "Keyboard + mouse", "group": "device", "variant": "outline", "trademark": false, "credit": "Material Symbols (Google), outlined style, Apache 2.0", "barScale": 0.85, "width": 173.17, "height": 100, "path": "M 7.317 100 q -2.927 0 -5.122 -2.256 T 0 92.683 v -53.659 q 0 -2.927 2.195 -5.122 t 5.122 -2.195 h 82.927 q 2.927 0 5.122 2.195 t 2.195 5.122 v 53.659 q 0 2.805 -2.195 5.061 T 90.244 100 H 7.317 Z m 0 -7.317 h 82.927 v -53.659 H 7.317 v 53.659 Z m 19.512 -7.927 h 43.902 v -7.317 H 26.829 v 7.317 Z m -11.829 -15.244 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z M 15 54.268 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15.122 0 h 7.317 v -7.317 h -7.317 v 7.317 Z m 15 0 h 7.317 v -7.317 h -7.317 v 7.317 Z M 7.317 92.683 v -53.659 v 53.659 Z M 139.024 100 q -14.39 0 -24.268 -9.878 t -9.878 -24.268 v -31.707 q 0 -14.39 9.878 -24.268 t 24.268 -9.878 q 14.39 0 24.268 9.878 t 9.878 24.268 v 31.707 q 0 14.39 -9.878 24.268 T 139.024 100 Z m 3.659 -65.854 h 23.171 q 0 -9.878 -6.463 -17.561 t -16.707 -9.024 v 26.585 Z m -30.488 0 h 23.171 v -26.585 q -10.244 1.341 -16.707 9.024 t -6.463 17.561 Z m 26.804 58.537 q 11.123 0 18.989 -7.848 Q 165.854 76.988 165.854 65.854 v -24.39 H 112.195 v 24.39 q 0 11.134 7.84 18.982 Q 127.876 92.683 138.999 92.683 Z m 0.026 -51.22 Z m 3.659 -7.317 Z m -7.317 0 Z m 3.659 7.317 Z"},
]

// A user-supplied SVG from the custom icon folder, as an icon record shaped
// like the built-ins: `source` (a file to render) instead of `path`, and a
// width taken from the file's own aspect ratio, with the height normalised to
// 100 like every other icon, so the bar slot and the picker tiles size it
// through the same helpers.
function custom(name, source, aspect) {
  return {
    "id": "custom:" + name,
    "label": name,
    "group": "custom",
    "custom": true,
    "source": source,
    "barScale": 0.8,
    "width": 100 * (aspect > 0 ? aspect : 1),
    "height": 100
  }
}

// A user's SVG repainted as a flat white silhouette, which is what the bar
// tints. Colour has to be taken out of the file itself rather than left to the
// tinting effect: that effect scales the source's own brightness, so a black
// logo would stay black and a red one would come out washed out. Once
// everything is white, the tint is exactly the theme colour, whatever the file
// looked like. `none` is left alone, so a stroke-only outline stays an outline,
// and per-shape opacity is kept.
function flattenSvg(text) {
  if (!text) return ""
  var out = String(text)

  // CSS rules can repaint anything below, and rewriting them reliably is a
  // different job; drop them and let the attributes below decide.
  out = out.replace(/<style[\s\S]*?<\/style>/gi, "")

  // fill="..." / stroke="..." (also currentColor, url(#gradient), rgb(...)).
  out = out.replace(/\b(fill|stroke)\s*=\s*"([^"]*)"/gi, function(all, attr, value) {
    return value.trim().toLowerCase() === "none" ? all : attr + '="#ffffff"'
  })
  out = out.replace(/\b(fill|stroke)\s*=\s*'([^']*)'/gi, function(all, attr, value) {
    return value.trim().toLowerCase() === "none" ? all : attr + '="#ffffff"'
  })

  // The same properties inside style="fill:#123; stroke:url(#g)".
  out = out.replace(/\b(fill|stroke)\s*:\s*([^;"'}]+)/gi, function(all, prop, value) {
    return value.trim().toLowerCase() === "none" ? all : prop + ":#ffffff"
  })

  // Whatever carries no paint at all defaults to black, so paint the root
  // element white and let it inherit. Its own fill is dropped first: a second
  // fill attribute would make the document invalid and render nothing.
  out = out.replace(/<svg\b([^>]*)>/i, function(all, attrs) {
    var selfClosing = /\/\s*$/.test(attrs)
    attrs = attrs.replace(/\/\s*$/, "")
    attrs = attrs.replace(/\bfill\s*=\s*("[^"]*"|'[^']*')/gi, "")
    return "<svg" + attrs + ' fill="#ffffff"' + (selfClosing ? "/>" : ">")
  })

  return out
}

function byId(id) {
  for (var i = 0; i < list.length; i++)
    if (list[i].id === id) return list[i]
  return list[0]
}

// Icons of one group, optionally one variant ("filled" or "outline"), in list order.
function inGroup(group, variant) {
  return list.filter(function(icon) {
    return icon.group === group && (variant === undefined || icon.variant === variant)
  })
}

// An icon's height at a given base size, scaled by its own barScale (or 1
// for a missing icon/barScale) and rounded to a whole pixel.
function scaledHeight(icon, base) {
  return Math.round(base * ((icon && icon.barScale) || 1))
}

// The height that keeps a wide icon (combo, keyboard, logi...) at most as
// wide as `box`, shrinking it below `box` itself if needed; a square or
// narrow icon (solaar, mouse...) just renders at `box` unchanged. For a
// hero-sized icon sitting next to a fixed-width label column, rendering
// every icon at one fixed height would let a wide one eat into that
// column and truncate the title/meta text next to it.
function fitHeight(icon, box) {
  if (!icon) return box
  return Math.min(box, box * icon.height / icon.width)
}
