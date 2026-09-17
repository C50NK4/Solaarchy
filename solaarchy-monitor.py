#!/usr/bin/env python3
"""Solaarchy: watch Logitech receivers for devices connecting and disconnecting.

Prints one JSON line per event and never exits on its own:
  {"event": "link", "path": "/dev/hidraw3", "number": 2, "online": false}
  {"event": "hotplug"}   a HID++ receiver or directly connected device came or went

Listen-only: hidraw nodes are opened O_RDONLY and nothing is ever written, so
no device is woken and the running Solaar GUI is unaffected (every open
hidraw handle gets its own copy of each report). Solaar's library is used
only to pick which hidraw nodes are HID++ receivers and devices; that reads
udev and sysfs, not the hardware.
"""

import json
import os
import select
import sys

sys.stdout, _stdout = sys.stderr, sys.stdout  # keep Solaar's import noise off the pipe
try:
    import pyudev
    from logitech_receiver import base
except Exception as e:
    _stdout.write(json.dumps({"event": "error", "error": f"solaar library unavailable: {e}"}) + "\n")
    _stdout.flush()
    sys.exit(1)

HIDPP_SHORT, HIDPP_LONG, DJ_REPORT = 0x10, 0x11, 0x20
DJ_PAIRING = 0x41  # HID++ 1.0 "device connection": flags bit 0x40 = link lost
DJ_CONNECTED = 0x42  # DJ-mode connection report: address bit 0x01 = disconnected
EX100_ADDRESS = 0x02  # 27 MHz receivers: every 0x41 means connected


def emit(doc):
    try:
        _stdout.write(json.dumps(doc) + "\n")
        _stdout.flush()
    except BrokenPipeError:  # the shell went away
        os._exit(0)


def parse(data):
    """Return (number, online) for a connection report, else None."""
    if len(data) < 5:
        return None
    report_id, number, sub_id, address = data[0], data[1], data[2], data[3]
    if report_id in (HIDPP_SHORT, HIDPP_LONG) and sub_id == DJ_PAIRING and address != 0x00:
        online = True if address == EX100_ADDRESS else not (data[4] & 0x40)
        return number, online
    if report_id == DJ_REPORT and sub_id == DJ_CONNECTED:
        return number, not (address & 0x01)
    return None


def hidpp_paths():
    try:
        return {info.path for info in base.receivers_and_devices()}
    except Exception:
        return set()


def main():
    fds = {}  # fd -> path

    def sync():
        """Match open fds to the HID++ nodes present; True if that set changed."""
        wanted = hidpp_paths()
        before = set(fds.values())
        for fd, path in list(fds.items()):
            if path not in wanted:
                os.close(fd)
                del fds[fd]
        opened = set(fds.values())
        for path in wanted - opened:
            try:
                fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
            except OSError:
                pass  # no access or already gone; the next hotplug retries
        return set(fds.values()) != before

    context = pyudev.Context()
    monitor = pyudev.Monitor.from_netlink(context)
    monitor.filter_by(subsystem="hidraw")
    monitor.start()
    sync()

    while True:
        readable, _, _ = select.select([monitor.fileno(), *fds], [], [])
        for fd in readable:
            if fd == monitor.fileno():
                changed = False
                while (event := monitor.poll(timeout=0)) is not None:
                    changed = changed or event.action in ("add", "remove")
                # Any hidraw node counts as a udev change (a gamepad, a
                # security key); only report when a Logitech one came or went.
                if changed and sync():
                    emit({"event": "hotplug"})
                continue
            path = fds.get(fd)
            if path is None:
                continue
            try:
                data = os.read(fd, 64)
            except BlockingIOError:
                continue
            except OSError:
                data = b""
            if not data:
                # Unplugged: the node fails before udev announces the removal,
                # and once the fd is dropped that udev event looks like no
                # change, so report it here.
                os.close(fd)
                del fds[fd]
                emit({"event": "hotplug"})
                continue
            link = parse(data)
            if link is not None:
                emit({"event": "link", "path": path, "number": link[0], "online": link[1]})


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
