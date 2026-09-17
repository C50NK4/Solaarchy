#!/usr/bin/env python3
"""Solaarchy: print battery and backlight state of Logitech HID++ devices as JSON.

Read-only: it goes through Solaar's own library (python-solaar, official repos)
and the hidraw access Solaar's udev rule already grants. No device setting is
changed and Solaar's configuration file is never written; backlight changes go
through `solaar config` so the running Solaar GUI records them and does not
undo them when the keyboard wakes.

Output: {"receivers": [...], "devices": [...], "warnings": [...]}, or
{"error": "..."} when nothing at all could be read.
"""

import fcntl
import json
import os
import signal
import struct
import sys
import time

_stdout = sys.stdout

# Filled in as the scan goes, so a timeout can still report what was found.
_receivers = []
_devices = []
_warnings = []


def _emit(doc):
    _stdout.write(json.dumps(doc) + "\n")
    _stdout.flush()


def _result():
    if not _devices and not _receivers and _warnings:
        return {"error": "; ".join(_warnings)}
    return {"receivers": _receivers, "devices": _devices, "warnings": _warnings}


def _timeout(*_):
    _warnings.append("timed out before every device answered")
    _emit(_result())
    os._exit(1)


# A receiver that stops answering must not leave a helper hanging behind the bar.
signal.signal(signal.SIGALRM, _timeout)
signal.alarm(20)


# Solaar prints warnings (e.g. about Wayland rules) while importing; keep them
# off stdout so the shell only ever sees the JSON document.
sys.stdout = sys.stderr
try:
    import solaar.configuration as _solaar_config
    from logitech_receiver import base
    from logitech_receiver import hidpp20
    from logitech_receiver.common import BatteryLevelApproximation
    from logitech_receiver.common import BatteryStatus
    from logitech_receiver.hidpp20_constants import SupportedFeature
    from logitech_receiver.receiver import Receiver
    from solaar.cli import _receivers_and_devices
except Exception as e:  # Solaar missing or incompatible
    _emit({"error": f"solaar library unavailable: {e}"})
    sys.exit(1)

# Outside the GUI, Solaar's library saves its configuration file immediately
# whenever it caches something about a device. That would race the running
# Solaar GUI, which rewrites the same file, so saving is switched off here.
_solaar_config.save = lambda *args, **kwargs: None
_solaar_config.do_save = lambda *args, **kwargs: None

# One read at a time from this user: overlapping reads can pick up each
# other's HID++ replies (see _consistent).
_lock_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "solaarchy-status.lock")
_lock = open(_lock_path, "w")
fcntl.flock(_lock, fcntl.LOCK_EX)  # the 20 s alarm bounds the wait
signal.alarm(20)  # and the read itself gets a fresh 20 s


def _battery(dev):
    # The whole reply is guarded, not just dev.battery(): an unexpected
    # battery object shape (e.g. .status.name or .charging() raising) must
    # only cost this device its battery reading, not the entire entry (name,
    # online state, path) that _device() builds around it — _scan() drops
    # the whole device on an uncaught exception here.
    try:
        b = dev.battery()
        if b is None or b.level is None:
            return None
        level = int(b.level)
        return {
            "level": level,
            "approximate": isinstance(b.level, BatteryLevelApproximation),
            "status": b.status.name.lower() if b.status is not None else "unknown",
            "charging": b.charging() and b.status != BatteryStatus.FULL,
            "full": b.status == BatteryStatus.FULL,
        }
    except Exception:
        return None


def _backlight(dev):
    try:
        if not dev.features or SupportedFeature.BACKLIGHT2 not in dev.features:
            return None
        bl = dev.backlight
        result = {
            "enabled": bool(bl.enabled),
            # Keyboards with an ambient light sensor switch on to "Automatic".
            "automatic": bool(getattr(bl, "auto_supported", False)),
            "levels": None,
            "level": None,
        }
    except Exception:
        return None
    # Best-effort only, same reasoning as above: a malformed/short
    # getBacklightInfo reply shouldn't discard the enabled/automatic state
    # already read.
    try:
        info = dev.feature_request(SupportedFeature.BACKLIGHT2, 0x20)
        if info:
            result["levels"] = info[0]
            # Byte 2 of getBacklightInfo tracks the level the firmware picked
            # (0 while disabled); informational only.
            result["level"] = info[2]
    except Exception:
        pass
    return result


def _online(dev):
    # Without a listener for receiver notifications, Solaar marks every paired
    # device online. Ping, as `solaar show` does, so a device that is switched
    # off or asleep is reported offline instead of as "no battery info".
    try:
        return bool(dev.ping())
    except Exception:  # NoSuchDevice: a pairing slot with nothing answering
        return False


def _consistent(dev):
    """True if every feature slot this process looked up still answers the same.

    All Solaar processes use one fixed HID++ software id, so a reply is matched
    only by device, feature slot and function. When another process (the
    Solaar GUI setting a device up after it reconnects, say) asks the same
    device for a different feature at the same moment, this process can take
    that reply as its own and cache the wrong slot for, e.g., the battery.
    Asking again catches that: a clash twice in a row is very unlikely.
    """
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


def _forget_features(dev):
    dev.features = hidpp20.FeaturesArray(dev)
    dev._backlight = None


def _safe(fn, fallback=None):
    try:
        return fn()
    except Exception:
        return fallback


def _device_id(dev, path):
    # serial/unitId are the stable, per-unit identities. Below that, wpid is
    # only per-model, so two identical-model devices with neither serial nor
    # unitId (older HID++1.0 hardware) would otherwise collide onto the same
    # id and get merged into one entry; path:number (the receiver's hidraw
    # node plus this device's pairing slot, or a directly-connected device's
    # own node) disambiguates them and is available whenever wpid would be.
    serial = _safe(lambda: dev.serial)
    if serial:
        return serial
    unit_id = _safe(lambda: dev.unitId)
    if unit_id:
        return unit_id
    number = _safe(lambda: dev.number)
    if path and number is not None:
        return f"{path}:{number}"
    return _safe(lambda: dev.wpid)


def _identity(dev):
    """(name, fullName, kind), the same way whether read online or offline."""
    return (
        (_safe(lambda: dev.codename or dev.name) or "").strip(),
        _safe(lambda: dev.name),
        str(_safe(lambda: dev.kind, "unknown")),
    )


def _device(dev, receiver_name, path):
    online = _online(dev)
    entry = {
        "id": _device_id(dev, path),
        # Placeholders; BarWidget.qml's merge already knows how to keep an
        # old name/kind showing when a device comes back as "Unknown device"/
        # "?" (Solaar's own not-yet-identified sentinels), which is what an
        # unresolved case below also lands on.
        "name": "",
        "fullName": None,
        "kind": "unknown",
        "receiver": receiver_name,
        # hidraw path + slot let solaarchy-monitor.py link events find this device.
        "path": path,
        "number": _safe(lambda: dev.number),
        "online": online,
        "battery": None,
        "backlight": None,
    }
    if online:
        for attempt in range(2):
            name, full_name, kind = _identity(dev)
            battery, backlight = _battery(dev), _backlight(dev)
            # codename/name/kind reach HID++2.0 devices through the same
            # feature_request() primitive, so they're checked by the same
            # cross-process consistency audit, not trusted separately.
            if _safe(lambda: _consistent(dev), False):
                entry["name"], entry["fullName"], entry["kind"] = name, full_name, kind
                entry["battery"], entry["backlight"] = battery, backlight
                break
            _forget_features(dev)
            time.sleep(0.3)
        else:
            # Still inconsistent: report nothing rather than someone else's
            # reply. The panel keeps showing the last good reading.
            entry["busy"] = True
    else:
        # Offline: Solaar still knows a cached name/kind from pairing, and
        # there's no live feature_request happening to race with.
        entry["name"], entry["fullName"], entry["kind"] = _identity(dev)
    return entry


def _label(info):
    return f"{info.vendor_id}:{info.product_id} ({os.path.basename(info.path)})"


def _scan(info):
    # Solaar's CLI opener exits the whole process when a receiver fails to
    # open, so feed it one path at a time and keep the failure to that path.
    try:
        opened = list(_receivers_and_devices(info.path))
    except SystemExit as e:
        _warnings.append(f"could not open {_label(info)}: {e.code}")
        return
    except Exception as e:
        _warnings.append(f"could not open {_label(info)}: {e}")
        return

    def try_add(dev, receiver_name, label):
        try:
            _devices.append(_device(dev, receiver_name, info.path))
        except Exception as e:
            _warnings.append(f"could not read {label}: {e}")

    for obj in opened:
        if isinstance(obj, Receiver):
            _receivers.append(obj.name)
            try:
                paired = [dev for dev in obj if dev is not None]
            except Exception as e:
                _warnings.append(f"could not list devices on {obj.name}: {e}")
                continue
            for dev in paired:
                try_add(dev, obj.name, f"a device on {obj.name}")
        else:
            try_add(obj, None, _label(info))


def main():
    for info in list(base.receivers_and_devices()):
        _scan(info)
    # Last-resort safety net: _device_id() only comes back empty if even the
    # device's own hidraw path was missing, which shouldn't happen, but such
    # a device can't be told apart across reads either way.
    _devices[:] = [d for d in _devices if d["id"]]
    _emit(_result())


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        _warnings.append(str(e))
        _emit(_result())
        sys.exit(1)
