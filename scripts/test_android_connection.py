"""Connection recovery tests; no real devices or services are modified."""

import subprocess
import unittest

from android_connection import ConnectionKeeper


class FakeAdb:
    def __init__(self):
        self.devices = {}
        self.mappings = {}
        self.writes = []
        self.fail = False

    def __call__(self, argv):
        if self.fail:
            raise subprocess.TimeoutExpired(argv, 8)
        if argv[1:] == ["devices"]:
            return "List of devices attached\n" + "\n".join(
                f"{serial}\t{state}" for serial, state in self.devices.items()
            )
        serial = argv[2]
        mappings = self.mappings.setdefault(serial, {})
        if argv[-1] == "--list":
            return "\n".join(f"host {local} {remote}" for local, remote in mappings.items())
        local, remote = argv[-2:]
        mappings[local] = remote
        self.writes.append((serial, local, remote))
        return ""


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        self.adb = FakeAdb()
        self.keeper = ConnectionKeeper("/fake/adb", ["PHONE123"], ["adb-PHONE123-"], self.adb)

    def test_reconnect_restores_both_ports_without_repeating_healthy_writes(self):
        self.adb.devices = {"adb-PHONE123-first": "device"}
        self.assertTrue(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 2)
        self.assertTrue(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 2)
        self.adb.devices.clear()
        self.assertFalse(self.keeper.check())
        self.adb.devices = {"adb-PHONE123-new-session": "device"}
        self.assertTrue(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 4)

    def test_unrelated_offline_and_unauthorized_devices_are_untouched(self):
        self.adb.devices = {"OTHER123": "device", "PHONE123": "offline", "adb-PHONE123-new": "unauthorized"}
        self.assertFalse(self.keeper.check())
        self.assertEqual(self.adb.writes, [])

    def test_usb_connection_and_missing_or_wrong_mapping_are_repaired(self):
        self.adb.devices = {"PHONE123": "device"}
        self.adb.mappings = {"PHONE123": {"tcp:9099": "tcp:1111", "tcp:8080": "tcp:8080"}}
        self.assertTrue(self.keeper.check())
        self.assertEqual(self.adb.mappings["PHONE123"]["tcp:9099"], "tcp:9099")
        self.assertEqual(self.adb.mappings["PHONE123"]["tcp:8080"], "tcp:8080")
        del self.adb.mappings["PHONE123"]["tcp:3000"]
        self.assertTrue(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 3)

    def test_adb_timeout_recovers_on_next_check(self):
        self.adb.fail = True
        self.assertFalse(self.keeper.check())
        self.adb.fail = False
        self.adb.devices = {"PHONE123": "device"}
        self.assertTrue(self.keeper.check())

    def test_failed_forward_retries_without_losing_other_mapping(self):
        self.adb.devices = {"PHONE123": "device"}
        real_run = self.keeper.run

        def fail_api(argv):
            if argv[-2:] == ["tcp:3000", "tcp:3000"]:
                raise subprocess.CalledProcessError(1, argv)
            return real_run(argv)

        self.keeper.run = fail_api
        self.assertFalse(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 1)
        self.keeper.run = real_run
        self.assertTrue(self.keeper.check())
        self.assertEqual(len(self.adb.writes), 2)


if __name__ == "__main__":
    unittest.main()
