"""Keep local Booking OS ports forwarded to an explicitly selected Android phone.

Uses the existing ADB pairing; never pairs, disconnects, installs, or clears data.
"""

import argparse
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import threading

PORTS = (9099, 3000)
LABEL = "com.bookingos.android-connection"
ROOT = Path(__file__).resolve().parents[1]
AGENT = Path.home() / "Library" / "LaunchAgents" / f"{LABEL}.plist"
LOG_DIR = ROOT / ".local" / "android-connection"
LOGGER = logging.getLogger("android-connection")


def command(argv):
    return subprocess.run(
        argv, capture_output=True, text=True, timeout=8, check=True
    ).stdout


def connected_devices(output):
    """Ignore offline, unauthorized and discovery-only devices."""
    return [
        parts[0]
        for line in output.splitlines()
        if len(parts := line.split()) >= 2 and parts[1] == "device"
    ]


def forwarded_ports(output):
    return {
        (parts[-2], parts[-1])
        for line in output.splitlines()
        if len(parts := line.split()) >= 3
    }


class ConnectionKeeper:
    def __init__(self, adb, devices, prefixes, run=command):
        self.adb, self.devices, self.prefixes, self.run = adb, devices, prefixes, run
        self.previous = {}

    def transition(self, key, value):
        if self.previous.get(key) != value:
            LOGGER.info(value)
            self.previous[key] = value

    def check(self):
        try:
            attached = connected_devices(self.run([self.adb, "devices"]))
        except (subprocess.SubprocessError, OSError):
            self.transition("adb", "ADB unavailable; retrying automatically.")
            return False
        self.transition("adb", "ADB available.")
        selected = [
            serial for serial in attached
            if serial in self.devices or any(serial.startswith(p) for p in self.prefixes)
        ]
        for serial in list(self.previous):
            if serial != "adb" and serial not in selected:
                self.previous.pop(serial)
        if not selected:
            self.transition("connection", "Waiting for the selected debugging phone.")
            return False
        self.previous.pop("connection", None)
        healthy = True
        for serial in selected:
            try:
                base = [self.adb, "-s", serial, "reverse"]
                existing = forwarded_ports(self.run([*base, "--list"]))
                for port in PORTS:
                    pair = (f"tcp:{port}", f"tcp:{port}")
                    if pair not in existing:
                        self.run([*base, *pair])
                        LOGGER.info("Restored phone forwarding for port %s.", port)
                verified = forwarded_ports(self.run([*base, "--list"]))
                if not all((f"tcp:{p}", f"tcp:{p}") in verified for p in PORTS):
                    raise RuntimeError("Forwarding not ready")
                self.transition(serial, "Selected phone connected: Auth 9099 and API 3000 ready.")
            except (subprocess.SubprocessError, OSError, RuntimeError):
                healthy = False
                self.transition(serial, "Phone connection not ready; retrying automatically.")
        return healthy


def install(args):
    if sys.platform != "darwin":
        raise SystemExit("Automatic login startup uses macOS launchd. Use --run elsewhere.")
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    argv = [sys.executable, str(Path(__file__).resolve()), "--run", "--adb", args.adb]
    for device in args.device:
        argv += ["--device", device]
    for prefix in args.device_prefix:
        argv += ["--device-prefix", prefix]
    argv += ["--interval", str(args.interval), "--log-file", str(LOG_DIR / "connection.log")]
    payload = {
        "Label": LABEL,
        "ProgramArguments": argv,
        "WorkingDirectory": str(ROOT),
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": str(LOG_DIR / "startup-error.log"),
    }
    temp = AGENT.with_suffix(".plist.tmp")
    temp.write_bytes(plistlib.dumps(payload))
    temp.chmod(0o600)
    temp.replace(AGENT)
    domain = f"gui/{os.getuid()}"
    subprocess.run(["launchctl", "bootout", f"{domain}/{LABEL}"], capture_output=True)
    command(["launchctl", "bootstrap", domain, str(AGENT)])
    print("Automatic phone forwarding installed and started; it will also start at macOS login.")
    print(f"Log: {LOG_DIR / 'connection.log'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group(required=True)
    for mode in ("run", "once", "install", "uninstall", "status"):
        modes.add_argument(f"--{mode}", action="store_true")
    parser.add_argument("--adb", default=shutil.which("adb"))
    parser.add_argument("--device", action="append", default=[], help="Exact authorized ADB serial")
    parser.add_argument("--device-prefix", action="append", default=[], help="Stable wireless ADB serial prefix")
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--log-file", type=Path)
    args = parser.parse_args()
    if args.uninstall:
        subprocess.run(
            ["launchctl", "bootout", f"gui/{os.getuid()}/{LABEL}"], capture_output=True
        )
        AGENT.unlink(missing_ok=True)
        print("Automatic forwarding stopped and removed. Existing forwarding is unchanged.")
        return
    if args.status:
        try:
            output = command(["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"])
            print("Automatic forwarding is running." if "state = running" in output else "Helper loaded; check logs for startup status.")
        except (subprocess.SubprocessError, OSError):
            print("Automatic forwarding is not loaded.")
            raise SystemExit(1)
        print(f"Log: {LOG_DIR / 'connection.log'}")
        return
    if not args.adb or not Path(args.adb).is_file():
        parser.error("ADB not found. Supply --adb with its absolute path.")
    args.adb = str(Path(args.adb).absolute())
    if not args.device and not args.device_prefix:
        parser.error("Select your phone with --device and/or --device-prefix.")
    if any(len(p) < 8 or p.strip() != p for p in args.device_prefix):
        parser.error("Use a specific phone prefix of at least 8 characters.")
    if args.interval < 2 or args.interval > 60:
        parser.error("Interval must be between 2 and 60 seconds.")
    if args.install:
        install(args)
        return
    handler = logging.StreamHandler()
    if args.log_file:
        args.log_file.parent.mkdir(parents=True, exist_ok=True)
        handler = RotatingFileHandler(args.log_file, maxBytes=200_000, backupCount=2)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", handlers=[handler])
    keeper = ConnectionKeeper(args.adb, args.device, args.device_prefix)
    if args.once:
        raise SystemExit(0 if keeper.check() else 1)
    stop = threading.Event()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, lambda *_: stop.set())
    while not stop.is_set():
        keeper.check()
        stop.wait(args.interval)


if __name__ == "__main__":
    main()
