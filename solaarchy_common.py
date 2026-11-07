"""Shared by solaarchy-status.py and the add-on helpers: the lock every device
read takes, and how a device is told apart and checked.

Standard library only at import time: a helper imports this after its own
guarded import of Solaar's library.
"""

import os
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
