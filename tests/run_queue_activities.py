"""Real Godot client + isolated HTTP server; no production accounts or rooms."""
from pathlib import Path
import json, os, subprocess, sys, tempfile, threading, time
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import dev_server
from tools.godot_runtime import default_godot
server=dev_server.server

class QueueFixture(dev_server.DevHandler):
    def _post(self):
        if self.path=='/test-queue-age':
            self.rfile.read(int(self.headers['Content-Length']))
            with server.lock:
                for entry in server.matchmaking.QUEUE.values(): entry['since']=time.time()-35
            self._json({'ok':True});return
        if self.path!='/test-queue': return super()._post()
        self.rfile.read(int(self.headers['Content-Length']))
        with server.lock:
            self._json({'ok':True,'rooms':list(server.ROOMS),'queue':list(server.matchmaking.QUEUE)})

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    folder=ROOT/'.dev-data'; folder.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='queue-ui-',dir=folder) as temp:
        os.environ['FOG_SECURITY_DB']=str(Path(temp)/'security.db')
        os.environ['FOG_REPLAY_DB']=str(Path(temp)/'replays.db')
        server.accounts.init_db(str(Path(temp)/'accounts.db'))
        users={'a':{'id':1,'name':'플레이어','rating':1000,'tier':'N'},'b':{'id':2,'name':'랭크 상대','rating':1020,'tier':'N'}}
        server.accounts.user_by_token=lambda token,**kwargs: users.get(token)
        server.draw_starting_color=lambda:'W'
        httpd=server.ThreadingServer(('127.0.0.1',0),QueueFixture)
        threading.Thread(target=httpd.serve_forever,daemon=True).start()
        script='queue_transition.gd' if '--transition' in sys.argv else 'queue_activities.gd'
        args=[default_godot(),'--path',str(ROOT/'godot'),'--script','res://tests/'+script,'--audio-driver','Dummy']
        args+=['--position','-16000,-16000'] if '--capture' in sys.argv else ['--headless']
        args+=['--','--smoke']+(['--capture'] if '--capture' in sys.argv else [])
        try:
            p=subprocess.run(args,env=dict(os.environ,FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}',APPDATA=str(Path(temp)/'appdata')),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=110,creationflags=0x08000000)
            text=p.stdout.decode('utf-8',errors='replace')
            (folder/(script+'.log')).write_text(text,encoding='utf-8')
            print(text)
            return int(p.returncode!=0 or 'ERROR:' in text or 'QUEUE_ACTIVITIES_FAILURES=0' not in text)
        except subprocess.TimeoutExpired as e:
            print((e.stdout or b'').decode('utf-8',errors='replace')); raise
        finally:
            httpd.shutdown();httpd.server_close();server.shutdown_bot_worker()

if __name__=='__main__': raise SystemExit(main())
