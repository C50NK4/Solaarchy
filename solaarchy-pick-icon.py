#!/usr/bin/env python3
"""Ask for an SVG with a native file dialog and put it in the icon folder.

Called by BarWidget.qml when the "+" tile in the bar icon picker is clicked.
Prints the installed file's name, without the .svg, on stdout; that is what
the widget stores in its `customIcon` setting. Exit codes: 0 chosen, 1
cancelled, 2 something went wrong (message on stderr, shown in the panel).

GTK is not an extra dependency: Solaar itself is a GTK application, so any
machine that can run Solaarchy already has python-gobject and gtk3.
"""

import os
import re
import shutil
import sys

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402  (must follow require_version)

# An icon that is not really an SVG would render as an empty bar slot with no
# hint why, so check the file actually starts like one before copying it in.
SVG_START = re.compile(rb"^(\xef\xbb\xbf)?\s*(<\?xml[^>]*\?>\s*|<!--.*?-->\s*|<!DOCTYPE[^>]*>\s*)*<svg\b",
                       re.S | re.I)


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(2)


def unique_path(folder, name):
    """`name`.svg in `folder`, with -2, -3... appended if that is taken."""
    candidate = os.path.join(folder, name + ".svg")
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(folder, "%s-%d.svg" % (name, n))
        n += 1
    return candidate


def choose():
    dialog = Gtk.FileChooserDialog(title="Choose an SVG for the Solaarchy bar icon",
                                   action=Gtk.FileChooserAction.OPEN)
    dialog.add_buttons(Gtk.STOCK_CANCEL, Gtk.ResponseType.CANCEL,
                       Gtk.STOCK_OPEN, Gtk.ResponseType.OK)

    svg = Gtk.FileFilter()
    svg.set_name("SVG images")
    svg.add_pattern("*.svg")
    svg.add_mime_type("image/svg+xml")
    dialog.add_filter(svg)

    start = os.path.expanduser("~/Downloads")
    dialog.set_current_folder(start if os.path.isdir(start) else os.path.expanduser("~"))

    response = dialog.run()
    chosen = dialog.get_filename() if response == Gtk.ResponseType.OK else None
    dialog.destroy()
    # Let the dialog actually disappear before this process exits.
    while Gtk.events_pending():
        Gtk.main_iteration()
    return chosen


def main():
    if len(sys.argv) != 2:
        fail("usage: solaarchy-pick-icon.py <icon-folder>")
    folder = os.path.expanduser(sys.argv[1])

    chosen = choose()
    if not chosen:
        sys.exit(1)

    try:
        with open(chosen, "rb") as fh:
            head = fh.read(4096)
    except OSError as e:
        fail("Could not read %s: %s" % (os.path.basename(chosen), e.strerror))

    if not SVG_START.search(head):
        fail("%s does not look like an SVG file" % os.path.basename(chosen))

    # The name becomes a file name, a setting value and the tile's label. Only
    # what would actually cause trouble is replaced (spaces, separators,
    # control characters), so "Ünïcode.svg" keeps its letters.
    name = re.sub(r"\.svg$", "", os.path.basename(chosen), flags=re.I)
    name = re.sub(r"\s+", "-", name)
    name = re.sub(r"[/\\\x00-\x1f]+", "", name)
    name = name.strip(" .-")[:64].strip(" .-") or "icon"

    try:
        os.makedirs(folder, exist_ok=True)
        target = unique_path(folder, name)
        shutil.copyfile(chosen, target)
    except OSError as e:
        fail("Could not copy the icon: %s" % e.strerror)

    print(re.sub(r"\.svg$", "", os.path.basename(target)))


if __name__ == "__main__":
    main()
