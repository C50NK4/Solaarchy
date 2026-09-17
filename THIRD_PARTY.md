# Third-party material

Solaarchy's code is MIT licensed (see `LICENSE`). That license does not cover
the third-party artwork in `icons.js`: the bar icons are not all Solaarchy's
own. This file lists where each one comes from and on what terms.

Solaarchy ships no vendor logos or trademarked marks of any kind. A user who
wants one supplies the file themselves; see "Your own bar icon" in `README.md`.
Anything in that folder belongs to the user who put it there and is no part of
this project.

## Solaar icon (`solaar`, the default)

- **Source:** `share/solaar/icons/solaar-symbolic.svg` from
  [Solaar](https://github.com/pwr-Solaar/Solaar)
- **Author:** Daniel Pavel
- **License:** [Creative Commons Attribution-ShareAlike 3.0](https://creativecommons.org/licenses/by-sa/3.0/),
  as declared in the SVG's own metadata
- **Changes:** the gradient fill and outline stroke were removed so it draws in
  one theme colour, the centre dot's arc was rewritten as Bézier curves, and the
  shape was rescaled to a height of 100. The modified icon keeps the same
  CC BY-SA 3.0 license.

Solaarchy is not affiliated with or endorsed by the Solaar project. It uses
Solaar, which must be installed separately (GPL-2.0-or-later).

## Device icons (`mouse`, `keyboard`, `combo`, and their `-outline` versions)

- **Source:** [Material Symbols](https://fonts.google.com/icons) by Google,
  `@material-symbols/svg-400` 0.47.2, outlined style: `mouse` and `keyboard`,
  each in its filled and unfilled form
- **License:** [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- **Changes:** moved and rescaled on one shared scale so every device icon keeps
  the same stroke weight; `combo` and `combo-outline` place the keyboard and
  the mouse side by side, bottom-aligned, in one path.
