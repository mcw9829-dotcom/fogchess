"""Native Material motion regression; --capture writes local screenshots."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.godot_runtime import default_godot


def main():
    log = ROOT / '.dev-data' / 'material-ui-runtime.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    capture = '--capture' in sys.argv
    args = [default_godot(), '--path', str(ROOT / 'godot'), '--script',
            'res://tests/material_ui.gd', '--log-file', str(log)]
    args += ['--position', '-16000,-16000'] if capture else ['--headless']
    args += ['--', '--smoke'] + (['--capture'] if capture else [])
    result = subprocess.run(args, capture_output=True, timeout=60)
    output = (result.stdout + result.stderr).decode('utf-8', errors='replace')
    sys.stdout.reconfigure(encoding='utf-8')
    print(output)
    return int(result.returncode != 0 or 'ERROR:' in output or
               'MATERIAL_UI_FAILURES=0' not in output)


if __name__ == '__main__':
    raise SystemExit(main())
