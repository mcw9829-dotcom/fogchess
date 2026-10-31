"""HTTP boundary for operations; auth before parsing or returning private data."""
from urllib.parse import parse_qs
import time
import accounts
import admin_ops as ops
import replays


class OperationsMixin:
    def _ops_actor(self):
        return ops.actor(self.headers.get('X-Admin-Session',''))

    def _ops_get(self,url):
        if not self._admin():return
        q=parse_qs(url.query)
        arg=lambda name,default='':q.get(name,[default])[0]
        try:
            offset=int(arg('offset','0'))
            if not 0<=offset<=1000000:raise ops.Problem('페이지 범위를 확인해 주세요.')
            path=url.path.removeprefix('/admin/ops/')
            if path=='overview':
                import server
                with server.lock:result=ops.overview(server.ROOMS,server.matchmaking.QUEUE)
            elif path=='users':result=ops.list_users(ops.text(arg('q'),'검색',80,0),offset)
            elif path=='user':result=ops.user_detail(int(arg('id')))
            elif path=='tickets':result=ops.tickets(ops.text(arg('q'),'검색',80,0),arg('kind'),offset)
            elif path=='games':
                result=ops.game_rows(offset)
                if offset==0:
                    known={r.get('replay_id') for r in result['rows']}
                    result['legacy']=replays.admin_recent(known)
            elif path=='game':result=ops.game_detail(arg('id'))
            elif path=='replay':
                data=replays.admin_payload(arg('id'))
                if not data:raise ops.Problem('종료된 기보를 찾을 수 없습니다.',404)
                result={'ok':True,'replay':data[0]}
            elif path=='notices':result=ops.notices()
            elif path=='audit':result=ops.audit(offset)
            elif path=='balance':result=ops.balance(arg('kind','match'),arg('band','all'),arg('days','7'))
            else:raise ops.Problem('없는 관리 기능입니다.',404)
            self._json(result)
        except (ops.Problem,ValueError,TypeError) as exc:
            self._json({'ok':False,'msg':str(exc) if isinstance(exc,ops.Problem) else '조회 값을 확인해 주세요.'},getattr(exc,'status',400))

    def _prune_restricted_queue(self,now):
        import server
        paused=ops.maintenance()['paused']
        for token,entry in list(server.matchmaking.QUEUE.items()):
            user=accounts.user_by_token(token)
            if not entry.get('matched') and (not user or user['id']!=entry['uid'] or paused or ops.block_reason(entry['uid'],'match')):
                server.matchmaking.cancel(token,now)

    def _ops_post(self,url,data):
        if not self._admin():return
        import server
        action=url.path.removeprefix('/admin/ops/')
        try:
            with server.lock:
                response=ops.mutate(action,data,self._ops_actor())
                self._prune_restricted_queue(time.time())
                for room in server.ROOMS.values():
                    for side,uid in room.get('users',{}).items():
                        u=accounts.user_by_id(uid)
                        if u:room['ratings'][side]=u['rating']
                    if room['state'].get('_settlement_id')==data.get('id') and response.get('result') is not None:
                        room['rating_result']=response['result'];room['rated_done']=True
                self._json(response)
        except ops.Problem as exc:self._json({'ok':False,'msg':str(exc)},exc.status)

    def _support(self,path,data):
        try:
            if path=='/support/login':
                result,error=accounts.login(data.get('name'),data.get('pw'),support=True)
                self._json({'ok':bool(result),'msg':error,**(result or {})})
                return
            user=accounts.user_by_token(data.get('session'),support=True)
            if path=='/support/mine':result=ops.support_mine(user)
            elif path=='/support/context':result=ops.support_context(user,data)
            elif path=='/support/submit':result=ops.support_submit(user,data)
            else:
                if user:ops.touch(user['id'])
                result={'ok':bool(user)}
            self._json(result)
        except ops.Problem as exc:self._json({'ok':False,'msg':str(exc)},exc.status)
