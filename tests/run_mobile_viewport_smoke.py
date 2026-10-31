"""Exercise CSS-pixel layout and physical-pixel input with an isolated game server."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '.dev-data/mobile-viewport-captures'
OUT.mkdir(parents=True, exist_ok=True)
sys.path[:0] = [str(ROOT / 'tests'), str(ROOT)]
with tempfile.TemporaryDirectory(prefix='fixture-', dir=OUT) as tmp:
    os.environ['FOG_SECURITY_DB'] = str(Path(tmp) / 'security.db')
    os.environ['FOG_REPLAY_DB'] = str(Path(tmp) / 'replays.db')
    from run_board_focus_smoke import FocusFixture, server
    from tools.godot_runtime import default_godot
    server.accounts.init_db(str(Path(tmp) / 'accounts.db'))
    httpd = server.ThreadingServer(('127.0.0.1', 0), FocusFixture)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    try:
        result = subprocess.run([
            default_godot(), '--path', str(ROOT / 'godot'),
            '--script', 'res://tests/mobile_viewport.gd',
            '--position', '-16000,-16000', '--audio-driver', 'Dummy', '--', '--smoke',
        ], env=dict(os.environ, APPDATA=str(OUT / 'runtime-home'),
                    FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}',
                    FOG_CAPTURE_DIR=str(OUT)), capture_output=True, timeout=150)
        log = (result.stdout + result.stderr).decode('utf-8', 'replace')
        (OUT / 'checks.log').write_text(log, encoding='utf-8')
        print(log)
        if result.returncode or 'SCRIPT ERROR' in log or 'FAILURES=0' not in log:
            raise SystemExit(1)
    finally:
        httpd.shutdown()
        httpd.server_close()
