"""Native client checks with disposable accounts and forced black human seating."""
from pathlib import Path
import os,subprocess,sys,tempfile,threading
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tests'),str(ROOT)]
from run_board_focus_smoke import FocusFixture,server
from tools.godot_runtime import default_godot
OUT=Path(os.environ['FOG_CAPTURE_DIR']);OUT.mkdir(parents=True,exist_ok=True)
def main():
    with tempfile.TemporaryDirectory(prefix='accounts-',dir=OUT) as directory:
        server.accounts.init_db(str(Path(directory)/'users.db'))
        server.draw_starting_color=lambda:'B'
        env=dict(os.environ,FOG_SECURITY_DB=str(Path(directory)/'security.db'),FOG_REPLAY_DB=str(Path(directory)/'replays.db'))
        os.environ.update(FOG_SECURITY_DB=env['FOG_SECURITY_DB'],FOG_REPLAY_DB=env['FOG_REPLAY_DB'])
        httpd=server.ThreadingServer(('127.0.0.1',0),FocusFixture)
        threading.Thread(target=httpd.serve_forever,daemon=True).start()
        try:
            result=subprocess.run([default_godot(),'--path',str(ROOT/'godot'),'--script','res://tests/account_polish.gd','--position','-16000,-16000','--audio-driver','Dummy','--','--smoke'],env=dict(env,FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}'),capture_output=True,timeout=125)
            text=(result.stdout+result.stderr).decode('utf-8','replace');print(text)
            if result.returncode or 'SCRIPT ERROR' in text or 'FAILURES=0' not in text:raise SystemExit(1)
        finally:
            server.shutdown_bot_worker();httpd.shutdown();httpd.server_close()

if __name__=='__main__': main()
