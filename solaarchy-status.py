#!/usr/bin/env python3
"""Solaarchy: print battery and backlight state of Logitech HID++ devices as JSON.

Read-only: it goes through Solaar's own library (python-solaar, official repos)
and the hidraw access Solaar's udev rule already grants. No device setting is
changed and Solaar's configuration file is never written; backlight changes go
through `solaar config`, which hands them to a running Solaar GUI.

Output: {"receivers": [...], "devices": [...], "listed": [...], "warnings": [...],
"bluetooth": N}, or {"error": "..."} when nothing at all could be read. "listed"
holds the hidraw path of every receiver whose pairings were all read, so a
device missing from one of them is no longer paired to it. "bluetooth" counts
the Logitech devices BlueZ has paired, connected or not (0 when BlueZ can't be
asked): Solaar only sees a Bluetooth device while it is connected.

With --known ID,ID,... (device ids as printed, "" for none), every online
device not in that list also gets "features": the sorted Solaar names of the
features in its HID++ 2.0 table, [] for a HID++ 1.0 device. The key is left out
when the table did not read the same twice. Without --known, no feature table
is read at all.
"""

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time

_stdout = sys.stdout

# Filled in as the scan goes, so a timeout can still report what was found.
_receivers = []
_devices = []
_listed = []
_warnings = []


def _known_ids():
    """Ids given with --known; None without it, and then no feature table is read."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--known",
        metavar="ID,ID,...",
        help="also list the HID++ features of every online device not in this list ('' for none)",
    )
    known = parser.parse_args().known
    return None if known is None else set(known.split(","))


_known = _known_ids()


def _emit(doc):
    _stdout.write(json.dumps(doc) + "\n")
    _stdout.flush()


def _bluetooth_paired():
    """Logitech devices BlueZ has paired, read-only over the system bus."""
    try:
        out = subprocess.run(
            ["busctl", "--system", "--json=short", "--timeout=2", "call", "org.bluez", "/",
             "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"],
            capture_output=True, text=True, timeout=4, check=True).stdout
        objects = json.loads(out)["data"][0]
    except Exception:
        return 0
    count = 0
    for interfaces in objects.values():
        dev = interfaces.get("org.bluez.Device1", {})
        modalias = str(dev.get("Modalias", {}).get("data", "")).lower()
        if dev.get("Paired", {}).get("data") and modalias.startswith(("usb:v046d", "bluetooth:v046d")):
            count += 1
    return count


# Asked before the device lock, so a slow BlueZ never holds up a device read.
_bluetooth = _bluetooth_paired()


def _result():
    if not _devices and not _receivers and _warnings:
        return {"error": "; ".join(_warnings)}
    return {"receivers": _receivers, "devices": _devices, "listed": _listed, "warnings": _warnings,
            "bluetooth": _bluetooth}


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

from solaarchy_common import consistent as _consistent
from solaarchy_common import device_id as _device_id
from solaarchy_common import forget_features as _forget_features
from solaarchy_common import online as _online
from solaarchy_common import open_lock
from solaarchy_common import safe as _safe

# One read at a time from this user; see solaarchy_common.py.

try:
    _lock = open_lock()
except OSError as e:
    _emit({"error": f"cannot take the status lock: {e}"})
    sys.exit(1)
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


def _feature_table(dev):
    """Sorted names of the features in dev's HID++ 2.0 table that users may see.

    A fresh FeaturesArray each time, so a second read really asks the device
    again (dev.features would answer from its cache) and the map the rest of
    _device() relies on is left alone. None unless every slot answers: half a
    table is never reported, and a device that stops answering mid-table costs
    one request timeout, not one per remaining slot.
    """
    if dev.protocol < 2.0:
        return []  # HID++ 1.0 has fixed registers, no feature table
    table = hidpp20.FeaturesArray(dev)
    if not table:  # asks FEATURE_SET how many slots there are
        return None
    found = []
    for index in range(table.count):
        feature = table.get_feature(index)
        if feature is None:
            return None
        found.append(feature)
    return sorted(
        f.name
        for f in found
        # Names Solaar knows only (unknown ids come back as "unknown:XXXX"),
        # minus ROOT/FEATURE_SET and those flagged hidden (0x40) or engineering (0x20).
        if isinstance(f, SupportedFeature)
        and f not in (SupportedFeature.ROOT, SupportedFeature.FEATURE_SET)
        and not table.flags.get(f, 0) & 0x60
    )


def _features(dev):
    # The same reply race as in _consistent(): only a table read the same
    # twice in a row counts; otherwise the caller asks again next time.
    first = _safe(lambda: _feature_table(dev))
    if first is not None and first == _safe(lambda: _feature_table(dev)):
        return first
    return None


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
                if _known is not None and entry["id"] not in _known:
                    features = _features(dev)
                    if features is not None:
                        entry["features"] = features
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
            return True
        except Exception as e:
            _warnings.append(f"could not read {label}: {e}")
            return False

    for obj in opened:
        if isinstance(obj, Receiver):
            _receivers.append(obj.name)
            try:
                paired = [dev for dev in obj if dev is not None]
            except Exception as e:
                _warnings.append(f"could not list devices on {obj.name}: {e}")
                continue
            # Only a receiver whose every pairing made it into the output
            # counts as listed: a device that failed to read is still paired.
            added = [try_add(dev, obj.name, f"a device on {obj.name}") for dev in paired]
            if all(added):
                _listed.append(info.path)
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
