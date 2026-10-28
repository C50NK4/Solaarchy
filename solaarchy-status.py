#!/usr/bin/env python3
"""Solaarchy: print battery, backlight and LED state of Logitech HID++ devices as JSON.

Read-only: it goes through Solaar's own library (python-solaar, official repos)
and the hidraw access Solaar's udev rule already grants. No device setting is
changed and Solaar's configuration file is never written; backlight and LED
changes go through `solaar config` so the running Solaar GUI records them and
does not undo them when the keyboard wakes.

Output: {"receivers": [...], "devices": [...], "listed": [...], "warnings": [...]},
or {"error": "..."} when nothing at all could be read. "listed" holds the hidraw
path of every receiver whose pairings were all read, so a device missing from
one of them is no longer paired to it.
"""

import fcntl
import json
import os
import signal
import stat
import struct
import sys
import time

_stdout = sys.stdout

# Filled in as the scan goes, so a timeout can still report what was found.
_receivers = []
_devices = []
_listed = []
_warnings = []


def _emit(doc):
    _stdout.write(json.dumps(doc) + "\n")
    _stdout.flush()


def _result():
    if not _devices and not _receivers and _warnings:
        return {"error": "; ".join(_warnings)}
    return {"receivers": _receivers, "devices": _devices, "listed": _listed, "warnings": _warnings}


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


def _open_lock():
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


try:
    _lock = _open_lock()
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


def _led(dev):
    # The persisted LED settings are the state source, read from Solaar's own
    # configuration cache (dev.persister, the same file `solaar config` and
    # the running Solaar GUI write): the zones' live state is not readable on
    # this hardware, so the settings are what the GUI re-applies and what the
    # user sees as "current". dev.persister is a plain dict per device.
    #
    # The device's zone/effect capabilities (dev.led_effects) are only asked
    # for when the cache actually shows LED zones, so a device without LED
    # support sends no HID++ traffic for it.
    try:
        persister = dev.persister
        if not isinstance(persister, dict):
            return None
        # Two feature families persist LED state with the same value class
        # and zone layout but different setting names: COLOR_LED_EFFECTS
        # (G403 and kin) caches led_control/led_zone_N, RGB_EFFECTS (G502,
        # G700/G900 Lightspeed and the newer RGB mice) caches
        # rgb_control/rgb_zone_N. Probe in the same order Solaar's own
        # dev.led_effects prefers the features, and report the names so the
        # QML side writes the family this cache actually uses.
        family = None
        for control_key, zone_prefix in (("led_control", "led_zone_"),
                                         ("rgb_control", "rgb_zone_")):
            if persister.get(control_key) is not None:
                family = (control_key, zone_prefix)
                break
        if family is None:
            return None  # no LED state cached for this device
        control_key, zone_prefix = family
        control = persister[control_key]
    except Exception:
        return None

    zones = []
    zone_settings = []
    for key, value in persister.items():
        if not key.startswith(zone_prefix):
            continue
        try:
            location = int(key[len(zone_prefix):])
        except ValueError:
            continue
        if not isinstance(value, hidpp20.LEDEffectSetting):
            continue
        zone_settings.append((location, value))
    if not zone_settings:
        return {"control": bool(control), "zones": zones,
                "controlSetting": control_key,
                "zoneSettingPrefix": zone_prefix}

    # Zone capabilities: which effects each location can do. dev.led_effects
    # is lazy and caches into dev._led_effects (cleared by _forget_features).
    capabilities = None
    try:
        if dev.online and dev.protocol >= 2.0:
            capabilities = dev.led_effects
    except Exception:
        pass

    for location, setting in sorted(zone_settings):
        effect_id = int(setting.ID) if setting.ID is not None else None
        label = None
        effects = None
        zone = None
        if capabilities is not None:
            for z in capabilities.zones:
                try:
                    if int(z.location) == location:
                        zone = z
                        break
                except Exception:
                    continue
        if zone is not None:
            # Each supported effect with its name, its full param set, and the
            # defaults Solaar's LEDEffectSetting.to_bytes() would otherwise
            # fill with 0: the QML side sends id + defaults (keeping any param
            # the current effect already sets) when cycling, e.g. Cycle needs
            # period 5000/intensity 100, and a color param with no value
            # anywhere would light the zone black.
            effects = []
            for e in zone.effects:
                eid = int(e.ID)
                # Newer firmware can advertise effects the library table does
                # not know; report them anyway, nameless and paramless.
                entry = hidpp20.LEDEffects.get(eid)
                effects.append(
                    {
                        "id": eid,
                        "name": str(entry[0]) if entry is not None else None,
                        "params": [str(p) for p in entry[1]] if entry is not None else [],
                        "defaults": {p: int(v) for p, v in entry[2].items()}
                        if entry is not None and len(entry) > 2
                        else {},
                    }
                )
        params = None
        if effect_id is not None:
            effect_entry = hidpp20.LEDEffects.get(effect_id)
            if effect_entry:
                params = {p: int(getattr(setting, p, 0)) for p in effect_entry[1]}
        zones.append(
            {
                "location": location,
                # NamedInts look up by int; an unknown location comes back None.
                "label": str(hidpp20.LEDZoneLocations[location])
                if hidpp20.LEDZoneLocations[location]
                else f"zone {location}",
                "effectId": effect_id,
                "effect": str(hidpp20.LEDEffects[effect_id][0])
                if effect_id is not None and effect_id in hidpp20.LEDEffects
                else None,
                "params": params,
                "effects": effects,
            }
        )
    return {"control": bool(control), "zones": zones,
            "controlSetting": control_key,
            "zoneSettingPrefix": zone_prefix}


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
    dev._led_effects = None


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
    # A device that hasn't answered yet (e.g. a Bluetooth keyboard waking up)
    # reports an all-zero serial/unitId: not an identity, skip it.
    serial = _safe(lambda: dev.serial)
    if serial and serial.strip("0"):
        return serial
    unit_id = _safe(lambda: dev.unitId)
    if unit_id and unit_id.strip("0"):
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
        "led": None,
    }
    if online:
        for attempt in range(2):
            name, full_name, kind = _identity(dev)
            battery, backlight, led = _battery(dev), _backlight(dev), _led(dev)
            # codename/name/kind reach HID++2.0 devices through the same
            # feature_request() primitive, so they're checked by the same
            # cross-process consistency audit, not trusted separately.
            if _safe(lambda: _consistent(dev), False):
                entry["name"], entry["fullName"], entry["kind"] = name, full_name, kind
                entry["battery"], entry["backlight"], entry["led"] = battery, backlight, led
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
