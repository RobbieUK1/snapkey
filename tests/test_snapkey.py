#!/usr/bin/env python3
"""Tests for Snapkey's binding helper.

Every test runs the real helper in a subprocess against a temporary
bindings.lua and a fake hyprctl, so no Hyprland state is touched.
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "plugin" / "snapkey"

FAKE_HYPRCTL = textwrap.dedent(
    """\
    #!/usr/bin/env bash
    set -euo pipefail
    case "${1:-}" in
      -j)
        if [[ ${2:-} == binds ]]; then
          if [[ -n ${FAKE_BINDS:-} && -f ${FAKE_BINDS} ]]; then
            cat "${FAKE_BINDS}"
          else
            printf '[]'
          fi
        fi
        ;;
      reload)
        printf 'ok\\n'
        if [[ -n ${FAKE_RELOAD_ERROR:-} ]]; then
          printf '%s\\n' "${FAKE_RELOAD_ERROR}" >&2
          exit 1
        fi
        ;;
      configerrors)
        printf '%s' "${FAKE_CONFIG_ERRORS:-}"
        ;;
    esac
    exit 0
    """
)

DEFAULT_BINDS = [
    {"modmask": 0, "key": "PRINT", "description": "Screenshot"},
    {"modmask": 76, "key": "C", "description": "Screenshot"},
    {"modmask": 68, "key": "PRINT", "description": "Extract text (OCR) from screenshot"},
    {"modmask": 68, "key": "C", "description": "Capture menu"},
]


class SnapkeyTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tempdir.cleanup)
        self.home = Path(self.tempdir.name)
        self.bindings = self.home / ".config" / "hypr" / "bindings.lua"
        self.bindings.parent.mkdir(parents=True)

        self.hyprctl = self.home / "hyprctl"
        self.hyprctl.write_text(FAKE_HYPRCTL, encoding="utf-8")
        self.hyprctl.chmod(0o755)

        self.binds_json = self.home / "binds.json"
        self.write_binds(DEFAULT_BINDS)

        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "SNAPKEY_BINDINGS": str(self.bindings),
                "SNAPKEY_HYPRCTL": str(self.hyprctl),
                "FAKE_BINDS": str(self.binds_json),
            }
        )
        for key in ("FAKE_CONFIG_ERRORS", "FAKE_RELOAD_ERROR"):
            self.env.pop(key, None)

    def write_binds(self, entries: list[dict]) -> None:
        self.binds_json.write_text(json.dumps(entries), encoding="utf-8")

    def run_helper(self, *args: str) -> tuple[int, dict, str, str]:
        process = subprocess.run(
            [str(HELPER), *args],
            capture_output=True,
            text=True,
            env=self.env,
            timeout=30,
            check=False,
        )
        try:
            payload = json.loads(process.stdout)
        except json.JSONDecodeError:
            payload = {}
        return process.returncode, payload, process.stdout, process.stderr

    def actions_by_id(self, payload: dict) -> dict[str, dict]:
        return {action["id"]: action for action in payload.get("actions", [])}

    # ------------------------------------------------------------------ status

    def test_status_reports_omarchy_defaults(self) -> None:
        code, payload, _, _ = self.run_helper("status")
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["hyprland"])

        actions = self.actions_by_id(payload)
        self.assertEqual(actions["smart"]["chord"], "PRINT")
        self.assertEqual(actions["smart"]["source"], "default")
        self.assertEqual(actions["text"]["chord"], "SUPER + CTRL + PRINT")
        self.assertEqual(actions["menu"]["chord"], "SUPER + CTRL + C")
        self.assertEqual(actions["region"]["chord"], "")
        self.assertEqual(actions["region"]["source"], "")

    def test_status_without_hyprctl_falls_back_to_first_defaults(self) -> None:
        self.env["SNAPKEY_HYPRCTL"] = str(self.home / "missing-hyprctl")
        code, payload, _, _ = self.run_helper("status")
        self.assertEqual(code, 0)
        self.assertFalse(payload["hyprland"])
        self.assertEqual(self.actions_by_id(payload)["smart"]["chord"], "PRINT")

    def test_region_takes_print_from_smart(self) -> None:
        post = [
            {"modmask": 0, "key": "PRINT", "description": "Snapkey: Region"},
            {"modmask": 76, "key": "C", "description": "Screenshot"},
        ]
        self.write_binds(post)
        code, payload, _, _ = self.run_helper("status")
        self.assertEqual(code, 0)
        actions = self.actions_by_id(payload)
        self.assertEqual(actions["smart"]["chord"], "SUPER + CTRL + ALT + C")
        self.assertEqual(actions["smart"]["source"], "default")

    # --------------------------------------------------------------- writing

    def test_set_region_writes_managed_block_and_keeps_user_lines(self) -> None:
        original = (
            "-- personal bindings\n"
            'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        )
        self.bindings.write_text(original, encoding="utf-8")

        code, payload, _, _ = self.run_helper("set", "region", "PRINT")
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["changed"])
        self.assertEqual(payload["replaced"], "Screenshot")

        text = self.bindings.read_text(encoding="utf-8")
        self.assertIn("-- personal bindings", text)
        self.assertIn('o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")', text)
        self.assertIn("-- Snapkey: screenshot keys (start)", text)
        self.assertIn("-- Snapkey: screenshot keys (end)", text)
        self.assertIn(
            'o.rebind("PRINT", "Snapkey: Region", '
            '"omarchy capture screenshot region")',
            text,
        )

        actions = self.actions_by_id(payload)
        self.assertEqual(actions["region"]["chord"], "PRINT")
        self.assertEqual(actions["region"]["source"], "custom")

    def test_missing_bindings_file_is_created(self) -> None:
        self.assertFalse(self.bindings.exists())
        code, payload, _, _ = self.run_helper("set", "region", "PRINT")
        self.assertEqual(code, 0)
        self.assertTrue(payload["changed"])
        self.assertTrue(self.bindings.exists())
        self.assertFalse(self.bindings.with_name("bindings.lua.bak.snapkey").exists())

    def test_backup_is_written_once(self) -> None:
        original = 'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        self.bindings.write_text(original, encoding="utf-8")

        self.run_helper("set", "region", "PRINT")
        backup = self.bindings.with_name("bindings.lua.bak.snapkey")
        self.assertTrue(backup.exists())
        self.assertEqual(backup.read_text(encoding="utf-8"), original)

        self.run_helper("set", "window", "SUPER + PRINT")
        self.assertEqual(backup.read_text(encoding="utf-8"), original)

    def test_set_normalizes_chords(self) -> None:
        code, payload, _, _ = self.run_helper("set", "region", "ctrl+print")
        self.assertEqual(code, 0)
        self.assertEqual(self.actions_by_id(payload)["region"]["chord"], "CTRL + PRINT")

    def test_set_rejects_unusable_chord(self) -> None:
        code, payload, _, _ = self.run_helper("set", "region", "not a key")
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertIn("cannot be bound", payload["error"])
        self.assertFalse(self.bindings.exists())

    def test_unknown_action_is_rejected(self) -> None:
        code, payload, _, _ = self.run_helper("set", "nope", "PRINT")
        self.assertEqual(code, 1)
        self.assertIn("Unknown action", payload["error"])

    # -------------------------------------------------------------- conflicts

    def test_check_reports_another_snapkey_action(self) -> None:
        self.run_helper("set", "region", "PRINT")
        code, payload, _, _ = self.run_helper("check", "window", "PRINT")
        self.assertEqual(code, 0)
        self.assertEqual(payload["conflict"], {"kind": "snapkey", "label": "Region"})

    def test_check_reports_a_plain_binding(self) -> None:
        code, payload, _, _ = self.run_helper("check", "region", "SUPER + CTRL + C")
        self.assertEqual(code, 0)
        self.assertEqual(payload["conflict"]["kind"], "binding")
        self.assertEqual(payload["conflict"]["label"], "Capture menu")

    def test_set_refuses_conflict_between_snapkey_actions(self) -> None:
        self.run_helper("set", "region", "PRINT")
        before = self.bindings.read_text(encoding="utf-8")

        code, payload, _, _ = self.run_helper("set", "window", "PRINT")
        self.assertEqual(code, 1)
        self.assertIn("already assigned to Region", payload["error"])
        self.assertEqual(self.bindings.read_text(encoding="utf-8"), before)

    # ------------------------------------------------------------------ reset

    def test_reset_restores_original_file(self) -> None:
        original = (
            "-- personal bindings\n"
            'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        )
        self.bindings.write_text(original, encoding="utf-8")

        self.run_helper("set", "region", "PRINT")
        code, payload, _, _ = self.run_helper("reset", "region")
        self.assertEqual(code, 0)
        self.assertTrue(payload["changed"])
        self.assertEqual(self.bindings.read_text(encoding="utf-8"), original)

    def test_reset_all_restores_original_file(self) -> None:
        original = 'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        self.bindings.write_text(original, encoding="utf-8")

        self.run_helper("set", "region", "PRINT")
        self.run_helper("set", "window", "SUPER + PRINT")

        code, payload, _, _ = self.run_helper("reset-all")
        self.assertEqual(code, 0)
        self.assertTrue(payload["changed"])
        self.assertEqual(self.bindings.read_text(encoding="utf-8"), original)

    # --------------------------------------------------------------- rollback

    def test_rollback_when_hyprland_rejects_the_config(self) -> None:
        original = 'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        self.bindings.write_text(original, encoding="utf-8")
        self.env["FAKE_CONFIG_ERRORS"] = "error: bad binding at line 40"

        code, payload, _, _ = self.run_helper("set", "region", "PRINT")
        self.assertEqual(code, 1)
        self.assertIn("Hyprland rejected the change", payload["error"])
        self.assertEqual(self.bindings.read_text(encoding="utf-8"), original)

    def test_rollback_when_reload_fails(self) -> None:
        original = 'o.bind("SUPER + SHIFT + T", "Terminal", "alacritty")\n'
        self.bindings.write_text(original, encoding="utf-8")
        self.env["FAKE_RELOAD_ERROR"] = "reload failed"

        code, payload, _, _ = self.run_helper("set", "region", "PRINT")
        self.assertEqual(code, 1)
        self.assertIn("reload failed", payload["error"])
        self.assertEqual(self.bindings.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
