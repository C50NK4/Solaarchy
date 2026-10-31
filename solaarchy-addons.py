#!/usr/bin/env python3
"""Solaarchy: list the installed Solaarchy add-ons as JSON.

An add-on is an ordinary Omarchy plugin with a solaarchy-addon.json next to
its manifest.json (see addons/ADDONS.md). Prints one JSON line:
  {"addons": [{"id", "name", "dir", "enabled", "category", "features",
               "label", "icon", "drawer", "panel"}], "errors": ["..."]}
"drawer" is the add-on's drawer QML as an absolute path, "" for none; "panel"
says whether it has a floating panel to summon. Read-only: it reads files and
asks the shell which plugins are enabled.

--test runs the self-check.
"""

import json
import os
import subprocess
import sys

API = 1
CATEGORIES = ("lighting", "haptics", "buttons", "pointer", "keyboard", "easyswitch")
SELF = "io.github.c50nk4.solaarchy"


def enabled_ids():
    """Ids the shell has enabled; None when it can't be asked (then none count)."""
    try:
        out = subprocess.run(["omarchy-shell", "shell", "listPlugins"],
                             capture_output=True, text=True, timeout=5).stdout
        return {p["id"] for p in json.loads(out) if isinstance(p, dict) and p.get("enabled")}
    except Exception:
        return None


def _inside(root, rel):
    """rel as an absolute path under root, or None for anything that leaves it."""
    if not isinstance(rel, str) or not rel or os.path.isabs(rel):
        return None
    path = os.path.normpath(os.path.join(root, rel))
    return path if path.startswith(os.path.normpath(root) + os.sep) else None


def read_addon(folder):
    """(add-on dict, None), (None, error text), or (None, None) for a plain plugin."""
    spec_path = os.path.join(folder, "solaarchy-addon.json")
    if not os.path.isfile(spec_path):
        return None, None
    name = os.path.basename(folder)
    try:
        with open(os.path.join(folder, "manifest.json")) as f:
            manifest = json.load(f)
        with open(spec_path) as f:
            spec = json.load(f)
    except Exception as e:
        return None, f"{name}: {e}"
    if not isinstance(manifest, dict) or not isinstance(spec, dict):
        return None, f"{name}: manifest.json and solaarchy-addon.json must be objects"
    pid = manifest.get("id")
    if not isinstance(pid, str) or not pid or pid == SELF:
        return None, f"{name}: manifest.json has no usable id"
    if spec.get("api") != API:
        return None, f"{pid}: solaarchy-addon.json api {spec.get('api')!r}, this Solaarchy reads api {API}"
    if spec.get("category") not in CATEGORIES:
        return None, f"{pid}: category must be one of {', '.join(CATEGORIES)}"
    features = spec.get("features", [])
    if not isinstance(features, list) or not all(isinstance(x, str) for x in features):
        return None, f"{pid}: features must be a list of Solaar feature names"
    drawer = ""
    if spec.get("drawer"):
        drawer = _inside(folder, spec["drawer"])
        if not drawer or not os.path.isfile(drawer):
            return None, f"{pid}: drawer {spec['drawer']!r} is not a file in the plugin folder"
    entry = (manifest.get("entryPoints") or {}).get("panel")
    panel = "panel" in (manifest.get("kinds") or []) and bool(_inside(folder, entry))
    label = spec.get("label") if isinstance(spec.get("label"), str) else ""
    return {
        "id": pid,
        "name": str(manifest.get("name") or pid),
        "dir": folder,
        "enabled": False,
        "category": spec["category"],
        "features": features,
        "label": label or str(manifest.get("name") or pid),
        "icon": spec.get("icon") if isinstance(spec.get("icon"), str) else "",
        "drawer": drawer,
        "panel": panel,
    }, None


def main(plugins_dir):
    addons, errors = [], []
    try:
        folders = sorted(os.listdir(plugins_dir))
    except OSError:
        folders = []
    for entry in folders:
        if entry.startswith("."):
            continue
        addon, error = read_addon(os.path.join(plugins_dir, entry))
        if error:
            errors.append(error)
        if addon:
            addons.append(addon)
    if addons:
        enabled = enabled_ids()
        if enabled is None:
            errors.append("could not ask the shell which plugins are enabled")
        for a in addons:
            a["enabled"] = bool(enabled) and a["id"] in enabled
    return {"addons": addons, "errors": errors}


def test():
    import tempfile
    with tempfile.TemporaryDirectory() as root:
        def plugin(name, manifest, spec, files=()):
            d = os.path.join(root, name)
            os.mkdir(d)
            with open(os.path.join(d, "manifest.json"), "w") as f:
                json.dump(manifest, f)
            if spec is not None:
                with open(os.path.join(d, "solaarchy-addon.json"), "w") as f:
                    json.dump(spec, f)
            for file in files:
                open(os.path.join(d, file), "w").close()
            return d

        good = plugin("good", {"id": "x.haptics", "name": "Haptics", "kinds": ["panel"],
                               "entryPoints": {"panel": "Panel.qml"}},
                      {"api": 1, "category": "haptics", "features": ["HAPTIC"], "drawer": "Drawer.qml"},
                      ["Panel.qml", "Drawer.qml"])
        plugin("plain", {"id": "x.plain"}, None)
        plugin("escape", {"id": "x.escape"}, {"api": 1, "category": "haptics", "drawer": "../good/Drawer.qml"})
        plugin("future", {"id": "x.future"}, {"api": 2, "category": "haptics"})
        plugin("nocat", {"id": "x.nocat"}, {"api": 1, "category": "toaster"})
        plugin("self", {"id": SELF}, {"api": 1, "category": "lighting"})
        global enabled_ids
        enabled_ids = lambda: {"x.haptics"}
        doc = main(root)
        assert [a["id"] for a in doc["addons"]] == ["x.haptics"], doc
        a = doc["addons"][0]
        assert a["enabled"] and a["panel"] and a["drawer"] == os.path.join(good, "Drawer.qml"), a
        assert a["label"] == "Haptics" and a["features"] == ["HAPTIC"], a
        assert len(doc["errors"]) == 4, doc["errors"]  # escape, future, nocat, self
        assert main(os.path.join(root, "missing")) == {"addons": [], "errors": []}
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        test()
        sys.exit(0)
    try:
        print(json.dumps(main(os.path.expanduser("~/.config/omarchy/plugins"))))
    except Exception as e:
        print(json.dumps({"addons": [], "errors": [str(e)]}))
