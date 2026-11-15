#!/usr/bin/env python3
"""Solaarchy: watch Logitech receivers for devices connecting and disconnecting.

Prints one JSON line per event and never exits on its own:
  {"event": "link", "path": "/dev/hidraw3", "number": 2, "online": false}
  {"event": "notify", "path": "/dev/hidraw3", "number": 2, "feature": 7}
                         a device's own HID++ 2.0 notification (e.g. its
                         battery feature reporting the charger unplugged)
  {"event": "hotplug"}   a HID++ receiver or directly connected device came or went
  {"event": "ready"}     listening; sent once at startup

Listen-only: hidraw nodes are opened O_RDONLY and nothing is ever written, so
no device is woken and the running Solaar GUI is unaffected (every open
hidraw handle gets its own copy of each report). Which hidraw nodes are HID++
receivers and devices is read from sysfs, the way Solaar picks them (see
solaarchy_common.hidpp_nodes), and hotplug comes from udev's netlink
broadcast. Standard library only: this process stays resident, and Solaar's
library plus pyudev kept it at ~46 MB, against ~13 MB now. Every RESYNC_S it
also looks at sysfs again, so a hotplug it missed (an event lost, a node that
could not be opened yet) is picked up anyway.
"""

import array
import json
import os
import select
import socket
import struct
import sys
import time

_stdout = sys.stdout


def _fail(e):
    # The bar shows this as the monitor's error instead of silently
    # restarting a monitor that can't work.
    try:
        _stdout.write(json.dumps({"event": "error", "error": f"monitor: {e}"}) + "\n")
        _stdout.flush()
    except OSError:
        pass
    sys.exit(1)


sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from solaarchy_common import hidpp_nodes  # noqa: E402
except Exception as e:
    _fail(e)

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


def notification(data):
    """(number, feature index) for a device's own HID++ 2.0 notification.

    A notification carries software id 0 (low nibble of byte 3), which tells
    it apart from replies to requests other programs make. Byte 2 is the
    feature's index on that device; receiver notifications (HID++ 1.0) use
    sub-ids from 0x40 up there instead.
    """
    if len(data) < 4 or data[0] not in (HIDPP_SHORT, HIDPP_LONG):
        return None
    if not 0 < data[2] < 0x40 or data[3] & 0x0F:
        return None
    return data[1], data[2]


def parse(data):
    """Return (number, online) for a connection report, else None."""
    if len(data) < 5:
        return None
    report_id, number, sub_id, address = data[0], data[1], data[2], data[3]
    # Unpairing: report the slot offline, so a device paired into it next
    # counts as a change and is read even within REPEAT_S.
    if report_id in (HIDPP_SHORT, HIDPP_LONG) and sub_id == 0x40 and address == 0x02:
        return number, False
    if report_id in (HIDPP_SHORT, HIDPP_LONG) and sub_id == DJ_PAIRING and address != 0x00:
        online = True if address == EX100_ADDRESS else not (data[4] & 0x40)
        return number, online
    if report_id == DJ_REPORT and sub_id == DJ_CONNECTED:
        return number, not (address & 0x01)
    return None


def hidpp_paths():
    try:
        return hidpp_nodes()
    except Exception as e:  # a bug, not a race: hidpp_nodes handles OSError per node
        sys.stderr.write(f"solaarchy-monitor: node discovery failed: {e!r}\n")
        return set()


RESYNC_S = 60  # how often sysfs is looked at again without a udev event


UDEV_GROUP = 2  # udevd's re-broadcast, sent once a node's permissions are in place
UDEV_MAGIC = 0xFEEDCAFE
NETLINK_KOBJECT_UEVENT = 15  # not exported by the socket module


SO_ATTACH_FILTER = 26


def _murmur2(data, seed=0):
    """libudev's subsystem hash (MurmurHash2, 32 bit)."""
    m, h, i = 0x5BD1E995, (seed ^ len(data)) & 0xFFFFFFFF, 0
    while len(data) - i >= 4:
        k = (int.from_bytes(data[i:i + 4], "little") * m) & 0xFFFFFFFF
        k = ((k ^ (k >> 24)) * m) & 0xFFFFFFFF
        h = ((h * m) & 0xFFFFFFFF) ^ k
        i += 4
    rest = data[i:]
    if len(rest) == 3:
        h ^= rest[2] << 16
    if len(rest) >= 2:
        h ^= rest[1] << 8
    if rest:
        h = ((h ^ rest[0]) * m) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * m) & 0xFFFFFFFF
    return h ^ (h >> 15)


def udev_socket():
    sock = socket.socket(socket.AF_NETLINK, socket.SOCK_RAW | socket.SOCK_NONBLOCK | socket.SOCK_CLOEXEC,
                         NETLINK_KOBJECT_UEVENT)
    # The kernel drops every udev message but hidraw's before this process
    # wakes, as pyudev's filter_by did: libudev puts the subsystem's hash in
    # the header at byte 24 (and its magic at byte 8), both big endian.
    code = [
        (0x20, 0, 0, 8),                         # A = magic
        (0x15, 0, 3, UDEV_MAGIC),                # not libudev's: drop
        (0x20, 0, 0, 24),                        # A = subsystem hash
        (0x15, 0, 1, _murmur2(b"hidraw")),       # not hidraw: drop
        (0x06, 0, 0, 0xFFFFFFFF),                # keep
        (0x06, 0, 0, 0),                         # drop
    ]
    prog = array.array("B", b"".join(struct.pack("=HBBI", *op) for op in code))
    try:
        sock.setsockopt(socket.SOL_SOCKET, SO_ATTACH_FILTER, struct.pack("HL", len(code), prog.buffer_info()[0]))
    except OSError:
        pass  # unfiltered still works: hidraw_change() checks every message
    sock.bind((0, UDEV_GROUP))
    return sock


def hidraw_change(msg):
    """True for a udevd "add" or "remove" of a hidraw node."""
    # libudev's header: "libudev\0", magic (big endian), then header size,
    # properties offset and length in host order; the properties are
    # NUL-separated KEY=VALUE pairs.
    if len(msg) < 24 or msg[:8] != b"libudev\0" or struct.unpack_from(">I", msg, 8)[0] != UDEV_MAGIC:
        return False
    off, length = struct.unpack_from("=II", msg, 16)
    props = dict(p.split(b"=", 1) for p in msg[off:off + length].split(b"\0") if b"=" in p)
    return props.get(b"SUBSYSTEM") == b"hidraw" and props.get(b"ACTION") in (b"add", b"remove")


# Some receivers repeat "connected" for a device that never left: a Lightspeed
# receiver with a charging G502 X sends one every ~3.8 s. Each one used to
# cost a full status read, so the bar never stopped reading. Pass a link on
# when it changes, and a repeat of the same state at most every REPEAT_S
# (a device that slept without saying so still gets a read when it wakes,
# within the same window as the bar's default periodic read, 300 s).
REPEAT_S = 300
_links = {}  # (path, number) -> (online, monotonic time last passed on)


def announce(path, number, online):
    now = time.monotonic()
    last = _links.get((path, number))
    if last is not None and last[0] == online and now - last[1] < REPEAT_S:
        return False
    _links[(path, number)] = (online, now)
    return True


def forget(path):
    """A node that went away takes its links' states with it: a receiver
    plugged back in on the same /dev/hidrawN starts afresh."""
    for key in [k for k in _links if k[0] == path]:
        del _links[key]


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
                forget(path)
        opened = set(fds.values())
        for path in wanted - opened:
            try:
                fds[os.open(path, os.O_RDONLY | os.O_NONBLOCK)] = path
            except OSError:
                pass  # no access or already gone; the next hotplug retries
        return set(fds.values()) != before

    monitor = udev_socket()
    sync()
    emit({"event": "ready"})

    while True:
        readable, _, _ = select.select([monitor.fileno(), *fds], [], [], RESYNC_S)
        if not readable:
            if sync():
                emit({"event": "hotplug"})
            continue
        for fd in readable:
            if fd == monitor.fileno():
                changed = False
                while True:
                    try:
                        changed = hidraw_change(monitor.recv(8192)) or changed
                    except BlockingIOError:
                        break
                    except OSError:  # ENOBUFS: events were lost, so look again
                        changed = True
                        break
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
                forget(path)
                emit({"event": "hotplug"})
                continue
            link = parse(data)
            if link is not None:
                if announce(path, *link):
                    emit({"event": "link", "path": path, "number": link[0], "online": link[1]})
                continue
            note = notification(data)
            if note is not None:
                emit({"event": "notify", "path": path, "number": note[0], "feature": note[1]})


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as e:  # e.g. no netlink socket in a sandbox
        _fail(e)
