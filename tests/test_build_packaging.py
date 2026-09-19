"""Packaging regression tests: settings catalogue merge and APK verification.

The settings test performs a real game assembly into a scratch directory
under .build (cleaned up afterwards) and proves the merged catalogue keeps
both the upstream VoxeLibre settings and every Theocraft mod's settings.
"""

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRATCH = ROOT / ".build" / "pytest-settingtypes"

VOXELIBRE_SETTING = "creative_mode (Creative mode) bool false"
THEOCRAFT_SETTINGS = (
    "theocraft_llm_enabled",
    "theocraft_halloween_enabled",
    "theocraft_circus_theo_mode",
)
BUNDLED_MODS = (
    "theocraft_villagers",
    "theocraft_halloween",
    "theocraft_circus",
    "theocraft_import",
)


def test_assembly_script_merges_base_voxelibre_settings() -> None:
    script = (ROOT / "scripts" / "Assemble-Game.ps1").read_text(encoding="utf-8")
    assert 'Join-Path $voxelibreSource "settingtypes.txt"' in script
    assert '"vendor\\voxelibre"' in script
    assert VOXELIBRE_SETTING in (
        ROOT / "vendor" / "voxelibre" / "settingtypes.txt"
    ).read_text(encoding="utf-8")


def test_settings_catalogue_merges_voxelibre_and_theocraft() -> None:
    if SCRATCH.exists():
        shutil.rmtree(SCRATCH)
    try:
        proc = subprocess.run(
            [
                "powershell.exe",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "scripts" / "Assemble-Game.ps1"),
                "-OutputDirectory",
                str(SCRATCH.relative_to(ROOT)),
            ],
            capture_output=True,
            text=True,
            timeout=600,
            cwd=str(ROOT),
        )
        assert proc.returncode == 0, proc.stderr[-2000:]
        merged = (SCRATCH / "settingtypes.txt").read_text(encoding="utf-8")
        assert VOXELIBRE_SETTING in merged
        for key in THEOCRAFT_SETTINGS:
            assert key in merged, key
        for mod in BUNDLED_MODS:
            assert (SCRATCH / "mods" / mod / "init.lua").is_file(), mod
    finally:
        shutil.rmtree(SCRATCH, ignore_errors=True)


def test_apk_verification_covers_all_bundled_mods() -> None:
    script = (ROOT / "scripts" / "Verify-AndroidApk.ps1").read_text(encoding="utf-8")
    assert "games/theocraft/game.conf" in script
    for mod in BUNDLED_MODS:
        assert f"games/theocraft/mods/{mod}/init.lua" in script, mod
