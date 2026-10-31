from pathlib import Path
import os,sys,tempfile,subprocess,threading
ROOT=Path(__file__).resolve().parents[1]
HERE=Path(__file__).parent.resolve()
sys.path[:0]=[str(ROOT/'tests'),str(ROOT)]
from tools.godot_runtime import default_godot
sys.stdout.reconfigure(encoding='utf-8')
out=ROOT/'.dev-data/lobby-b-captures';out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='fog-lobby-') as tmp:
    os.environ['FOG_SECURITY_DB']=str(Path(tmp)/'security.sqlite3')
    os.environ['FOG_REPLAY_DB']=str(Path(tmp)/'replays.sqlite3')
    from run_board_focus_smoke import FocusFixture,server
    if '--host-color' in sys.argv:
        host_color=sys.argv[sys.argv.index('--host-color')+1]
        if host_color not in ('W','B'): raise SystemExit('--host-color must be W or B')
        server.draw_starting_color=lambda:host_color
        print('FIXTURE_HOST_COLOR='+host_color)
    server.accounts.init_db(str(Path(tmp)/'test.db'))
    httpd=server.ThreadingServer(('127.0.0.1',0),FocusFixture)
    threading.Thread(target=httpd.serve_forever,daemon=True).start()
    script=Path(sys.argv[sys.argv.index('--script')+1]).resolve() if '--script' in sys.argv else ROOT/'godot/tests/lobby_b.gd'
    args=[default_godot(),'--path',str(ROOT/'godot'),'--script',str(script)]
    args+=['--position','-16000,-16000'] if '--capture' in sys.argv else ['--headless']
    args+=['--','--smoke']+(['--capture'] if '--capture' in sys.argv else [])
    try:
        p=subprocess.run(args,env=dict(os.environ,APPDATA=str(Path(tmp)/'runtime-home'),FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}',FOG_CAPTURE_DIR=str(out)),capture_output=True,timeout=100)
        log=p.stdout.decode('utf-8','replace')+p.stderr.decode('utf-8','replace')
        (out/(script.stem+'.log')).write_text(log,encoding='utf-8')
        print(log[-18000:])
        sys.exit(int(p.returncode!=0 or 'SCRIPT ERROR' in log or 'LOBBY_FAILURES=0' not in log))
    finally:httpd.shutdown();httpd.server_close()
