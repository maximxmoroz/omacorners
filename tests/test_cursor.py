#!/usr/bin/env python3
import importlib.util
import os
import stat
import tempfile
import unittest
from importlib.machinery import SourceFileLoader
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts" / "omacorners-cursor"


def load_helper():
    loader = SourceFileLoader("omacorners_cursor", str(HELPER))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


class CursorHelperTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_helper()

    def test_parse_cursorpos_plain(self):
        self.assertEqual(self.mod.parse_cursorpos("977, 601"), (977, 601))
        self.assertEqual(self.mod.parse_cursorpos("0,0"), (0, 0))
        self.assertEqual(self.mod.parse_cursorpos("  -12,  40\n"), (-12, 40))

    def test_parse_cursorpos_json(self):
        self.assertEqual(self.mod.parse_cursorpos('{"x": 10, "y": 20}'), (10, 20))

    def test_parse_cursorpos_rejects_garbage(self):
        self.assertIsNone(self.mod.parse_cursorpos(""))
        self.assertIsNone(self.mod.parse_cursorpos("nope"))
        self.assertIsNone(self.mod.parse_cursorpos("1,2,3"))
        self.assertIsNone(self.mod.parse_cursorpos('{"x": "no"}'))
        self.assertIsNone(self.mod.parse_cursorpos("[]"))

    def test_parse_monitors_applies_scale(self):
        raw = """
        [{"name": "DP-2", "x": 0, "y": 0, "width": 3440, "height": 1440, "scale": 2}]
        """
        mons = self.mod.parse_monitors(raw)
        self.assertEqual(len(mons), 1)
        self.assertEqual(mons[0]["width"], 1720)
        self.assertEqual(mons[0]["height"], 720)
        self.assertEqual(mons[0]["name"], "DP-2")

    def test_hit_corner_uses_logical_hdmi_geometry(self):
        mons = [
            {"name": "eDP-1", "x": 0, "y": 0, "width": 1920, "height": 1080},
            {"name": "HDMI-A-1", "x": 1920, "y": 0, "width": 2048, "height": 1152},
        ]
        self.assertEqual(self.mod.hit_corner(3967, 1151, mons, 16), ("br", "HDMI-A-1"))
        self.assertEqual(self.mod.hit_corner(1919, 1079, mons, 16), ("br", "eDP-1"))
        self.assertEqual(self.mod.hit_corner(1920, 0, mons, 16), ("tl", "HDMI-A-1"))
        self.assertEqual(self.mod.hit_corner(3000, 500, mons, 16), ("none", "-"))

    def test_parse_monitors_caps_and_skips_junk(self):
        self.assertEqual(self.mod.parse_monitors("nope"), [])
        self.assertEqual(self.mod.parse_monitors("{}"), [])
        payload = [{"name": "M%d" % i, "x": i * 100, "y": 0, "width": 100, "height": 100, "scale": 1} for i in range(20)]
        import json
        mons = self.mod.parse_monitors(json.dumps(payload))
        self.assertEqual(len(mons), 16)

    def test_near_edge_detects_corners_and_edges(self):
        mons = [{"name": "A", "x": 0, "y": 0, "width": 100, "height": 80}]
        self.assertTrue(self.mod.near_edge(0, 0, mons, 8))
        self.assertTrue(self.mod.near_edge(99, 79, mons, 8))
        self.assertTrue(self.mod.near_edge(50, 2, mons, 8))
        self.assertFalse(self.mod.near_edge(50, 40, mons, 8))
        self.assertFalse(self.mod.near_edge(-1, 0, mons, 8))

    def test_find_socket_rejects_bad_signature(self):
        self.assertIsNone(self.mod.find_socket({"HYPRLAND_INSTANCE_SIGNATURE": "../etc", "XDG_RUNTIME_DIR": "/tmp"}))
        self.assertIsNone(self.mod.find_socket({"HYPRLAND_INSTANCE_SIGNATURE": "a/b", "XDG_RUNTIME_DIR": "/tmp"}))
        self.assertIsNone(self.mod.find_socket({"HYPRLAND_INSTANCE_SIGNATURE": "", "XDG_RUNTIME_DIR": "/tmp"}))

    def test_find_socket_accepts_unix_socket(self):
        with tempfile.TemporaryDirectory() as tmp:
            sig = "testsig_omacorners"
            sock_dir = Path(tmp) / "hypr" / sig
            sock_dir.mkdir(parents=True)
            sock_path = sock_dir / ".socket.sock"
            import socket as smod
            srv = smod.socket(smod.AF_UNIX, smod.SOCK_STREAM)
            srv.bind(str(sock_path))
            try:
                found = self.mod.find_socket({
                    "HYPRLAND_INSTANCE_SIGNATURE": sig,
                    "XDG_RUNTIME_DIR": tmp,
                })
                self.assertEqual(found, str(sock_path))
            finally:
                srv.close()
                try:
                    os.unlink(sock_path)
                except OSError:
                    pass

    def test_stat_is_socket_rejects_regular_file(self):
        with tempfile.NamedTemporaryFile(delete=False) as fh:
            path = fh.name
        try:
            self.assertFalse(self.mod.stat_is_socket(path))
        finally:
            os.unlink(path)

    def test_helper_is_regular_python(self):
        self.assertTrue(HELPER.is_file())
        self.assertFalse(HELPER.is_symlink())
        mode = HELPER.stat().st_mode
        self.assertTrue(stat.S_ISREG(mode))

    def test_parse_evdev_and_apply_super_and_buttons(self):
        import struct
        fmt = "llHHi"
        payload = struct.pack(fmt, 0, 0, 1, 125, 1) + struct.pack(fmt, 0, 0, 1, 272, 1)
        events = self.mod.parse_evdev_events(payload)
        self.assertEqual(events, [(1, 125, 1), (1, 272, 1)])
        meta, buttons = set(), set()
        for ev in events:
            self.mod.apply_evdev(*ev, meta, buttons)
        self.assertEqual(meta, {125})
        self.assertEqual(buttons, {272})
        self.mod.apply_evdev(1, 125, 0, meta, buttons)
        self.mod.apply_evdev(1, 272, 0, meta, buttons)
        self.assertEqual(meta, set())
        self.assertEqual(buttons, set())


if __name__ == "__main__":
    unittest.main()
