from pathlib import Path
import os, sys, subprocess, tempfile, threading
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tests'))
sys.path.insert(0, str(ROOT))
from run_board_focus_smoke import FocusFixture, server
from tools.godot_runtime import default_godot
sys.stdout.reconfigure(encoding='utf-8')
outdir = Path(os.environ.get('FOG_CAPTURE_DIR', str(ROOT / '.dev-data' / 'targeting-captures')))
outdir.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='fog-targeting-') as tmp:
    server.accounts.init_db(str(Path(tmp)/'test.db'))
    httpd = server.ThreadingServer(('127.0.0.1',0), FocusFixture)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    args = [default_godot(), '--path', str(ROOT/'godot'), '--script', 'res://tests/targeting.gd']
    args += ['--position','-16000,-16000'] if '--capture' in sys.argv else ['--headless']
    args += ['--','--smoke']
    if '--capture' in sys.argv: args += ['--capture']
    try:
        result = subprocess.run(args, env=dict(os.environ, FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}',FOG_CAPTURE_DIR=str(outdir)),capture_output=True,timeout=60)
        output = result.stdout.decode('utf-8','replace')+result.stderr.decode('utf-8','replace')
        (outdir/'validation.log').write_text(output,encoding='utf-8')
        print(output)
        sys.exit(int(result.returncode != 0 or 'TARGETING_FAILURES=0' not in output or 'SCRIPT ERROR' in output))
    finally:
        httpd.shutdown()
        httpd.server_close()
