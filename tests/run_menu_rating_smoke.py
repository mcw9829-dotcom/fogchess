from pathlib import Path
import json, os, subprocess, sys, tempfile, threading, time, uuid

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from run_godot_smoke import FixtureHandler, server
from tools.godot_runtime import default_godot

class FocusFixture(FixtureHandler):
    def _post(self):
        if self.path!='/test-focus': return super()._post()
        self.rfile.read(int(self.headers['Content-Length']))
        code=server.gen_code(); room=server.new_room(code)
        white=uuid.uuid4().hex; black=uuid.uuid4().hex
        room.update(seats={'W':white,'B':black},tokens={white:'W',black:'B'},seen={white:time.time(),black:time.time()},names={'W':'moon','B':'raven'},ratings={'W':1458,'B':1512})
        st=room['state'];st.update(phase='play',turn='W',turnCount=22,turn_deadline=time.time()+60)
        # Deliberate UI fixture in a temporary server, never a live development room.
        for pid,rc in {'W_B1':(7,5),'W_N1':(5,8),'B_N1':(4,8),'B_P1':(8,6)}.items():
            st['pieces'][pid].update(r=rc[0],c=rc[1],alive=True,moved=True)
            for group in ['forests','bushes','rivers','impassable']: room['terrain'][group].discard(rc)
        st['feed']=[{'seq':1,'actor':'W','atype':'N','method':'melee','victim':'B','vtype':'R'},{'seq':2,'actor':'B','atype':'N','method':'melee','victim':'W','vtype':'P'},{'seq':3,'actor':'W','atype':'B','method':'artillery','victim':'B','vtype':'N'}]
        st['feedseq']=3
        st['move_history']={'W':['12. e10','14. Nf7','16. Nxh6','18. Bg9','20. Bh10','22. Bf8']}
        for pid in ['B_P2','B_P3','B_P4','B_R1','B_N2']: st['pieces'][pid]['alive']=False
        st['captured']={'W':['P','P','P','R','N'],'B':['P']}
        with server.lock: server.ROOMS[code]=room
        self._json({'room':code,'token':white,'color':'W'})

def main():
    sys.stdout.reconfigure(encoding='utf-8')
    with tempfile.TemporaryDirectory(prefix='fog-focus-test-') as directory:
        server.accounts.init_db(str(Path(directory)/'test.db'))
        httpd=server.ThreadingServer(('127.0.0.1',0),FocusFixture)
        threading.Thread(target=httpd.serve_forever,daemon=True).start()
        args=[default_godot(),'--path',str(ROOT/'godot'),'--script','res://tests/menu_rating.gd',
              '--log-file',str(ROOT/'.dev-data'/'menu-rating-runtime.log')]
        if '--capture' in sys.argv: args+=['--position','-16000,-16000']
        else: args+=['--headless']
        args+=['--','--smoke']
        if '--capture' in sys.argv: args+=['--capture']
        try:
            p=subprocess.run(args,env=dict(os.environ,FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}'),capture_output=True,timeout=60)
            out=p.stdout.decode('utf-8',errors='replace')+p.stderr.decode('utf-8',errors='replace')
            print(out)
            return int(p.returncode!=0 or 'MENU_RATING_FAILURES=0' not in out or 'SCRIPT ERROR' in out)
        except subprocess.TimeoutExpired as exc:
            print((exc.stdout or b'').decode('utf-8',errors='replace'))
            print((exc.stderr or b'').decode('utf-8',errors='replace'))
            raise
        finally: httpd.shutdown();httpd.server_close()

if __name__=='__main__': raise SystemExit(main())
