"""Setup card actions against an isolated local server, optionally rendered."""
from pathlib import Path
import os, subprocess, sys, tempfile, threading

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import dev_server
from run_board_focus_smoke import FocusFixture
from tools.godot_runtime import default_godot

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='fog-setup-ui-') as directory:
        dev_server.server.accounts.init_db(str(Path(directory)/'test.db'))
        httpd=dev_server.server.ThreadingServer(('127.0.0.1',0),FocusFixture)
        threading.Thread(target=httpd.serve_forever,daemon=True).start()
        args=[default_godot(),'--path',str(ROOT/'godot'),'--script','res://tests/calm_motion.gd',
              '--log-file',str(ROOT/'.dev-data/calm-motion-runtime.log')]
        capture='--capture' in sys.argv
        args+=['--position','-16000,-16000'] if capture else ['--headless']
        args+=['--','--smoke']+(['--capture'] if capture else [])
        try:
            p=subprocess.run(args,env=dict(os.environ,FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}'),capture_output=True,timeout=60)
            text=(p.stdout+p.stderr).decode('utf-8',errors='replace')
            print(text)
            return int(p.returncode!=0 or 'ERROR:' in text or 'CALM_MOTION_FAILURES=0' not in text)
        finally:
            httpd.shutdown()
            httpd.server_close()

if __name__=='__main__': raise SystemExit(main())
