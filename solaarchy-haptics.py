#!/usr/bin/env python3
"""Solaarchy: play haptic waveforms on Logitech devices that have a haptic motor.

  solaarchy-haptics.py play WAVEFORM [--device ID]   buzz, e.g. `play completed`
  solaarchy-haptics.py list                          waveforms and haptic devices
  solaarchy-haptics.py serve                         the bar widget's player

`serve` is started by BarWidget.qml while a device with haptics is known, and
keeps that device open so a pulse fires in well under a millisecond instead of
the second or so it takes to load Solaar's library and find the device. It
takes one JSON command per line on stdin from the widget, and the same commands
from `play` and `list` over a socket in a directory only this user can reach.
With no server running, `play` and `list` open the devices themselves.

Waveforms go out through Solaar's own library as HID++ feature 0x19B0
(HAPTIC) function 4, the request behind `solaar config <device> haptic-play`,
with the hidraw access Solaar's udev rule already grants. Nothing is
persisted: playing a waveform changes no device setting, and the haptic level
is left to `solaar config` (see BarWidget.qml).

With notifications switched on in the widget, `serve` also watches the session
bus for Notify calls with dbus-monitor and reports the sender's app name and
urgency, never the text, so the widget can pick a waveform for it.
"""

import fcntl
import json
import os
import select
import signal
import socket
import stat
import struct
import subprocess
import sys
import time

# HID++ 0x19B0 waveform ids, as Solaar names them (HapticWaveForms), with the
# names the CLI and the widget's settings use. A device reports which of them
# it has in a bitmask; the MX Master 4 has exactly these.
WAVEFORMS = {
    "sharp-state-change": 0x00,
    "damp-state-change": 0x01,
    "sharp-collision": 0x02,
    "damp-collision": 0x03,
    "subtle-collision": 0x04,
    "happy-alert": 0x05,
    "angry-alert": 0x06,
    "completed": 0x07,
    "square": 0x08,
    "wave": 0x09,
    "firework": 0x0A,
    "mad": 0x0B,
    "knock": 0x0C,
    "jingle": 0x0D,
    "ringing": 0x0E,
    "whisper-collision": 0x1B,
}
WAVEFORM_NAMES = {v: k for k, v in WAVEFORMS.items()}

HAPTIC_PLAY = 0x40  # function 4, shifted into the HID++ function nibble
# Back-to-back requests to one device closer than this are dropped rather
# than queued: a burst of Hyprland events (scrolling through workspaces, a
# layout switch reported once per keyboard) should feel like one pulse, not a
# rattle that runs on after the burst ends.
MIN_GAP = 0.06
# How long a scan that found nothing stands before a request may scan again.
# The widget asks for a rescan whenever a device connects, so this only
# matters for a device that was never reported.
RESCAN_GAP = 15.0
LOCK_WAIT = 25.0

SOCKET_NAME = "solaarchy-haptics.sock"

_stdout = sys.stdout


def emit(doc):
    try:
        _stdout.write(json.dumps(doc) + "\n")
        _stdout.flush()
    except BrokenPipeError:  # the shell went away
        os._exit(0)


def parse_waveform(text):
    """A waveform name ("completed", "HAPPY ALERT") or id ("7", "0x1b"), or None."""
    key = str(text).strip().lower().replace("_", "-").replace(" ", "-")
    if key in WAVEFORMS:
        return WAVEFORMS[key]
    try:
        n = int(key, 0)
    except ValueError:
        return None
    return n if 0 <= n < 32 else None


# The socket lives only in a directory no one else can write to, for the
# same reason solaarchy-status.py keeps its lock there: in a shared one like
# /tmp another user could plant something at the predictable name.
def _private_dir(path):
    try:
        st = os.stat(path)
    except OSError:
        return False
    return stat.S_ISDIR(st.st_mode) and st.st_uid == os.getuid() and not st.st_mode & 0o022


def private_dir():
    """The directory solaarchy-status.py keeps its lock in, picked the same way."""
    for d in (os.environ.get("XDG_RUNTIME_DIR"), f"/run/user/{os.getuid()}"):
        if d and _private_dir(d):
            return d
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    d = os.path.join(cache, "solaarchy")
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
    except OSError:
        return None
    return d if _private_dir(d) else None


def socket_path():
    d = private_dir()
    return os.path.join(d, SOCKET_NAME) if d else None


class StatusLock:
    """solaarchy-status.py's lock, held while finding devices.

    Finding a device asks it a string of questions (its name, its features).
    Every Solaar process uses one fixed HID++ software id, so a status read
    asking at the same moment can take one of these replies for its own and
    report the device as "Unknown device". Taking turns with the status
    helper avoids that. The file is opened with the same care it takes: no
    symlinks followed, nothing truncated, and refused unless it is a private
    regular file. A status read holds the lock for seconds at most; past
    LOCK_WAIT the scan goes ahead anyway rather than leave events unplayed.
    """

    def __enter__(self):
        self.fd = None
        d = private_dir()
        if d is None:
            return self
        flags = os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC
        path = os.path.join(d, "solaarchy-status.lock")
        try:
            try:
                fd = os.open(path, flags | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                fd = os.open(path, flags)
            st = os.fstat(fd)
            if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_nlink != 1:
                os.close(fd)
                return self
        except OSError:
            return self
        deadline = time.monotonic() + LOCK_WAIT
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.fd = fd
                return self
            except BlockingIOError:
                if time.monotonic() > deadline:
                    os.close(fd)
                    return self
                time.sleep(0.1)

    def __exit__(self, *_):
        if self.fd is not None:
            os.close(self.fd)  # closing drops the flock


def ask_server(command, timeout=2.0):
    """Send one command to a running `serve`; its reply, or None if none is running."""
    path = socket_path()
    if path is None:
        return None
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(timeout)
            s.connect(path)
            s.sendall((json.dumps(command) + "\n").encode())
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(4096)
                if not chunk:
                    break
                data += chunk
    except OSError:
        return None
    try:
        return json.loads(data)
    except ValueError:
        return None


class Haptics:
    """The haptic devices Solaar can see, opened once and kept open."""

    def __init__(self):
        self.devices = []  # [{"id", "name", "dev", "waveforms", "last"}]
        self.opened = []  # Receiver/Device objects whose handles we hold
        self.dirty = True
        self.scanned_at = 0.0

    def _load_solaar(self):
        # Solaar prints warnings (e.g. about Wayland rules) while importing;
        # keep them off stdout, which carries JSON only.
        saved, sys.stdout = sys.stdout, sys.stderr
        try:
            import solaar.configuration as solaar_config
            from logitech_receiver import base
            from logitech_receiver.hidpp20_constants import SupportedFeature
            from logitech_receiver.receiver import Receiver
            from solaar.cli import _receivers_and_devices
        finally:
            sys.stdout = saved
        # As in solaarchy-status.py: outside the GUI, Solaar's library saves its
        # configuration file whenever it caches something about a device, which
        # would race the running Solaar GUI that owns that file.
        solaar_config.save = lambda *args, **kwargs: None
        solaar_config.do_save = lambda *args, **kwargs: None
        self.base = base
        self.feature = SupportedFeature.HAPTIC
        self.Receiver = Receiver
        self.open_path = _receivers_and_devices

    def close(self):
        for obj in self.opened:
            try:
                obj.close()
            except Exception:
                pass
        self.opened = []
        self.devices = []

    def scan(self):
        if not hasattr(self, "base"):
            self._load_solaar()
        self.close()
        self.dirty = False
        with StatusLock():
            self._scan()
        self.scanned_at = time.monotonic()

    def _scan(self):
        for info in list(self.base.receivers_and_devices()):
            try:
                opened = list(self.open_path(info.path))
            except (SystemExit, Exception):
                continue  # Solaar's opener exits the process on a failed open
            for obj in opened:
                self.opened.append(obj)
                if isinstance(obj, self.Receiver):
                    try:
                        paired = [d for d in obj if d is not None]
                    except Exception:
                        continue
                else:
                    paired = [obj]
                for dev in paired:
                    entry = self._haptic_entry(dev, info.path)
                    if entry:
                        self.devices.append(entry)

    def _haptic_entry(self, dev, path):
        try:
            if not dev.ping() or not dev.features or self.feature not in dev.features:
                return None
            index = dev.features[self.feature]
            # Every Solaar process uses one fixed HID++ software id, so another
            # program's reply can be taken for ours (see _consistent() in
            # solaarchy-status.py). Ask for the slot again before trusting it:
            # a play request sent to the wrong slot would be some other
            # feature's function 4.
            reply = dev.request(0x0000, struct.pack("!H", int(self.feature)))
            if reply is None or reply[0] != index:
                return None
            caps = dev.feature_request(self.feature, 0x00)
            mask = int.from_bytes(caps[4:8], "big") if caps and len(caps) >= 8 else 0
        except Exception:
            return None
        return {
            "id": device_id(dev, path),
            "name": (safe(lambda: dev.codename or dev.name) or "").strip(),
            "dev": dev,
            "waveforms": [i for i in range(32) if mask & (1 << i)],
            "last": 0.0,
        }

    def play(self, waveform, device=None):
        if self.dirty:
            self.scan()
        targets = [d for d in self.devices if device in (None, "", d["id"])]
        if not targets and time.monotonic() - self.scanned_at > RESCAN_GAP:
            # Asleep at the last scan, or since replugged: look once more. Not
            # on every request, though: a scan takes about a second, and a
            # device that stays asleep would otherwise stall each event.
            self.scan()
            targets = [d for d in self.devices if device in (None, "", d["id"])]
        if not targets:
            return {"error": f"no haptic device {device}" if device else "no haptic device found"}
        played, failed = [], False
        now = time.monotonic()
        for d in targets:
            # A device that lists its waveforms only plays those; one that
            # lists none (an older firmware, say) gets the request anyway.
            if d["waveforms"] and waveform not in d["waveforms"]:
                continue
            if now - d["last"] < MIN_GAP:
                played.append(d["name"])
                continue
            try:
                # No reply wanted: the pulse is the answer, and waiting on a
                # sleeping device would stall every request behind it.
                d["dev"].feature_request(self.feature, HAPTIC_PLAY, waveform, no_reply=True)
                d["last"] = now
                played.append(d["name"])
            except Exception:
                failed = True
        if failed:
            self.dirty = True  # gone since the scan; the next request rescans
        if not played:
            return {"error": "could not reach the haptic device" if failed
                    else f"no haptic device has waveform {waveform:#04x}"}
        return {"ok": True, "devices": played}

    def describe(self):
        if self.dirty:
            self.scan()
        return {
            "ok": True,
            "devices": [
                {"id": d["id"], "name": d["name"],
                 "waveforms": [WAVEFORM_NAMES.get(i, hex(i)) for i in d["waveforms"]]}
                for d in self.devices
            ],
        }


def safe(fn, fallback=None):
    try:
        return fn()
    except Exception:
        return fallback


def device_id(dev, path):
    # The same id solaarchy-status.py reports, so the widget and the CLI can
    # name a device exactly as the panel and `solaar config` do.
    for value in (safe(lambda: dev.serial), safe(lambda: dev.unitId)):
        if value:
            return value
    number = safe(lambda: dev.number)
    if path and number is not None:
        return f"{path}:{number}"
    return safe(lambda: dev.wpid)


def handle(haptics, command):
    if not isinstance(command, dict):
        return {"error": "not a command"}
    cmd = command.get("cmd")
    if cmd == "play":
        waveform = parse_waveform(command.get("waveform", ""))
        if waveform is None:
            return {"error": f"unknown waveform {command.get('waveform')!r}"}
        return haptics.play(waveform, command.get("device"))
    if cmd == "list":
        return haptics.describe()
    if cmd == "rescan":
        haptics.dirty = True
        return {"ok": True}
    return {"error": f"unknown command {cmd!r}"}


class NotificationWatch:
    """Notify calls on the session bus, via dbus-monitor: app name and urgency only."""

    RULE = "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"

    def __init__(self):
        self.proc = None
        self.buffer = b""
        self.current = None

    def start(self):
        if self.proc:
            return
        try:
            self.proc = subprocess.Popen(
                ["dbus-monitor", "--session", self.RULE],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL,
            )
        except OSError as e:
            emit({"event": "error", "error": f"cannot watch notifications: {e}"})
            self.proc = None

    def stop(self):
        if self.proc:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc, self.buffer, self.current = None, b"", None

    def fileno(self):
        return self.proc.stdout.fileno()

    def read(self):
        data = os.read(self.fileno(), 65536)
        if not data:
            self.stop()
            emit({"event": "error", "error": "notification watcher stopped"})
            return
        self.buffer += data
        *lines, self.buffer = self.buffer.split(b"\n")
        for raw in lines:
            self._line(raw.decode("utf-8", "replace"))

    # dbus-monitor prints a header per message, then one argument per line,
    # top-level ones indented by exactly three spaces. Notify's arguments are
    # app_name, replaces_id, app_icon, summary, body, actions, hints and the
    # expire timeout, which as the last top-level int32 closes the message.
    def _line(self, line):
        if line.startswith("method call ") and "member=Notify" in line:
            self._finish()
            self.current = {"app": None, "urgency": 1, "want_urgency": False}
            return
        c = self.current
        if c is None:
            return
        stripped = line.strip()
        if c["app"] is None and line.startswith("   string \""):
            c["app"] = stripped[len("string \""):].rstrip("\"")
        elif stripped == 'string "urgency"':
            c["want_urgency"] = True
        elif c["want_urgency"] and stripped.startswith("variant"):
            parts = stripped.split()
            if len(parts) >= 3 and parts[-2] == "byte" and parts[-1].isdigit():
                c["urgency"] = int(parts[-1])
            c["want_urgency"] = False
        elif line.startswith("   int32 "):
            self._finish()

    def _finish(self):
        c, self.current = self.current, None
        if c is not None and c["app"] is not None:
            emit({"event": "notification", "app": c["app"], "urgency": c["urgency"]})


def serve():
    sys.stdout = sys.stderr  # keep Solaar's import noise off the pipe
    # The shell stops the player with SIGTERM (and pdeathsig sends the same):
    # exit through the finally below so the socket doesn't outlive it.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    haptics = Haptics()
    notifications = NotificationWatch()

    path = socket_path()
    server = None
    if path is None:
        emit({"event": "error", "error": "no private directory for the haptics socket"})
    else:
        # A live server already answering (a second shell) keeps its socket;
        # anything else at the path is a leftover from one that died.
        if ask_server({"cmd": "rescan"}, timeout=0.5) is not None:
            emit({"event": "error", "error": "another Solaarchy haptics player is running"})
        else:
            try:
                st = os.lstat(path)
                if stat.S_ISSOCK(st.st_mode) and st.st_uid == os.getuid():
                    os.unlink(path)
            except FileNotFoundError:
                pass
            server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            old_umask = os.umask(0o177)
            try:
                server.bind(path)
            finally:
                os.umask(old_umask)
            server.listen(8)
    emit({"event": "ready", "socket": path if server else None})
    # Find the devices now rather than on the first request, so the first
    # event after login buzzes as promptly as every later one. Commands that
    # arrive meanwhile wait in the pipe and the socket's backlog.
    try:
        haptics.scan()
    except Exception as e:
        emit({"event": "error", "error": f"solaar library unavailable: {e}"})

    stdin_buffer = b""
    clients = {}  # socket -> buffered bytes
    try:
        while True:
            watch = [sys.stdin.fileno(), *clients]
            if server:
                watch.append(server)
            if notifications.proc:
                watch.append(notifications.fileno())
            readable, _, _ = select.select(watch, [], [])
            for r in readable:
                if r == sys.stdin.fileno():
                    data = os.read(r, 65536)
                    if not data:
                        return  # the widget went away
                    stdin_buffer += data
                    *lines, stdin_buffer = stdin_buffer.split(b"\n")
                    for line in lines:
                        try:
                            command = json.loads(line)
                        except ValueError:
                            continue
                        if isinstance(command, dict) and command.get("cmd") == "notifications":
                            notifications.start() if command.get("enabled") else notifications.stop()
                            continue
                        result = handle(haptics, command)
                        if "error" in result:
                            emit({"event": "error", "error": result["error"]})
                elif r is server:
                    try:
                        conn, _ = server.accept()
                        conn.setblocking(False)
                        clients[conn] = b""
                    except OSError:
                        pass
                elif notifications.proc and r == notifications.fileno():
                    notifications.read()
                else:
                    try:
                        data = r.recv(4096)
                    except OSError:
                        data = b""
                    if data:
                        clients[r] += data
                        if len(clients[r]) > 65536:
                            data = b""  # not a command; drop the client
                        elif b"\n" not in clients[r]:
                            continue
                    line = clients.pop(r).split(b"\n", 1)[0]
                    try:
                        if line:
                            try:
                                command = json.loads(line)
                            except ValueError:
                                command = None
                            r.sendall((json.dumps(handle(haptics, command)) + "\n").encode())
                    except OSError:
                        pass
                    finally:
                        r.close()
    finally:
        notifications.stop()
        if server:
            server.close()
            try:
                os.unlink(path)
            except OSError:
                pass
        haptics.close()


def cli(argv):
    usage = "usage: solaarchy-haptics.py play WAVEFORM [--device ID] | list"
    if not argv or argv[0] in ("-h", "--help"):
        print(usage)
        print("waveforms: " + ", ".join(WAVEFORMS))
        return 0
    if argv[0] == "play" and len(argv) in (2, 4):
        command = {"cmd": "play", "waveform": argv[1]}
        if len(argv) == 4:
            if argv[2] != "--device":
                print(usage, file=sys.stderr)
                return 2
            command["device"] = argv[3]
        if parse_waveform(argv[1]) is None:
            print(f"unknown waveform {argv[1]!r}; one of: " + ", ".join(WAVEFORMS), file=sys.stderr)
            return 2
    elif argv == ["list"]:
        command = {"cmd": "list"}
    else:
        print(usage, file=sys.stderr)
        return 2

    result = ask_server(command)
    if result is None:
        # No widget running: do it here, at the cost of loading Solaar.
        sys.stdout, saved = sys.stderr, sys.stdout
        try:
            haptics = Haptics()
            result = handle(haptics, command)
            haptics.close()
        except Exception as e:
            result = {"error": f"solaar library unavailable: {e}"}
        finally:
            sys.stdout = saved

    if "error" in result:
        print(result["error"], file=sys.stderr)
        return 1
    if command["cmd"] == "list":
        print("waveforms: " + ", ".join(WAVEFORMS))
        for d in result["devices"]:
            print(f"{d['name']} ({d['id']}): " + ", ".join(d["waveforms"]))
        if not result["devices"]:
            print("no haptic device found")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["serve"]:
        try:
            serve()
        except KeyboardInterrupt:
            pass
    else:
        sys.exit(cli(sys.argv[1:]))
