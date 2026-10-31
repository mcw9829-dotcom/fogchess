"""Real Godot + HTTP admin workflows in disposable account/replay/security databases."""
import os,sys,tempfile,uuid,time,threading,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from tools.godot_runtime import default_godot

def main():
 with tempfile.TemporaryDirectory(prefix='fog-admin-qa-') as folder:
  os.environ.update(FOG_DB=str(Path(folder)/'accounts.db'),FOG_REPLAY_DB=str(Path(folder)/'replays.db'),FOG_SECURITY_DB=str(Path(folder)/'security.db'),FOG_ADMIN_KEY=uuid.uuid4().hex)
  import accounts,server,admin_ops,spectator,web_server
  accounts.init_db()
  a,_=accounts.signup('LocalTester','Fixture-Password-492!');b,_=accounts.signup('TestOpponent','Fixture-Password-492!')
  accounts.add_feedback('bug','Godot admin fixture','LocalTester',a['user']['id'],None,'Godot test')
  admin_ops.touch(a['user']['id'])
  r=server.new_room('QA01');r.update(match=True,users={'W':a['user']['id'],'B':b['user']['id']},names={'W':'LocalTester','B':'TestOpponent'},ratings={'W':1000,'B':1000})
  r['state'].update(phase='play',turn_deadline=None);spectator.capture(r)
  r['state'].setdefault('notation',[]).append({'action':'fire','actor':'W','captures':1,'turn':1,'compact':'Be8'})
  r['state'].update(phase='over',winner='W');server.settle_rating(r);spectator.capture(r)
  admin_ops.mutate('notice',dict(requestId=uuid.uuid4().hex,title='운영 데스크 연결 확인',body='테스트 공지입니다. 실제 서버에 게시되지 않습니다.\n진행 중인 대국은 점검 중에도 유지됩니다.',kind='operations',published=True,reason='격리 테스트'),'QA operator')
  httpd=server.ThreadingServer(('127.0.0.1',0),web_server.WebHandler)
  threading.Thread(target=httpd.serve_forever,daemon=True).start()
  capture=ROOT.parents[2]/'outputs'/'fogchess-admin-applied'/'assets';capture.mkdir(parents=True,exist_ok=True)
  env=dict(os.environ,FOG_TEST_URL=f'http://127.0.0.1:{httpd.server_port}',FOG_TEST_ADMIN_KEY=os.environ['FOG_ADMIN_KEY'],FOG_ADMIN_CAPTURE=str(capture))
  args=[default_godot(),'--path',str(ROOT/'godot'),'--script','res://tests/admin_ops_smoke.gd']
  if '--capture' not in sys.argv:args+=['--headless']
  args+=['--','--smoke']
  if '--capture' in sys.argv:args+=['--admin-capture']
  try:
   run=subprocess.run(args,env=env,capture_output=True,timeout=65)
   output=(run.stdout+run.stderr).decode('utf-8',errors='replace')
   print(output)
   return int(run.returncode!=0 or 'ADMIN_FAILURES=0' not in output or 'SCRIPT ERROR' in output or 'ERROR:' in output)
  except subprocess.TimeoutExpired as e:
   print((e.stdout or b'').decode('utf-8',errors='replace'));print((e.stderr or b'').decode('utf-8',errors='replace'));return 1
  finally:httpd.shutdown();httpd.server_close()
if __name__=='__main__':raise SystemExit(main())
