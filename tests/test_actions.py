#!/usr/bin/env python3
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACTIONS = (ROOT / "Actions.js").read_text(encoding="utf-8")
MANIFEST = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8"))


class ActionWhitelistTests(unittest.TestCase):
    def test_plugin_id_matches_manifest_and_settings_action(self):
        self.assertEqual(MANIFEST["id"], "io.github.omargond.omacorners")
        self.assertEqual(MANIFEST["name"], "Omacorners")
        self.assertIn("io.github.omargond.omacorners", ACTIONS)

    def test_order_and_meta_keys_match(self):
        order = re.search(r"var ORDER = \[([\s\S]+?)\]", ACTIONS)
        self.assertIsNotNone(order)
        ids = re.findall(r'"([^"]+)"', order.group(1))
        meta = re.search(r"var META = \{([\s\S]+?)\n\}", ACTIONS)
        self.assertIsNotNone(meta)
        meta_keys = re.findall(r'^\s+"([^"]+)": \{', meta.group(1), re.M)
        self.assertEqual(ids, meta_keys)
        self.assertEqual(ids[0], "none")
        self.assertIn("lock", ids)
        self.assertIn("desktop", ids)
        self.assertIn("hide-windows", ids)
        self.assertIn("shutdown", ids)
        self.assertIn("reboot", ids)
        self.assertIn("agent", ids)
        self.assertIn("settings", ids)

    def test_argv_entries_are_literal_arrays_of_strings(self):
        for match in re.finditer(r"argv:\s*\[([^\]]+)\]", ACTIONS):
            body = match.group(1)
            self.assertNotIn("+", body)
            self.assertNotIn("${", body)
            parts = re.findall(r'"([^"]*)"', body)
            self.assertTrue(parts, msg="argv must be a JSON-like string array: " + body)
            for part in parts:
                self.assertNotIn(" ", part)
                self.assertNotIn(";", part)
                self.assertNotIn("|", part)
                self.assertNotIn("`", part)

    def test_hypr_dispatch_strings_are_literals(self):
        dispatches = re.findall(r'dispatch:\s*"([^"]+)"', ACTIONS)
        self.assertTrue(dispatches)
        for item in dispatches:
            self.assertRegex(item, r"^[a-z0-9]+ [a-z0-9+._-]+$")

    def test_normalize_unknown_is_none(self):
        self.assertIn("if (isAppAction(id)) return id", ACTIONS)
        self.assertIn('return "none"', ACTIONS)

    def test_grok_agent_is_a_builtin(self):
        self.assertIn('label: "Grok"', ACTIONS)
        self.assertIn('["omarchy-agent"]', ACTIONS)
        self.assertIn('focusClass: "org.omarchy.agent"', ACTIONS)
        self.assertIn('"claude": { label: "Claude"', ACTIONS)
        self.assertIn("isAgentAction", ACTIONS)
        self.assertIn('"--app-id=org.omarchy.agent." + name', ACTIONS)

    def test_power_actions_use_omarchy_binaries(self):
        self.assertIn('["omarchy-system-shutdown"]', ACTIONS)
        self.assertIn('["omarchy-system-reboot"]', ACTIONS)
        self.assertIn("needsConfirm", ACTIONS)

    def test_app_launch_uses_gtk_launch_argv(self):
        self.assertIn('["uwsm-app", "--", "gtk-launch", desktop + ".desktop"]', ACTIONS)
        self.assertIn("isDesktopId", ACTIONS)
        self.assertNotIn("bash -lc", ACTIONS)

    def test_hide_windows_is_not_the_special_workspace_overlay(self):
        self.assertIn('"hide-windows": { label: "Hide windows", kind: "hide-windows" }', ACTIONS)
        self.assertIn("omacorners-hide", ACTIONS)
        self.assertIn("moveWindowSilentDispatch", ACTIONS)
        self.assertNotIn('"hide-windows": { label: "Hide windows", kind: "hypr"', ACTIONS)

    def test_no_shell_interpolation_helpers(self):
        lowered = ACTIONS.lower()
        self.assertNotIn("bash -lc", lowered)
        self.assertNotIn("bash -c", lowered)
        self.assertNotIn("shellquote", lowered)
        self.assertNotIn("execdetached(", lowered)


if __name__ == "__main__":
    unittest.main()
