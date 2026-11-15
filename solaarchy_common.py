"""Shared by solaarchy-status.py, solaarchy-monitor.py and the add-on helpers:
the lock every device read takes, how a device is told apart and checked,
which hidraw nodes are HID++ (hidpp_nodes, paired_node), and whether another
program may be asking the same receivers (other_writers).

Standard library only at import time: the monitor never loads Solaar, and the
other helpers import this after their own guarded import of Solaar's library.
"""

import os
import re
import stat
import struct


# One read at a time from this user: overlapping reads can pick up each
# other's HID++ replies (see consistent).
#
# The lock lives only in a directory no one else can write to, never a shared
# one like /tmp: there another user could plant a symlink at the predictable
# name and have every refresh open (formerly: truncate) any file of this
# user's that the link points at.
def _private_dir(path):
    try:
        st = os.stat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o022


def _lock_dir():
    for d in (os.environ.get("XDG_RUNTIME_DIR"), f"/run/user/{os.getuid()}"):
        if d and _private_dir(d):
            return d
    # No usable runtime dir (e.g. run outside a login session): a private
    # directory of our own under the user's cache instead.
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    d = os.path.join(cache, "solaarchy")
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
    except OSError:
        return None
    return d if _private_dir(d) else None


def open_lock():
    d = _lock_dir()
    if d is None:
        raise OSError("no private directory for the status lock")
    path = os.path.join(d, "solaarchy-status.lock")
    # No O_TRUNC: the file's content is never used, only its flock. The first
    # run creates it with O_EXCL, so creating can never land on anything
    # already there; later runs reopen it, and either way it is checked below.
    flags = os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC
    try:
        fd = os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        fd = os.open(path, flags)
    st = os.fstat(fd)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1:
        os.close(fd)
        raise OSError(f"{d}/solaarchy-status.lock is not a private regular file")
    return fd


def online(dev):
    # Without a listener for receiver notifications, Solaar marks every paired
    # device online. Ping, as `solaar show` does, so a device that is switched
    # off or asleep is reported offline instead of as "no battery info".
    try:
        return bool(dev.ping())
    except Exception:  # NoSuchDevice: a pairing slot with nothing answering
        return False


def consistent(dev):
    """True if every feature slot this process looked up still answers the same.

    All Solaar processes use one fixed HID++ software id, so a reply is matched
    only by device, feature slot and function. When another process (the
    Solaar GUI setting a device up after it reconnects, say) asks the same
    device for a different feature at the same moment, this process can take
    that reply as its own and cache the wrong slot for, e.g., the battery.
    Asking again catches that: a clash twice in a row is very unlikely.
    """
    from logitech_receiver import hidpp20

    features = getattr(dev, "features", None)
    if not isinstance(features, hidpp20.FeaturesArray):
        return True  # HID++ 1.0 devices use fixed registers, not feature slots
    for feature, index in list(dict.items(features)):
        if index is None or int(feature) == 0:  # ROOT is always slot 0
            continue
        reply = dev.request(0x0000, struct.pack("!H", int(feature)))
        if reply is None or reply[0] != (index or 0):
            return False
    return True


def forget_features(dev):
    from logitech_receiver import hidpp20

    dev.features = hidpp20.FeaturesArray(dev)
    dev._backlight = None
    dev._led_effects = None


def safe(fn, fallback=None):
    try:
        return fn()
    except Exception:
        return fallback


def device_id(dev, path):
    # serial/unitId are the stable, per-unit identities. Below that, wpid is
    # only per-model, so two identical-model devices with neither serial nor
    # unitId (older HID++1.0 hardware) would otherwise collide onto the same
    # id and get merged into one entry; path:number (the receiver's hidraw
    # node plus this device's pairing slot, or a directly-connected device's
    # own node) disambiguates them and is available whenever wpid would be.
    # A device that hasn't answered yet (e.g. a Bluetooth keyboard waking up)
    # reports an all-zero serial/unitId: not an identity, skip it.
    serial = safe(lambda: dev.serial)
    if serial and serial.strip("0"):
        return serial
    unit_id = safe(lambda: dev.unitId)
    if unit_id and unit_id.strip("0"):
        return unit_id
    number = safe(lambda: dev.number)
    if path and number is not None:
        return f"{path}:{number}"
    return safe(lambda: dev.wpid)


# ---- HID++ node discovery, standard library only ----
#
# The same choice Solaar's hidapi.udev_impl._match makes, read straight from
# sysfs: a hidraw node whose report descriptor declares HID++ short (0x10,
# 6 bytes) or long (0x11, 19 bytes) input reports, or a Centurion transport
# (0x50/0x51, 63 bytes in and out), and that is not itself a device behind a
# receiver (a HID device whose parent is another HID device). Solaar does
# this through pyudev; with Solaar's library, that kept the resident monitor
# at ~46 MB, against ~13 MB now (see solaarchy-monitor.py).

_HID_DIR = re.compile(r"^[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}$")


def _report_sizes(desc):
    """({report id: input bits}, {output report ids}) from a HID report descriptor."""
    inputs, outputs = {}, set()
    size = count = 0
    report_id = 0
    stack = []
    i = 0
    while i < len(desc):
        prefix = desc[i]
        if prefix == 0xFE:  # long item: skip it whole
            if i + 1 >= len(desc):
                break
            i += 3 + desc[i + 1]
            continue
        n = (0, 1, 2, 4)[prefix & 3]
        value = int.from_bytes(desc[i + 1:i + 1 + n], "little")
        i += 1 + n
        kind, tag = (prefix >> 2) & 3, prefix >> 4
        if kind == 1:  # global
            if tag == 7:
                size = value
            elif tag == 9:
                count = value
            elif tag == 8:
                report_id = value
            elif tag == 10:
                stack.append((size, count, report_id))
            elif tag == 11 and stack:
                size, count, report_id = stack.pop()
        elif kind == 0:  # main
            if tag == 8:
                inputs[report_id] = inputs.get(report_id, 0) + size * count
            elif tag == 9:
                outputs.add(report_id)
    return inputs, outputs


def _is_hidpp(desc):
    inputs, outputs = _report_sizes(desc)
    if inputs.get(0x10) == 6 * 8 or inputs.get(0x11) == 19 * 8:
        return True
    return any(inputs.get(r) == 63 * 8 and r in outputs for r in (0x50, 0x51))


def hidpp_nodes():
    """Paths of the hidraw nodes Solaar's descriptor check accepts as receivers
    or devices. (Solaar also falls back to vendor and product ids when a
    descriptor won't parse; this skips such a node.)"""
    found = set()
    try:
        names = os.listdir("/sys/class/hidraw")
    except OSError:
        return found
    for name in names:
        try:
            hid = os.path.realpath(f"/sys/class/hidraw/{name}/device")
            if _HID_DIR.match(os.path.basename(os.path.dirname(hid))):
                continue  # behind a receiver; the receiver's node carries its reports
            with open(os.path.join(hid, "report_descriptor"), "rb") as f:
                if _is_hidpp(f.read()):
                    found.add(f"/dev/{name}")
        except OSError:
            continue
    return found


def paired_node(receiver_path, number):
    """The hidraw node of the device in slot `number` of a receiver, or None."""
    def phys(name):
        with open(f"/sys/class/hidraw/{name}/device/uevent") as f:
            for line in f:
                if line.startswith("HID_PHYS="):
                    return line.rstrip("\n").split("=", 1)[1]
        return None

    try:
        want = phys(os.path.basename(receiver_path))
        if not want:
            return None
        want = f"{want}:{number}"
        for name in os.listdir("/sys/class/hidraw"):
            try:
                if phys(name) == want:
                    return f"/dev/{name}"
            except OSError:
                continue
    except OSError:
        pass
    return None


# HID++ managers that usually run as root or another user, whose open files
# this process can't see: their name alone counts as contention.
_HIDPP_DAEMONS = {"logid", "ratbagd", "openlogi-agent"}


def other_writers(paths):
    """True if another process may be asking these HID++ nodes too: one of
    this user's has one of `paths` open for writing, or a known HID++ daemon
    runs (as root, say, where its open files can't be read)."""
    targets = set()
    for p in paths:
        try:
            st = os.stat(p)
            targets.add(st.st_rdev)
        except OSError:
            pass
    me = os.getpid()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == me:
            continue
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() in _HIDPP_DAEMONS:
                    return True
        except OSError:
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue  # gone, or another user's (known daemons are caught by name above)
        for fd in fds:
            try:
                if not os.readlink(f"{fd_dir}/{fd}").startswith("/dev/hidraw"):
                    continue
                if os.stat(f"{fd_dir}/{fd}").st_rdev not in targets:
                    continue
                with open(f"/proc/{pid}/fdinfo/{fd}") as f:
                    flags = next((int(line.split()[1], 8) for line in f if line.startswith("flags:")), 0)
                if flags & 3 != os.O_RDONLY:
                    return True
            except (OSError, ValueError):
                continue
    return False
