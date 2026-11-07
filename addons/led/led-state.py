#!/usr/bin/env python3
"""Solaarchy add-on helper: print the persisted LED state of selected Logitech
HID++ devices as JSON.

Read-only: it goes through Solaar's own library (python-solaar, official repos)
and the hidraw access Solaar's udev rule already grants. No device setting is
changed and Solaar's configuration file is never written; LED changes go through
`solaar config` so the running Solaar GUI records them and does not undo them
when the keyboard wakes.

With --ids ID,ID,... (device ids as the core status script prints them), the
"led" reading of every online device whose id is in that list is included; an
offline one comes back with "led": null, and a device not in the list is left
out and not pinged. Output: {"devices": [{"id": ..., "online": bool, "led":
... | null}, ...]}, one entry per id found, or {"error": "..."} when the
Solaar library can't be imported at all. Without --ids (or with an empty list)
nothing is read and the helper prints {"devices": []} at once.
"""

import argparse
import fcntl
import json
import os
import signal
import sys
import time

_stdout = sys.stdout

# Filled in as the scan goes, so a timeout can still report what was found.
_devices = []


def _emit(doc):
    _stdout.write(json.dumps(doc) + "\n")
    _stdout.flush()


def _dedup(devices):
    # Two links to one unit (a receiver slot and a direct node, say) share an
    # id: keep one entry per id, preferring the first that carries an actual
    # led reading over one that came back null.
    kept = {}
    for d in devices:
        i = d["id"]
        if not i:
            continue
        if i not in kept or (kept[i]["led"] is None and d["led"] is not None):
            kept[i] = d
    return list(kept.values())


def _ids_arg():
    """The --ids list; None without it."""
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--ids",
        metavar="ID,ID,...",
        help="include the led reading of every online device whose id is in this list",
    )
    return parser.parse_args().ids


_ids_raw = _ids_arg()
if _ids_raw is None or _ids_raw.strip() == "":
    # Nothing asked for: answer at once, before the Solaar import or the lock.
    _emit({"devices": []})
    sys.exit(0)
_ids = set(_ids_raw.split(","))


def _result():
    return {"devices": _dedup(_devices)}


def _timeout(*_):
    # A receiver that stops answering must not leave a helper hanging behind
    # the bar: report what was found so far and stop.
    _emit(_result())
    os._exit(1)


signal.signal(signal.SIGALRM, _timeout)
signal.alarm(20)


# Solaar prints warnings (e.g. about Wayland rules) while importing; keep them
# off stdout so the shell only ever sees the JSON document.
sys.stdout = sys.stderr
try:
    import solaar.configuration as _solaar_config
    from logitech_receiver import base
    from logitech_receiver import hidpp20
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

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
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


def _entry(dev, path):
    # Every device — receiver-paired and directly connected alike — is looked
    # up under the receiver's (or its own) hidraw path, the way the core
    # status script does. Only a device that was asked for is pinged at all,
    # and its led reading is taken inside the same cross-process consistency
    # audit the core runs: a clash twice in a row means it is someone else's
    # reply, so report nothing rather than trust it.
    device_id = _device_id(dev, path)
    if device_id not in _ids:
        return None
    entry = {
        "id": device_id,
        "online": _online(dev),
        "led": None,
    }
    if entry["online"]:
        for attempt in range(2):
            led = _led(dev)
            if _safe(lambda: _consistent(dev), False):
                entry["led"] = led
                break
            _forget_features(dev)
            time.sleep(0.3)
        # Still inconsistent after two attempts: led stays null, the shell
        # keeps showing the last good reading.
    return entry


def _scan(info):
    # Solaar's CLI opener exits the whole process when a receiver fails to
    # open, so feed it one path at a time and keep the failure to that path.
    # A path that can't be opened is simply skipped: the shell asked for led
    # readings, not a warning channel.
    try:
        opened = list(_receivers_and_devices(info.path))
    except (SystemExit, Exception):
        return

    def add(dev):
        try:
            entry = _entry(dev, info.path)
            if entry:
                _devices.append(entry)
        except Exception:
            pass

    for obj in opened:
        if isinstance(obj, Receiver):
            try:
                paired = [dev for dev in obj if dev is not None]
            except Exception:
                continue
            for dev in paired:
                add(dev)
        else:
            add(obj)


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
        _emit(_result())
        sys.exit(1)
