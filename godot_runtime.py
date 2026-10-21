"""Select the project-local stable Godot runtime (Windows Korean IME fix)."""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
VERSION = "4.7.1"
LOCAL_EXE = ROOT / ".dev-data" / "tools" / "godot-4.7.1" / "Godot_v4.7.1-stable_win64.exe"
STEAM_EXE = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")


def default_godot():
    # An explicit override always wins, including on Linux/macOS CI.
    if os.environ.get("GODOT_EXE"):
        return os.environ["GODOT_EXE"]
    if LOCAL_EXE.is_file():
        return str(LOCAL_EXE)
    return str(STEAM_EXE) if os.name == "nt" else "godot"


if __name__ == "__main__":
    print(default_godot())
