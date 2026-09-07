let ROOM = null, TOKEN = '', COLOR = null, VIEW = null;
let SEL = null, MOVES = [], canFire = false, fireCells = [], fireRange = [], canBarrage = false, barrageCells = [];
let canScan = false, scanCells = [];
let attackMode = null, lastFx = 0, hoverCell = null, feedSeen = 0;
let prevPos = {}, overShown = null, soloReveal = false;
let prevFog = null;   // 직전 렌더의 안개 칸 index Set (null=최초) — 안개 걷힘/덮임 트랜지션용
let prevCanAct = false;   // 직전에 '내가 둘 수 있었나' — 내 차례로 바뀌는 순간 딩 소리용

const boardEl = document.getElementById('board');
function fxOn(){ return localStorage.getItem('fog_fx') !== '0'; }               // 파티클 이펙트 on/off(설정)
const FXMAIN = (window.FxLayer && document.querySelector('.boardWrap'))          // 보드 위 파티클 레이어
  ? new FxLayer(document.querySelector('.boardWrap'), boardEl, {border:4, cols:12}) : null;
window.addEventListener('resize', ()=>{ if(FXMAIN) FXMAIN.resize(); });
let FX_LAST = null;
let PENDING_FX = null;   // /action 응답으로 받은 내 액션의 fx — 다음 폴링(새 그리드)에서 먼저 재생   // 내가 방금 쏜 사격 {type, from:[r,c]} — 탄도선 출발점(상대 사격은 머즐 노출된 기물로 추정)
const PIECE_KR = {K:'킹', Q:'퀸', R:'전차', B:'비숍', N:'나이트', P:'폰'};
const METHOD_ICON = {melee:'⚔️', artillery:'💥', barrage:'🚜'};
function SIDE(c){ return c==='W'?'백':'흑'; }
function pieceSrc(t, o){
  const letter = {K:'k', Q:'q', R:'r', B:'b', N:'n', P:'p'}[t];
  return `/img/Chess_${letter}${o === 'W' ? 'l' : 'd'}t45.svg`;
}

// 사운드(ac()/tone()/noise()/SND)는 sound.js 로 분리됨 — 소리 수정은 그 파일에서.

async function api(path, opts){ return (await fetch(path, opts)).json(); }
function post(path, body){ return api(path, {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body||{})}); }

function nick(){ return (localStorage.getItem('fog_nick')||'').trim(); }  // 게스트 표시 이름(회원이면 서버가 계정 닉네임 사용)
function session(){ return localStorage.getItem('fog_session') || ''; }   // 로그인 세션 토큰(회원이면 레이팅전)
let ME = null;                                                             // 내 프로필 {name, rating, tier, wins, losses, draws}
const TIER_KR = {P:'폰', N:'나이트', R:'룩', B:'비숍', Q:'퀸', K:'킹'};
const TIER_FLOORS = [[1900,'K'],[1700,'Q'],[1500,'B'],[1200,'R'],[1000,'N'],[500,'P']];   // config.RATING_TIERS 와 동일
async function join(){
  const stored = ROOM ? (localStorage.getItem('fog_'+ROOM) || '') : '';
  const r = await post('/join', {room: ROOM, token: stored, name: nick(), session: session()});
  ROOM = r.room; TOKEN = r.token; COLOR = r.color;
  location.hash = '#'+ROOM;
  localStorage.setItem('fog_'+ROOM, TOKEN);
}
async function poll(){
  if(!ROOM) return;                               // 메뉴 화면에선 폴링 안 함
  const r = await api(`/state?room=${ROOM}&token=${TOKEN}&reveal=${soloReveal?1:0}`);
  if(r.gone){ await join(); return; }
  VIEW = r; render();
}

// ---------- 화면 전환(메뉴 ↔ 게임) ----------
const SCREENS = ['home','botMenu','joinMenu','settings'];
function showScreen(id){
  document.getElementById('game').style.display = 'none';
  SCREENS.forEach(s=>{ document.getElementById(s).style.display = (s===id)?'flex':'none'; });
  if(id==='home' && typeof loadHomeLb==='function') loadHomeLb();   // 홈 리더보드 패널 최신화
}
function showGame(){
  SCREENS.forEach(s=>{ document.getElementById(s).style.display = 'none'; });
  document.getElementById('game').style.display = 'flex';
  if(bgmEnabled()) startBgm();          // 게임 화면 진입 시 배경음악(켜져 있으면)
}
function _resetGame(){ clearSel(); prevPos={}; prevFog=null; overShown=null; lastFx=0; PENDING_FX=null; feedSeen=0; }

async function lobbyCreate(){        // 사설 방 생성(친구 초대)
  ROOM = null; TOKEN = '';
  await join();
  _resetGame(); showGame(); poll();
}
async function joinByCode(code){     // 친구 방 코드로 참가
  ROOM = (code||'').trim().toUpperCase(); TOKEN = '';
  await join();
  _resetGame(); showGame(); poll();
}
async function soloStart(){
  const r = await post('/join', {solo:true, name: nick(), session: session()});
  ROOM = r.room; TOKEN = r.token; COLOR = r.color;   // 'solo'
  location.hash = '#'+ROOM; localStorage.setItem('fog_'+ROOM, TOKEN);
  _resetGame(); showGame(); poll();
}
async function botStart(level){
  const r = await post('/join', {vs_bot:true, level, name: nick(), session: session()});
  ROOM = r.room; TOKEN = r.token; COLOR = r.color;   // 'W' (사람=백, 컴퓨터=흑)
  location.hash = '#'+ROOM; localStorage.setItem('fog_'+ROOM, TOKEN);
  _resetGame(); showGame(); poll();
}

// ---------- 테마 · 설정 ----------
function applyTheme(t){
  document.documentElement.dataset.theme = t;
  localStorage.setItem('fog_theme', t);
  const d=document.getElementById('thDark'), l=document.getElementById('thLight');
  if(d) d.classList.toggle('on', t!=='light');
  if(l) l.classList.toggle('on', t==='light');
  const ri=document.getElementById('railThemeIco'); if(ri) ri.textContent = (t==='light') ? '🌙' : '☀️';
}
function themeIsDark(){ const t=document.documentElement.dataset.theme; return t ? t==='dark' : matchMedia('(prefers-color-scheme:dark)').matches; }
let settingsFrom = 'home';                 // 설정을 어디서 열었나(뒤로 갈 곳)
function applyCb(on){                        // 색약 모드: 신호색 팔레트 교체
  if(on) document.documentElement.dataset.cb = 'on';
  else document.documentElement.removeAttribute('data-cb');
  localStorage.setItem('fog_cb', on ? '1' : '0');
  const c = document.getElementById('setCb'); if(c) c.checked = on;
}
function cbOn(){ return document.documentElement.dataset.cb === 'on'; }
function openSettings(from){
  settingsFrom = from || 'home';
  document.getElementById('setSound').checked = soundOn;
  document.getElementById('setBgm').checked = bgmEnabled();
  document.getElementById('setVol').value = Math.round(masterVol()*100);
  document.getElementById('setCb').checked = cbOn();
  document.getElementById('setFxOn').checked = fxOn();
  showScreen('settings');
}
function closeSettings(){                   // 뒤로: 게임 중이면 게임으로, 아니면 홈으로
  if(settingsFrom==='game' && ROOM) showGame();
  else showScreen('home');
}
async function selectPiece(p){
  if(VIEW.phase !== 'play' || VIEW.turn !== VIEW.yourColor) return;
  SEL = p; attackMode = null;
  const r = await api(`/moves?room=${ROOM}&token=${TOKEN}&pid=${p.id}`);
  MOVES = r.moves||[]; canFire = r.canFire; fireCells = r.fireCells||[]; fireRange = r.fireRange||[];
  canBarrage = r.canBarrage; barrageCells = r.barrageCells||[];
  canScan = r.canScan; scanCells = r.scanCells||[];
  render();
}
async function act(body){
  const r = await post('/action', Object.assign({room:ROOM, token:TOKEN}, body));
  if(r.msg) showMsg(r.msg);
  if(r.fx) PENDING_FX = r.fx;                     // 내 액션의 fx(다음 폴링에서 재생)
  return r;
}
function clearSel(){ SEL=null; MOVES=[]; fireCells=[]; fireRange=[]; attackMode=null; hoverCell=null; }
async function doMove(r,c){ await act({type:'move', pid:SEL.id, r, c}); clearSel(); poll(); }
async function doFire(r,c){ FX_LAST={type:'fire', from:[SEL.r,SEL.c]}; const r_=await act({type:'fire', pid:SEL.id, r, c}); if(!r_.ok) FX_LAST=null; clearSel(); poll(); }
async function doBarrage(r,c){ FX_LAST={type:'barrage', from:[SEL.r,SEL.c]}; const r_=await act({type:'barrage', pid:SEL.id, r, c}); if(!r_.ok) FX_LAST=null; clearSel(); poll(); }
async function doScan(r,c){ await act({type:'scan', pid:SEL.id, r, c}); clearSel(); poll(); }
async function placePiece(r,c){ ac(); await act({type:'place', pid:SEL.id, r, c}); if(soundOn) SND.place(); SEL=null; poll(); }
async function setReady(v){ await act({type:'ready', value:v}); poll(); }
async function rematch(){ await act({type:'rematch'}); clearSel(); clearAnnotations(); lastFx=0; PENDING_FX=null; feedSeen=0; prevPos={}; prevFog=null; overShown=null; poll(); }
async function doPromote(t){ await act({type:'promote', choice:t}); document.getElementById('promoModal').style.display='none'; poll(); }
async function doResign(){ if(!confirm('정말 기권할까요? 상대가 승리합니다.')) return; await act({type:'resign'}); clearSel(); poll(); }
async function leaveRoom(){
  if(!confirm('이 방에서 나가 홈으로 갈까요?')) return;
  if(ROOM) localStorage.removeItem('fog_'+ROOM);
  ROOM=null; TOKEN=''; COLOR=null; VIEW=null; location.hash='';
  clearSel(); clearAnnotations(); prevPos={}; prevFog=null; overShown=null; lastFx=0; PENDING_FX=null; feedSeen=0;
  stopBgm();
  showScreen('home');                 // 새 방 만들지 말고 시작 메뉴로 복귀
}
function showMsg(m){ const e=document.getElementById('msg'); e.textContent=m||''; setTimeout(()=>{ if(e.textContent===m) e.textContent=''; }, 2500); }
function inList(l,r,c){ return l.some(([a,b])=>a===r&&b===c); }

// ---------- 사운드 on/off ----------
let soundOn = localStorage.getItem('fog_sound') !== '0';

// ---------- 직관 조작: 드래그로 이동 ----------
let dragState = null;
function boardCellFromEvent(ev){
  const rect = boardEl.getBoundingClientRect();
  const b = 4;                                    // #board 테두리 두께(px)
  const cell = boardEl.clientWidth / 12;          // 한 칸 픽셀
  const c = Math.floor((ev.clientX - rect.left - b) / cell);
  const r = Math.floor((ev.clientY - rect.top  - b) / cell);
  return (r<0||r>11||c<0||c>11) ? null : [r,c];
}
function piecePointerDown(pd, ev){
  if(ev.button!==0) return;                          // 좌클릭만 이동/선택(우클릭은 주석)
  const setup = VIEW.phase==='setup';
  if(!setup && (VIEW.phase!=='play' || VIEW.turn!==VIEW.yourColor)) return;
  ev.preventDefault();
  // 배치: 다른 내 기물이 선택된 채 이 기물을 누르면 → 탭이면 자리 교환, 끌면 이 기물을 잡은 것(선택이 옮겨감)
  const swapFrom = (setup && SEL && SEL.id!==pd.id) ? SEL : null;
  const toggleOff = !!(setup && SEL && SEL.id===pd.id);
  if(setup){ if(!swapFrom){ SEL = pd; render(); } }  // 배치: 선택(교환 대기 중이면 기존 선택 유지)
  else if(!(SEL && SEL.id===pd.id)) selectPiece(pd); // 플레이: 선택(+행마 조회)
  const touch = ev.pointerType === 'touch';
  // 터치: 손가락 떨림 허용치를 키우고(탭이 드래그로 오인되지 않게), 기물을 손가락 위로 띄워 목표 칸이 가려지지 않게
  dragState = { pd, moved:false, x:ev.clientX, y:ev.clientY, clone:null, setup, touch,
                thr: touch ? 12 : 5, lift: touch ? 40 : 0, over:null, swapFrom, toggleOff };
  window.addEventListener('pointermove', piecePointerMove);
  window.addEventListener('pointerup', piecePointerUp);
  window.addEventListener('pointercancel', piecePointerCancel);   // 브라우저가 터치를 가로채면(스크롤·제스처) 정리
}
function dragEnd(){                                  // 드래그 상태·클론·하이라이트 정리
  window.removeEventListener('pointermove', piecePointerMove);
  window.removeEventListener('pointerup', piecePointerUp);
  window.removeEventListener('pointercancel', piecePointerCancel);
  if(dragState && dragState.clone) dragState.clone.remove();
  if(dragState && dragState.over) dragState.over.classList.remove('dragover');
  dragState = null;
}
function piecePointerCancel(){ dragEnd(); }
function dropPoint(ev){                              // 드롭 판정 지점: 터치는 띄운 기물 위치(=손가락 위 lift px)
  return dragState && dragState.lift ? {clientX: ev.clientX, clientY: ev.clientY - dragState.lift} : ev;
}
function dropOk(ds, rc){                             // 이 칸에 놓을 수 있나(배치: 내 진영 빈 땅·부쉬 / 플레이: 합법 이동칸)
  const [r,c] = rc;
  if(ds.setup){
    const [z0,z1] = VIEW.zone||[0,0];
    const t = (VIEW.grid[r] && VIEW.grid[r][c]) ? VIEW.grid[r][c].t : 1;
    return r>=z0 && r<=z1 && (t===0 || t===3);
  }
  return !!(SEL && SEL.id===ds.pd.id && !attackMode && inList(MOVES, r, c));
}
function piecePointerMove(ev){
  if(!dragState) return;
  if(!dragState.moved && Math.hypot(ev.clientX-dragState.x, ev.clientY-dragState.y) < dragState.thr) return;
  dragState.moved = true;
  if(dragState.swapFrom){ SEL = dragState.pd; dragState.swapFrom = null; render(); }   // 교환 대기였지만 끌었다 → 이 기물을 잡은 것
  if(!dragState.clone){                            // 커서/손가락을 따라오는 반투명 클론
    const img = document.createElement('img');
    img.className = 'dragclone' + (dragState.touch ? ' touch' : '');
    img.src = pieceSrc(dragState.pd.t, VIEW.yourColor);
    document.body.appendChild(img);
    dragState.clone = img;
  }
  dragState.clone.style.left = ev.clientX + 'px';
  dragState.clone.style.top  = (ev.clientY - dragState.lift) + 'px';
  const pt = dropPoint(ev), cell = boardCellFromEvent(pt);          // 놓일 칸 미리보기(골드 테두리)
  let el = null;
  if(cell && dropOk(dragState, cell)){
    const hit = document.elementFromPoint(pt.clientX, pt.clientY);   // 클론은 pointer-events:none이라 그 아래 칸이 잡힘
    el = hit && hit.closest ? hit.closest('#board .cell') : null;
  }
  if(el !== dragState.over){
    if(dragState.over) dragState.over.classList.remove('dragover');
    if(el) el.classList.add('dragover');
    dragState.over = el;
  }
}
function piecePointerUp(ev){
  const ds = dragState, pt = dropPoint(ev);
  dragEnd();
  if(!ds) return;
  if(!ds.moved){                                   // 움직임 없음 = 탭/클릭
    if(ds.swapFrom) placePiece(ds.pd.r, ds.pd.c);  // 배치: 선택된 기물과 자리 교환(서버 apply_place가 두 기물 위치를 맞바꿈)
    else if(ds.toggleOff){ SEL = null; render(); } // 배치: 선택된 기물을 다시 탭 → 선택 해제
    return;                                        // 그 외엔 선택 유지
  }
  const cell = boardCellFromEvent(pt); if(!cell || !dropOk(ds, cell)) return;   // 못 놓는 칸이면 제자리(선택 유지)
  const [r,c] = cell;
  if(ds.setup) placePiece(r, c);                   // 배치: 내 진영 빈 땅·부쉬에 놓기 · 내 기물 위면 자리 교환
  else doMove(r, c);                               // 플레이: 합법 이동칸에 놓으면 이동
}

// ---------- 리체스식 우클릭 주석: 화살표(드래그) / 원(제자리) ----------
let annCircles = new Set();   // "r,c"
let annArrows = [];           // [r0,c0,r1,c1]
let annDrag = null;
const ANN_COLOR = '#15781b';
function drawAnnotations(live){
  const svg = document.getElementById('annot'); if(!svg) return;
  const W = boardEl.clientWidth; if(!W) return;
  const cell = W/12;
  svg.setAttribute('width', W); svg.setAttribute('height', W); svg.setAttribute('viewBox', `0 0 ${W} ${W}`);
  const cen = (r,c)=>[c*cell+cell/2, r*cell+cell/2];
  let s = `<defs><marker id="annHead" viewBox="0 0 10 10" refX="6.5" refY="5" markerWidth="4" markerHeight="4" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="${ANN_COLOR}"/></marker></defs>`;
  annCircles.forEach(k=>{ const [r,c]=k.split(',').map(Number); const [x,y]=cen(r,c);
    s += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${(cell*0.46).toFixed(1)}" fill="none" stroke="${ANN_COLOR}" stroke-width="${(cell*0.09).toFixed(1)}" opacity="0.85"/>`; });
  const arrow=(r0,c0,r1,c1,op)=>{
    const [x0,y0]=cen(r0,c0), [x1,y1]=cen(r1,c1);
    const dx=x1-x0, dy=y1-y0, L=Math.hypot(dx,dy); if(L<1) return;
    const sx=x0+dx/L*(cell*0.32), sy=y0+dy/L*(cell*0.32);   // 시작칸에서 살짝 나오게
    const ex=x1-dx/L*(cell*0.28), ey=y1-dy/L*(cell*0.28);   // 끝칸 앞에서 화살촉
    s += `<line x1="${sx.toFixed(1)}" y1="${sy.toFixed(1)}" x2="${ex.toFixed(1)}" y2="${ey.toFixed(1)}" stroke="${ANN_COLOR}" stroke-width="${(cell*0.16).toFixed(1)}" stroke-linecap="round" opacity="${op||0.8}" marker-end="url(#annHead)"/>`;
  };
  annArrows.forEach(a=>arrow(a[0],a[1],a[2],a[3]));
  if(live) arrow(live[0],live[1],live[2],live[3],0.5);
  svg.innerHTML = s;
}
function clearAnnotations(){ if(annCircles.size||annArrows.length){ annCircles.clear(); annArrows.length=0; drawAnnotations(); } }
function annPointerDown(ev){
  if(ev.button===0){ clearAnnotations(); return; }   // 좌클릭 = 주석 지우기
  if(ev.button!==2) return;                           // 우클릭만 주석
  ev.preventDefault();
  const cell = boardCellFromEvent(ev); if(!cell) return;
  annDrag = { r:cell[0], c:cell[1] };
  window.addEventListener('pointermove', annPointerMove);
  window.addEventListener('pointerup', annPointerUp);
  window.addEventListener('pointercancel', annPointerUp);
}
function annPointerMove(ev){
  if(!annDrag) return;
  const cell = boardCellFromEvent(ev);
  const live = (cell && !(cell[0]===annDrag.r && cell[1]===annDrag.c)) ? [annDrag.r,annDrag.c,cell[0],cell[1]] : null;
  drawAnnotations(live);
}
function annPointerUp(ev){
  window.removeEventListener('pointermove', annPointerMove);
  window.removeEventListener('pointerup', annPointerUp);
  window.removeEventListener('pointercancel', annPointerUp);
  const d = annDrag; annDrag = null;
  if(!d || ev.type === 'pointercancel'){ drawAnnotations(); return; }   // 취소면 그리던 것만 지움
  const cell = boardCellFromEvent(ev); if(!cell){ drawAnnotations(); return; }
  if(cell[0]===d.r && cell[1]===d.c){                 // 제자리 = 원 토글
    const k = d.r+','+d.c;
    if(annCircles.has(k)) annCircles.delete(k); else annCircles.add(k);
  } else {                                            // 드래그 = 화살표 토글
    const i = annArrows.findIndex(a=>a[0]===d.r&&a[1]===d.c&&a[2]===cell[0]&&a[3]===cell[1]);
    if(i>=0) annArrows.splice(i,1); else annArrows.push([d.r,d.c,cell[0],cell[1]]);
  }
  drawAnnotations();
}

// ---------- 온보딩: 지금 뭘 해야 하는지 한 줄 ----------
function coachText(me, solo){
  if(COLOR==='spectator') return '👀 관전 중 — 조작할 수 없어요.';
  if(VIEW.phase==='setup') return VIEW.bothJoined
    ? '① 기물을 드래그/클릭해 내 3줄 안에 배치 → ② [준비 완료].'
    : '상대 접속 대기 중 — 위 [🔗 초대 링크]를 친구에게 보내세요.';
  if(VIEW.phase==='over') return '게임 종료 — [↻ 재대결]로 다시 시작할 수 있어요.';
  if(!solo && VIEW.turn!==me) return '⏳ 상대 턴 — 잠시 기다려 주세요.';
  if(SEL) return '초록=이동(드래그하거나 클릭). 비숍·전차는 위 공격 버튼. 취소는 빈 칸/우클릭.';
  return '내 기물을 클릭하거나 드래그해 이동하세요. 어두운 칸은 안개예요.';
}

// ── SVG 지형 생성: 숲(고정 5그루 침엽수) · 부쉬(롤 스타일 뾰족 풀숲) ──
// 색은 기물처럼 2색(잎·목제)+외곽선. 채도 A(올리브빛 차분). 랜덤 없음(숲은 좌우 반전만).
const TPAL = { leaf:'#5f8140', line:'#34512a', wood:'#6f4d2c' };
function _pine(cx,baseY,s){
  const tH=6*s, b=baseY-tH;
  const tri=(w,y0,y1)=>`<polygon points="${cx.toFixed(1)},${(b-y1).toFixed(1)} ${(cx-w).toFixed(1)},${(b-y0).toFixed(1)} ${(cx+w).toFixed(1)},${(b-y0).toFixed(1)}" fill="${TPAL.leaf}" stroke="${TPAL.line}" stroke-width="1" stroke-linejoin="round"/>`;
  return `<rect x="${(cx-1.4*s).toFixed(1)}" y="${(baseY-tH).toFixed(1)}" width="${(2.8*s).toFixed(1)}" height="${(tH+1).toFixed(1)}" fill="${TPAL.line}"/>`
    +`<rect x="${(cx-0.9*s).toFixed(1)}" y="${(baseY-tH).toFixed(1)}" width="${(1.8*s).toFixed(1)}" height="${tH.toFixed(1)}" fill="${TPAL.wood}"/>`
    +tri(6.6*s,1*s,13.5*s)+tri(5.2*s,8*s,20*s)+tri(3.9*s,14.5*s,26*s);
}
const _COMP=[[11,27,.80],[25,28,.82],[4,39,.98],[18,40,1.08],[32,39,.98]]; // 뒤2 + 앞3(바깥은 가장자리까지)
function _forest(flip){ return `<svg viewBox="0 0 36 40">`+_COMP.map(([x,y,s])=>_pine(flip?36-x:x,y,s)).join('')+`</svg>`; }
const FOREST=[_forest(0),_forest(1)];
function forestTile(flip){ return FOREST[flip?1:0]; }
const _bushCache={};
function bushTile(r,c){
  const k=r*12+c; if(_bushCache[k]) return _bushCache[k];
  let n=r*70+c*13+3; const rr=()=>{ n=(n*1103515245+12345)&0x7fffffff; return n/0x7fffffff; };
  let s=`<svg viewBox="0 0 36 36"><ellipse cx="18" cy="30.5" rx="16" ry="5.5" fill="${TPAL.line}"/>`;  // 바닥(cy+ry)=36 → 칸 하단에 정확히 맞춤
  for(let i=0;i<12;i++){ const x=4+i*2.6+(rr()-.5)*1.4, tip=31-(7+Math.floor(rr()*5)), lean=(rr()-.5)*2.4;
    s+=`<polygon points="${(x-1.6).toFixed(1)},32 ${(x+1.6).toFixed(1)},32 ${(x+lean).toFixed(1)},${tip}" fill="${TPAL.leaf}" stroke="${TPAL.line}" stroke-width="0.7" stroke-linejoin="round"/>`; }
  s+=`</svg>`; _bushCache[k]=s; return s;
}

// RPG Maker풍 오토타일: 이웃이 같은 지형이 아닌 방향에만 가장자리를 그린다(강 전용으로 축소)
function terrainEdge(r,c,t){
  const get=(rr,cc)=> (rr<0||rr>11||cc<0||cc>11) ? -1 : VIEW.grid[rr][cc].t;
  const diff=(rr,cc)=> get(rr,cc)!==t;   // 보드 밖(-1)도 '다름' 취급 → 테두리 생김
  const e=[];
  if(t===1){ // 산: 위=밝은 윗면 / 아래=그림자 절벽 / 좌우=측면
    if(diff(r-1,c)) e.push('inset 0 9px 0 -1px rgba(226,205,162,.95)');
    if(diff(r+1,c)) e.push('inset 0 -8px 0 -1px rgba(50,36,22,.62)');
    if(diff(r,c-1)) e.push('inset 8px 0 0 -1px rgba(151,120,82,.5)');
    if(diff(r,c+1)) e.push('inset -8px 0 0 -1px rgba(82,60,38,.5)');
  } else if(t===3){ // 부쉬: 잎 하이라이트(위 밝게, 아래 어둡게)
    if(diff(r-1,c)) e.push('inset 0 7px 0 -1px rgba(182,228,150,.8)');
    if(diff(r+1,c)) e.push('inset 0 -7px 0 -1px rgba(26,52,24,.6)');
    if(diff(r,c-1)) e.push('inset 7px 0 0 -1px rgba(150,200,120,.5)');
    if(diff(r,c+1)) e.push('inset -7px 0 0 -1px rgba(40,80,36,.5)');
  } else { // 강: 물가 포말(밝은 테두리)
    if(diff(r-1,c)) e.push('inset 0 6px 0 -1px rgba(210,242,255,.72)');
    if(diff(r+1,c)) e.push('inset 0 -6px 0 -1px rgba(210,242,255,.5)');
    if(diff(r,c-1)) e.push('inset 6px 0 0 -1px rgba(210,242,255,.6)');
    if(diff(r,c+1)) e.push('inset -6px 0 0 -1px rgba(210,242,255,.6)');
  }
  return e.length ? e.join(',') : 'none';
}

function barrageLine(tr,tc){
  if(!SEL) return [];
  const dr0 = tr-SEL.r, dc0 = tc-SEL.c;
  if((dr0===0)===(dc0===0)) return [];           // 상하좌우 직선만(대각 불가)
  const dr = dr0===0?0:(dr0>0?1:-1), dc = dc0===0?0:(dc0>0?1:-1);
  const out=[];
  for(let d=1; d<=4; d++){                        // 사거리 4
    const r=SEL.r+dr*d, c=SEL.c+dc*d;
    if(r<0||r>11||c<0||c>11) break;
    if(VIEW.grid[r][c].t===1) break;             // 숲에 막힘
    out.push([r,c]);
  }
  return out;
}

function playFx(fx){                                // fx = 서버 fx 객체(폴링 VIEW.fx 또는 액션 응답)
  if(!fx || fx.seq === lastFx) return;
  lastFx = fx.seq;
  const tp = fx.type;
  if(soundOn) (SND[tp]||SND.move)();
  if(fxOn() && FXMAIN){                              // 파티클 레이어(캔버스) — 켜져 있으면 CSS 연출 대신
    const cells = fx.cells || [];
    const from = fxOrigin(tp, cells); FX_LAST = null;
    const found = tp==='scan' ? cells.filter(([r,c])=>{ const p=VIEW.grid[r] && VIEW.grid[r][c] && VIEW.grid[r][c].p; return p && p.o!==VIEW.yourColor; }) : null;
    FXMAIN.play(tp, cells, from, found);
    return;
  }
  if(['capture','kill','fire','barrage'].includes(tp)){
    fx.cells.forEach(([r,c])=>{
      const el = boardEl.children[r*12+c];
      if(!el) return;
      const b = document.createElement('div'); b.className='boom'; el.appendChild(b); setTimeout(()=>b.remove(), 520);
      const sk = document.createElement('div'); sk.className='shock'; el.appendChild(sk); setTimeout(()=>sk.remove(), 580);  // 충격파 링
      if(tp==='fire' || tp==='barrage' || tp==='kill'){
        const fl = document.createElement('div'); fl.className='flash'; el.appendChild(fl); setTimeout(()=>fl.remove(), 320);
      }
      if(tp==='kill'){                                  // 킹 처치: 사방 파편
        for(let i=0;i<10;i++){
          const p = document.createElement('div'); p.className='debris';
          const ang = (Math.PI*2/10)*i;
          p.style.setProperty('--dx', Math.cos(ang).toFixed(3));
          p.style.setProperty('--dy', Math.sin(ang).toFixed(3));
          el.appendChild(p); setTimeout(()=>p.remove(), 680);
        }
      }
    });
    if(tp==='kill'){
      const w = document.querySelector('.boardWrap');
      if(w){ w.classList.add('shake'); setTimeout(()=>w.classList.remove('shake'), 400); }
    }
  }
  if(tp==='scan'){                                   // 스캔: 2×2 보라 플래시
    fx.cells.forEach(([r,c])=>{ const el=boardEl.children[r*12+c]; if(!el) return;
      const fl=document.createElement('div'); fl.className='scanflash'; el.appendChild(fl); setTimeout(()=>fl.remove(),500); });
  }
}

// 사격 이펙트의 출발점: 내가 쏜 거면 FX_LAST, 상대가 쐈으면 머즐 노출로 보이는 적 비숍/전차 중 표적과 맞는 것
function fxOrigin(tp, cells){
  if(!(tp==='fire' || tp==='barrage' || tp==='kill') || !cells.length) return null;
  if(FX_LAST) return FX_LAST.from;
  let want = tp==='fire' ? ['B'] : ['R'];
  if(tp==='kill'){                                                        // 킹 처치: 킬로그의 수단으로 판별(멜리면 탄도선 없음)
    const last = (VIEW.feed||[]).slice(-1)[0];
    if(!last || last.method==='melee') return null;
    want = last.method==='artillery' ? ['B'] : ['R'];
  }
  const to = cells[cells.length-1], me = VIEW.yourColor;
  let best=null, bd=99;
  VIEW.grid.forEach((row,r)=>row.forEach((cell,c)=>{
    const p = cell.p; if(!p || p.o===me || !want.includes(p.t)) return;
    const dr=Math.abs(r-to[0]), dc=Math.abs(c-to[1]);
    const ok = p.t==='B' ? (dr*dr+dc*dc <= 25) : ((dr===0 || dc===0) && Math.max(dr,dc) <= 4);
    const d = Math.max(dr,dc); if(ok && d<bd){ bd=d; best=[r,c]; }
  }));
  return best;
}

// 초대 링크의 기준 주소 — '이 페이지를 연 그 주소'를 그대로 쓴다.
//  · localhost로 열었으면 남에게 못 주니 서버가 준 LAN 주소(shareBase)로 대체.
//  · LAN IP(192.168.x)·터널/배포 URL(https://…)로 열었으면 그 origin 그대로 →
//    같은 와이파이든, cloudflared 터널이든, 배포든 링크가 자동으로 맞는다.
function inviteBase(){
  const h = location.hostname;
  const isLocal = (h==='localhost' || h==='127.0.0.1' || h==='::1' || h==='');
  if(!isLocal && location.origin) return location.origin + '/';
  return (VIEW && VIEW.shareBase) ? VIEW.shareBase : (location.origin + '/');
}
// 미행동(시간초과 자동 넘김) 미터 — 상대가 쌓이면 '내 자동 승리 접근'(금색),
// 내가 쌓이면 '내 패배 접근'(빨강). 연속 maxMisses회면 상대 자동 승리.
function missBar(label, n, max, kind){
  let pips = '';
  for(let i=0;i<max;i++) pips += `<span class="pip${i<n?' on':''}"></span>`;
  const near = (n >= max-1) ? ' near' : '';
  const tail = kind==='win' ? '곧 자동 승리!' : '서두르세요!';
  return `<div class="missbar ${kind}${near}"><span class="ml">⏳ ${label} ${n}/${max} · ${tail}</span><span class="pips">${pips}</span></div>`;
}
function tierOf(rating){ for(const [f,t] of TIER_FLOORS) if(rating>=f) return t; return 'P'; }
function fmtElapsed(s){ if(s==null) return '00:00'; const m=Math.floor(s/60), x=s%60; return (m<10?'0':'')+m+':'+(x<10?'0':'')+x; }
// 플레이어 패널(리체스식): 위=상대, 아래=나. 티어 기물 아바타 · 이름(레이팅) · 잡은 기물(상대 색 아이콘)+우세 · 병력 · 턴 시계(30초)
function renderPlayers(me, solo){
  const oppEl=$('pOpp'), meEl=$('pMe'), g=$('gclock');
  if(!VIEW || COLOR==='spectator'){ oppEl.innerHTML=''; meEl.innerHTML=''; g.textContent=''; return; }
  const opp = me==='W' ? 'B' : 'W', play = VIEW.phase==='play';
  const box = (el, who, name, rating, lost, captured, isMe)=>{
    const active = play && VIEW.turn===who;
    const secs = active ? VIEW.turnSecondsLeft : VIEW.turnSeconds;
    const tier = rating!=null ? tierOf(rating) : null;
    const avatar = tier ? `<img class="ptier" src="${pieceSrc(tier,'W')}" alt="${TIER_KR[tier]}" title="${TIER_KR[tier]}" draggable="false">`
                        : `<span class="ptier em">${isMe?'🙂':'👤'}</span>`;
    const caps = captured.map(t=>`<img src="${pieceSrc(t, who==='W'?'B':'W')}" alt="${t}" title="잡은 ${TIER_KR[t]||t}" draggable="false">`).join('');
    const adv = captured.length - lost.length;
    el.className = 'pbox' + (isMe?' me':'') + (active?' active':'');
    el.innerHTML = avatar
      + `<div class="pinfo"><div class="pname">${escapeHtml(name)}${rating!=null?` <small>${rating}</small>`:''}<span class="pcol">${who==='W'?'백':'흑'}${isMe?' · 나':''}</span></div>`
      + `<div class="pcap">${caps}${adv>0?`<span class="adv">+${adv}</span>`:''}<span class="alive">병력 ${who===me ? VIEW.aliveMe : VIEW.aliveOpp}</span></div></div>`
      + `<div class="pclock ${active ? (secs!=null && secs<=6 ? 'low' : 'active') : 'idle'}">${play && secs!=null ? secs+'s' : (VIEW.phase==='over' ? '—' : '')}</div>`;
  };
  const oppName = solo ? (opp==='W'?'백':'흑') : (VIEW.oppName || '상대');
  const myName  = solo ? (me==='W'?'백':'흑')  : (VIEW.myName  || nick() || '나');
  box(oppEl, opp, oppName, solo ? null : VIEW.oppRating, VIEW.deadOpp||[], VIEW.deadMe||[], false);   // 상대: 잃은=deadOpp, 잡은=deadMe
  box(meEl,  me,  myName,  solo ? null : VIEW.myRating,  VIEW.deadMe||[],  VIEW.deadOpp||[], true);    // 나: 잃은=deadMe, 잡은=deadOpp
  if(VIEW.phase==='setup') g.textContent = (VIEW.secondsLeft!=null && VIEW.bothJoined) ? `⏱ 배치 ${VIEW.secondsLeft}s` : '';
  else g.innerHTML = `<span>⏱ ${fmtElapsed(VIEW.elapsed)}${VIEW.phase==='over'?' · 종료':''}</span><span>${VIEW.turnCount}/${VIEW.turnLimit}턴</span>`;
}
function renderMisses(me, solo){
  const el = document.getElementById('misses');
  if(!el) return;
  if(VIEW.phase!=='play' || solo || !VIEW.misses){ el.innerHTML=''; return; }
  const opp = me==='W' ? 'B' : 'W';
  const mm = VIEW.maxMisses || 3;
  const mine = VIEW.misses[me]||0, oppn = VIEW.misses[opp]||0;
  let html = '';
  if(oppn>0) html += missBar('상대 미행동', oppn, mm, 'win');     // 상대가 안 움직임 → 내가 이김에 접근
  if(mine>0) html += missBar('내 미행동',   mine, mm, 'danger');  // 내가 안 움직임 → 내가 짐에 접근
  el.innerHTML = html;
}
function renderInvite(){
  const box = document.getElementById('invite');
  // 초대 링크는 상대가 아직 안 왔을 때만 크게 노출
  if(VIEW && !VIEW.bothJoined && COLOR!=='spectator'){
    box.style.display = 'block';
    document.getElementById('inviteUrl').value = inviteBase() + '#' + ROOM;
  } else {
    box.style.display = 'none';
  }
}
function renderFeed(){
  const feed = VIEW.feed || [];
  const maxSeq = feed.reduce((m,e)=>Math.max(m,e.seq), feedSeen);
  document.getElementById('feed').innerHTML = feed.slice().reverse().map(e=>{
    const you = e.actor===COLOR, mine = e.victim===COLOR;
    const cls = (you?'kf-you':(mine?'kf-me':'')) + (e.seq>feedSeen?' kf-new':'');
    return `<div class="kf ${cls}">
      <img src="${pieceSrc(e.atype,e.actor)}"><span class="nm">${PIECE_KR[e.atype]}</span>
      <em>${METHOD_ICON[e.method]||'✖'}</em>
      <img src="${pieceSrc(e.vtype,e.victim)}"><span class="nm">${PIECE_KR[e.vtype]}</span></div>`;
  }).join('') || '<div style="color:#6a645c;font-size:12px;padding:4px">아직 없음</div>';
  feedSeen = maxSeq;
}
function renderOverlay(){
  const ov = document.getElementById('overlay');
  if(VIEW.phase !== 'over'){ ov.style.display='none'; ov.innerHTML=''; overShown=null; return; }
  ov.style.display='flex';
  if(overShown === VIEW.winner) return;  // 이미 만들어짐 — 애니메이션/사운드 중복 방지
  overShown = VIEW.winner;
  ov.className='overlay';
  const solo = VIEW.solo || COLOR==='solo';
  let big, sub, snd;
  if(VIEW.winner==='draw'){ big='🤝 무승부'; sub='턴 한도 도달'; snd='drawend'; }
  else if(solo){ big=`🏳 ${VIEW.winner==='W'?'백':'흑'} 승리`; sub='혼자 연습'; snd='victory'; }
  else if(VIEW.winner===VIEW.yourColor){ big='🏆 승리!'; sub='적 왕 처치'; snd='victory'; }
  else { big='💀 패배'; sub='내 왕이 당했다'; snd='defeat'; }
  if(VIEW.ratingDelta){                                  // 레이팅전 정산 결과(서버가 한 번만 계산)
    const d = VIEW.ratingDelta.delta;
    sub += d===0 ? ` · 🏅 레이팅 변동 없음(${VIEW.ratingDelta.rating})` : ` · 🏅 레이팅 ${d>0?'+':''}${d} → ${VIEW.ratingDelta.rating}`;
    fetchMe();                                           // 레일 프로필의 레이팅·티어 갱신
  }
  ov.innerHTML = `<div class="big">${big}</div><div class="sub">${sub}</div>`;
  const b = document.createElement('button'); b.className='big'; b.textContent='↻ 재대결';
  b.onclick = rematch; ov.appendChild(b);
  ac(); if(soundOn) (SND[snd]||function(){})();
  if(fxOn() && FXMAIN){ FXMAIN.resize(); if(snd==='victory') FXMAIN.victory(); else if(snd==='defeat') FXMAIN.defeat(); else FXMAIN.drawend(); }
}

function renderPromo(me, solo){
  const pm = document.getElementById('promoModal');
  const show = VIEW && VIEW.promote && COLOR!=='spectator' && (solo || VIEW.turn===me);
  if(!show){ pm.style.display='none'; return; }
  if(pm.style.display!=='flex'){                 // 새로 뜰 때만 버튼 구성(깜빡임 방지)
    const box=document.getElementById('promoBtns'); box.innerHTML='';
    [['R','전차'],['N','나이트'],['B','비숍']].forEach(([t,name])=>{
      const b=document.createElement('button');
      b.style.cssText='display:flex; flex-direction:column; align-items:center; gap:4px; padding:10px 14px;';
      b.innerHTML=`<img src="${pieceSrc(t, me)}" style="width:42px;height:42px" draggable="false"><span style="font-size:12px">${name}</span>`;
      b.onclick=()=>doPromote(t);
      box.appendChild(b);
    });
  }
  pm.style.display='flex';
}

function render(){
  if(!VIEW) return;
  const me = VIEW.yourColor;                 // 조작 중인 색(솔로는 차례마다 바뀜)
  const solo = VIEW.solo || COLOR==='solo';
  const wi = document.getElementById('whoami');
  if(solo) wi.textContent = `🎯 혼자 연습 · 지금 ${me==='W'?'백':'흑'} 차례`;
  else if(COLOR==='spectator') wi.textContent = '👀 관전자';
  else wi.textContent = `${VIEW.myName||'나'}${VIEW.myRating!=null?` (${VIEW.myRating})`:''} · ${COLOR==='W'?'백(아래)':'흑(위)'}`;
  wi.style.background = solo ? '#4a3a1e' : (COLOR==='W' ? '#22406b' : (COLOR==='B'?'#6b2222':'#333'));
  let rttxt = ROOM ? `방 ${ROOM}` : '';
  if(!solo && COLOR!=='spectator' && VIEW.oppName && (VIEW.bothJoined || VIEW.oppName!=='상대'))
    rttxt += (rttxt?' · ':'') + `vs ${VIEW.oppName}${VIEW.oppRating!=null?` (${VIEW.oppRating})`:''}`;
  if(VIEW.rated) rttxt += ' · 🏅 레이팅전';
  if(VIEW.mapSeed) rttxt += ' · 🗺 맵 #' + VIEW.mapSeed;
  if(VIEW.match) rttxt = '⚔️ 랭크 매칭 · ' + rttxt;
  document.getElementById('roomtag').textContent = rttxt;

  renderInvite();

  renderPlayers(me, solo);                   // 플레이어 패널: 상대/나 · 턴 시계 · 잡은 기물 · 경과 시간
  renderMisses(me, solo);

  let s = '';
  if(VIEW.phase==='setup'){
    if(!VIEW.bothJoined) s = '상대 접속 대기 중… 🔗 초대 링크를 친구에게 보내세요';
    else {
      s = VIEW.ready ? '준비 완료 — 상대 대기' : '👉 기물 배치 후 [준비 완료]';
      s += VIEW.oppReady ? ' · 상대 준비됨 ✔' : ' · 상대 배치 중…';
    }
  } else if(VIEW.phase==='over'){
    s = (VIEW.winner==='draw')?'무승부': solo ? `${VIEW.winner==='W'?'백':'흑'} 승리!` : (VIEW.winner===me?'승리!':'패배');
  } else {
    s = solo ? `🟢 ${me==='W'?'백':'흑'} 차례` : ((VIEW.turn===me) ? '🟢 당신 턴' : '⏳ 상대 턴 대기');
    if(!solo && !VIEW.oppConnected) s += '  · ⚠ 상대 접속 끊김?';
  }
  document.getElementById('status').textContent = s;

  // ── 턴 표시: 배너 + 보드 테두리 + (내 차례 전환 시) 딩 ──
  const banner = document.getElementById('turnBanner');
  boardEl.classList.remove('turn-mine','turn-wait');
  banner.className = 'turnBanner';
  let canAct = false, bt = '';
  if(VIEW.phase==='setup'){
    banner.classList.add('setup'); bt = '⚙ 배치 단계 — 기물을 놓고 [준비 완료]';
  } else if(VIEW.phase==='over'){
    banner.classList.add('over'); bt = '🏁 게임 종료';
  } else if(solo){
    banner.classList.add('mine'); boardEl.classList.add('turn-mine');
    bt = `🎯 지금 ${me==='W'?'백':'흑'} 차례`;
  } else if(VIEW.turn===me){
    banner.classList.add('mine'); boardEl.classList.add('turn-mine');
    bt = '🟢 당신 차례 — 지금 두세요'; canAct = true;
  } else {
    banner.classList.add('wait'); boardEl.classList.add('turn-wait');
    bt = '⏳ 상대 차례 — 대기 중';
  }
  banner.textContent = bt;
  if(canAct && !prevCanAct && soundOn){ ac(); if(SND.yourturn) SND.yourturn(); }  // 상대→나 전환 순간 딩
  prevCanAct = canAct;

  // 컨트롤
  const ctr = document.getElementById('controls'); ctr.innerHTML = '';
  const mkBtn = (txt, fn, cls)=>{ const b=document.createElement('button'); b.textContent=txt; if(cls) b.className=cls; b.onclick=fn; ctr.appendChild(b); return b; };
  if(solo){
    mkBtn(soloReveal ? '👁 안개 걷힘(연습용) ON' : '🌫 안개 걷힘 OFF',
          ()=>{ soloReveal=!soloReveal; poll(); }, soloReveal ? 'on' : '');
  }
  // (컴퓨터 대전·혼자 연습은 시작 메뉴로 분리 — 대기 화면 패널에는 표시하지 않음)
  if(VIEW.phase==='setup' && VIEW.bothJoined && COLOR!=='spectator'){
    mkBtn('↩ 기본 포진', ()=>autoplace('default'));
    mkBtn('🎲 무작위 배치', ()=>autoplace('random'));
    mkBtn(VIEW.ready ? '✔ 준비 완료 (취소하려면 클릭)' : '준비 완료',
          ()=>setReady(!VIEW.ready), VIEW.ready ? 'on' : '');
    const hint = document.createElement('div');
    hint.className='help'; hint.style.marginTop='2px';
    hint.textContent='드래그 또는 클릭→칸 클릭으로 배치 · 내 기물 위에 놓거나 탭하면 자리 교환(⇄)';
    ctr.appendChild(hint);
  }
  if(SEL && VIEW.phase==='play' && VIEW.turn===me){
    if(canFire){
      const b = document.createElement('button');
      b.textContent = attackMode==='fire' ? '🎯 저격 ON — 표적 클릭' : '🎯 비숍 저격 (시야 내 사거리 5)';
      b.className = attackMode==='fire' ? 'fire' : 'attn';   // 미선택이면 펄스로 유도
      b.onclick = ()=>{ ac(); attackMode = attackMode==='fire'?null:'fire'; hoverCell=null; render(); };
      ctr.appendChild(b);
    }
    if(canBarrage){
      const b = document.createElement('button');
      b.textContent = attackMode==='barrage' ? '🚜 돌파 사격 ON — 방향 클릭' : '🚜 돌파 사격 (십자 4칸)';
      b.className = attackMode==='barrage' ? 'tank' : 'attn';
      b.onclick = ()=>{ ac(); attackMode = attackMode==='barrage'?null:'barrage'; hoverCell=null; render(); };
      ctr.appendChild(b);
    }
    if(canScan){
      const b = document.createElement('button');
      b.textContent = attackMode==='scan' ? '🔍 스캔 ON — 지점 클릭' : '🔍 퀸 스캔 (안개 2×2 밝히기)';
      b.className = attackMode==='scan' ? 'scan' : 'attn';
      b.onclick = ()=>{ ac(); attackMode = attackMode==='scan'?null:'scan'; hoverCell=null; render(); };
      ctr.appendChild(b);
    }
    if((canFire||canBarrage||canScan) && !attackMode){
      const ah = document.createElement('div'); ah.className='help'; ah.style.marginTop='2px';
      ah.textContent = canFire
        ? '🎯 이 비숍은 저격 가능 — 위 버튼 누르고 하늘색 표적(보이는 적)을 클릭. 숨은 적은 못 맞힘'
        : canBarrage
        ? '🚜 이 전차는 십자 돌파 사격 가능 — 위 버튼 누르고 하늘색 방향(상하좌우)을 클릭'
        : '🔍 이 퀸은 스캔 가능 — 위 버튼 누르고 보라색 사거리(맨해튼 6)에서 지점 클릭. 그 자리 2×2를 ~2턴 감시(숨은 적 노출). 감시 지역은 상대도 보지만, 퀸 위치는 노출 안 됨';
      ctr.appendChild(ah);
    }
  }

  // 소리 on/off (관전자 제외 항상) + 코치 한 줄
  if(COLOR!=='spectator'){
    mkBtn(soundOn ? '🔊 소리 켜짐' : '🔇 소리 꺼짐',
      ()=>{ soundOn=!soundOn; localStorage.setItem('fog_sound', soundOn?'1':'0'); if(soundOn) ac(); render(); });
  }
  if(COLOR!=='spectator' && VIEW.phase!=='over' && VIEW.bothJoined){
    mkBtn('🏳 기권', doResign, 'fire');
  }
  if(ROOM){ mkBtn('🚪 나가기', leaveRoom); }
  const coach = document.createElement('div'); coach.className='help'; coach.style.marginTop='6px';
  coach.textContent = coachText(me, solo);
  ctr.appendChild(coach);

  document.getElementById('log').innerHTML = VIEW.log.map(x=>'· '+x).join('<br>');
  renderFeed();
  renderOverlay();
  renderPromo(me, solo);

  // 보드
  boardEl.innerHTML = '';
  const canSetup = VIEW.phase==='setup' && COLOR!=='spectator';
  const [z0,z1] = VIEW.zone||[0,0];
  const lastMove = (VIEW.fx && (VIEW.fx.type==='move'||VIEW.fx.type==='capture')) ? VIEW.fx.cells : [];
  const fxset = new Set(lastMove.map(([r,c])=>r*12+c));
  const myTurn = VIEW.phase==='play' && VIEW.turn===me;
  const newPos = {};
  const newFog = new Set();

  for(let r=0;r<12;r++) for(let c=0;c<12;c++){
    const cell = VIEW.grid[r][c];
    const d = document.createElement('div');
    d.className = 'cell ' + ((r+c)%2 ? 'dark':'light');
    if(cell.t===1){ const tv=document.createElement('div'); tv.className='terrain'; tv.innerHTML=forestTile((r+c)%2); d.appendChild(tv); }
    else if(cell.t===2){ d.className += ' river'; d.style.setProperty('--edge', terrainEdge(r, c, 2)); }
    else if(cell.t===3){ const tv=document.createElement('div'); tv.className='terrain bushfront'; tv.innerHTML=bushTile(r, c); d.appendChild(tv); }
    const _idx = r*12+c, _fogged = (cell.f===1);
    if(_fogged){ d.className += ' fog'; newFog.add(_idx); }
    if(prevFog){                                          // 안개 상태 변화 → 부드러운 트랜지션
      if(prevFog.has(_idx) && !_fogged) d.className += ' reveal';   // 걷힘
      else if(!prevFog.has(_idx) && _fogged) d.className += ' refog'; // 덮임
    }
    if(VIEW.scanTiles && inList(VIEW.scanTiles, r, c)){ const sw=document.createElement('div'); sw.className='scanwatch'; d.appendChild(sw); }  // 스캔 감시 타일(파랑)
    if(fxset.has(r*12+c)) d.className += ' lastfx';

    if(cell.p){
      const img = document.createElement('img');
      img.className = 'piece'; img.src = pieceSrc(cell.p.t, cell.p.o); img.draggable = false;
      if(cell.p.o===me && cell.t===3) img.classList.add('concealed');   // 내 기물이 부쉬에 은신 중
      if(cell.p.id){  // 내 기물: 직전 위치에서 미끄러지듯 이동
        newPos[cell.p.id] = [r,c];
        const pv = prevPos[cell.p.id];
        if(pv && (pv[0]!==r || pv[1]!==c)){
          const cw = boardEl.clientWidth/12;               // 실제 칸 크기(모바일 축소 대응)
          const dy=(pv[0]-r)*cw, dx=(pv[1]-c)*cw;
          img.style.transition='none';
          img.style.transform=`translate(${dx}px,${dy}px)`;
          requestAnimationFrame(()=>{ img.style.transition=''; img.style.transform=''; });
        }
      }
      d.appendChild(img);
      const mine = cell.p.o===me && cell.p.id;
      if(mine && VIEW.phase==='play'){
        d.classList.add('selpiece');
        const pd={id:cell.p.id, r, c, t:cell.p.t};
        d.onpointerdown = (ev)=>piecePointerDown(pd, ev);   // 클릭=선택 · 드래그=이동
        if(SEL && SEL.id===cell.p.id) d.classList.add('sel');
      }
      if(mine && VIEW.phase==='setup'){
        d.classList.add('selpiece');
        const pd={id:cell.p.id, r, c, t:cell.p.t};
        d.onpointerdown = (ev)=>piecePointerDown(pd, ev);   // 기물만 복제 드래그(타일 안 딸려옴) · 클릭=선택
        if(SEL && SEL.id===cell.p.id) d.classList.add('sel');
        else if(SEL){ d.classList.add('swapable'); d.title='탭하거나 여기에 놓으면 자리 교환'; }   // 선택 중: 다른 내 기물 = 교환 대상(⇄)
      }
    }

    if(canSetup && r>=z0 && r<=z1 && (cell.t===0 || cell.t===3)){   // 빈 땅·부쉬 배치 가능(숲·강은 불가)
      const rr=r, cc=c;
      if(SEL && !(cell.p && cell.p.o===me)){ d.classList.add('zone'); d.onclick = ()=>placePiece(rr, cc); }   // 빈 칸: 클릭해 놓기(드롭은 pointer 드래그가 처리). 내 기물 칸의 탭/드롭 교환은 piecePointerUp
    }

    if(SEL && myTurn){
      const rr=r, cc=c;
      if(attackMode==='fire'){
        if(inList(fireCells, r, c)){                 // 실제 표적(보이는 적) — 진하게 + 링, 클릭해 저격
          d.classList.add('aim','fireReach','fireTarget');
          d.onmouseenter = ()=>{ hoverCell=[rr,cc]; paintAim(); };
          d.onclick = ()=>doFire(rr, cc);
        } else if(inList(fireRange, r, c)){           // 사거리 원(빈 곳) — 옅게, 여기까지 쏠 수 있음
          d.classList.add('aim','fireRangeArea');
          d.onclick = ()=>showMsg('사거리 안 — 보이는 적만 저격 가능(숨은 적은 못 맞힘)');
        }
      } else if(attackMode==='barrage'){
        if(inList(barrageCells, r, c)){
          d.classList.add('aim','barrageReach');
          d.onmouseenter = ()=>{ hoverCell=[rr,cc]; paintAim(); };
          d.onclick = ()=>doBarrage(rr, cc);
        }
      } else if(attackMode==='scan'){
        if(inList(scanCells, r, c)){
          d.classList.add('aim','scanReach');
          d.onmouseenter = ()=>{ hoverCell=[rr,cc]; paintAim(); };
          d.onclick = ()=>doScan(rr, cc);
        }
      } else if(inList(MOVES, r, c)){
        d.classList.add(cell.p ? 'capture' : 'movable');
        if(!cell.p && cell.t===3){ d.classList.add('search'); d.title='부쉬 수색: 들어가면 숨은 적을 잡는다'; }   // 숨은 적이 있어도 표식은 그대로(정보 누출 없음)
        d.onclick = ()=>doMove(rr, cc);
      }
    }
    // 빈 칸/사거리 밖 클릭 → 선택 취소(내 다른 기물·이동 목표는 제외)
    if(SEL && myTurn && !d.onclick && !(cell.p && cell.p.o===me && cell.p.id)){
      d.onclick = ()=>{ clearSel(); render(); };
    }
    boardEl.appendChild(d);
  }
  prevPos = newPos;
  prevFog = newFog;
  paintAim();
  if(PENDING_FX){ playFx(PENDING_FX); PENDING_FX = null; }   // 내 액션 연출(봇 응수에 덮여도 유지)
  playFx(VIEW.fx);
}

function paintAim(){
  document.querySelectorAll('.splash,.lineHit,.scanArea').forEach(e=>e.classList.remove('splash','lineHit','scanArea'));
  if(!SEL || !hoverCell) return;
  if(attackMode==='fire'){
    const [r,c]=hoverCell; const el=boardEl.children[r*12+c]; if(el) el.classList.add('splash');  // 단일 타일 저격
  } else if(attackMode==='barrage'){
    barrageLine(hoverCell[0], hoverCell[1]).forEach(([r,c])=>{
      const el=boardEl.children[r*12+c]; if(el) el.classList.add('lineHit');
    });
  } else if(attackMode==='scan'){                    // 2×2 스캔 미리보기
    const [r,c]=hoverCell;
    [[0,0],[0,1],[1,0],[1,1]].forEach(([dr,dc])=>{ const rr=r+dr, cc=c+dc;
      if(rr<12&&cc<12){ const el=boardEl.children[rr*12+cc]; if(el) el.classList.add('scanArea'); } });
  }
}

async function autoplace(mode){ await act({type:'autoplace', mode}); SEL=null; poll(); }

// 좌표 라벨 (a~l 열 / 1~12 행) — 한 번만 그린다
function renderCoords(){
  const cols = 'abcdefghijkl';
  const cr = document.getElementById('colLabels');
  const rc = document.getElementById('rowLabels');
  if(cr && !cr.childElementCount){
    for(let c=0;c<12;c++){ const s=document.createElement('span'); s.textContent=cols[c]; cr.appendChild(s); }
  }
  if(rc && !rc.childElementCount){
    for(let r=0;r<12;r++){ const s=document.createElement('span'); s.textContent=(r+1); rc.appendChild(s); }
  }
}

// 홈 랜딩용 장식 보드(정적·비상호작용) — '한 판 진행 중' 스냅샷:
// 백 군대가 전진(나이트 정찰), 안개 가장자리에 적 2기 포착, 위쪽은 안개, 지형 몇 개.
// 규칙 요약 모달(입장 시 1회 자동 + 상단 ❔규칙)
function openHelp(){ document.getElementById('helpModal').style.display='flex'; }
function closeHelp(){ document.getElementById('helpModal').style.display='none'; }

// ---------- 기물 설명 보기(상세 가이드 · 설정에서 염) ----------
const OB_C = 'W';   // 가이드 기물 색(백)
let guideStops = [];   // 데모 애니메이션 정지 함수들

function obMiniGrid(cols, rows, cellPx, decorate){
  const g = document.createElement('div'); g.className = 'obGrid';
  g.style.gridTemplateColumns = `repeat(${cols}, ${cellPx}px)`;
  for(let r=0;r<rows;r++) for(let c=0;c<cols;c++){
    const d = document.createElement('div');
    d.className = 'obCell ' + ((r+c)%2 ? 'dark':'light');
    d.style.width = d.style.height = cellPx+'px';
    d.dataset.rc = r+'_'+c;
    if(decorate) decorate(d, r, c);
    g.appendChild(d);
  }
  return g;
}
// 기물 움직임 데모(미니판): 평소엔 정지 상태로 기물만 표시.
// 마우스를 올리면(모바일은 탭) 그 카드만 재생 — 행마(예시 1~2수, 반복) → 공격(실제로 적을 잡는 장면) 순.
// spec.moves = 예시 이동(상대좌표 1~2개), spec.capture = {mode:'move'|'shot', ...}.
let guideActive = null;   // 동시에 하나만 재생(시선 분산 방지)
function pieceDemo(stage, spec){
  const SZ=7, C=3, CELL=24;
  stage.classList.add('gd');
  const grid = obMiniGrid(SZ, SZ, CELL); grid.classList.add('obDemo','pdemo'); stage.appendChild(grid);
  const cellAt=(r,c)=> (r>=0&&r<SZ&&c>=0&&c<SZ) ? grid.querySelector(`[data-rc="${r}_${c}"]`) : null;
  const p=document.createElement('img'); p.className='demop'; p.src=pieceSrc(spec.t,'W');
  p.style.width=p.style.height=CELL+'px'; grid.appendChild(p);
  const foes=[];   // 적 기물(검은 폰) 풀 — 재사용
  const foeAt=(i)=>{ while(foes.length<=i){ const e=document.createElement('img'); e.className='demoe';
      e.src=pieceSrc('P','B'); e.style.width=e.style.height=CELL+'px'; e.style.display='none'; grid.appendChild(e); foes.push(e); } return foes[i]; };
  const place=(el,r,c)=>{ el.style.transform=`translate(${c*CELL}px, ${r*CELL}px)`; };
  const A=(rc)=>[C+rc[0], C+rc[1]];   // 상대→절대 좌표

  // ---- 프레임 타임라인 ----
  const HOME=[C,C];
  const frames=[{p:HOME}];                                   // [0] 정지(휴식)
  (spec.moves||[]).forEach(mv=>{ const d=A(mv);           // 행마: 예시 칸으로 슬라이드(점 표시) → 제자리
    frames.push({p:d, dot:[d]});
    frames.push({p:HOME});
  });
  // 단계별 프레임: move=이동 포획(공격) / shot=사격(능력: 비숍 저격·전차 돌파) / scan=정찰(능력: 퀸)
  const addPhase=(ph)=>{
    if(!ph) return;
    if(ph.mode==='move'){
      const e=A(ph.enemy);
      frames.push({p:HOME, foes:[e]});                     // 적 등장
      frames.push({p:e, foes:[e], hit:[e]});               // 적 위로 이동(겹침)=잡기
      frames.push({p:e, foes:[]});                         // 적 제거(포획 완료)
      frames.push({p:HOME});                               // 리셋
    } else if(ph.mode==='shot'){
      const es=(ph.enemies||[]).map(A), path=(ph.path||[]).map(A);
      frames.push({p:HOME, foes:es});                          // 적 포착
      frames.push({p:HOME, foes:es, beam:path});               // 조준·발사선
      frames.push({p:HOME, foes:[], hit:es, exposed:true});    // 명중=적 제거 + 내 위치 노출
      frames.push({p:HOME});                                   // 리셋
    } else if(ph.mode==='scan'){
      const area=(ph.area||[]).map(A), hidden=A(ph.hidden);
      frames.push({p:HOME, fog:area});                     // 안개에 가려진 2×2(적 안 보임)
      frames.push({p:HOME, scan:area, foes:[hidden]});     // 스캔 발동 → 숨은 적 발각
      frames.push({p:HOME, scan:area, foes:[hidden]});     // 감시 유지(내 위치 노출 없음)
      frames.push({p:HOME});                               // 리셋
    }
  };
  addPhase(spec.capture);   // 공격: 모든 기물 공통(이동해서 포획)
  addPhase(spec.ability);   // 능력: 비숍·전차·퀸만

  const CLS=['hmv','aim','hit','scan','beam','fog'];
  const apply=(f)=>{
    grid.querySelectorAll('.obCell').forEach(d=>d.classList.remove(...CLS));
    place(p, f.p[0], f.p[1]);
    p.classList.toggle('exposed', !!f.exposed);
    (f.dot ||[]).forEach(rc=>{const el=cellAt(rc[0],rc[1]); if(el)el.classList.add('hmv');});
    (f.beam||[]).forEach(rc=>{const el=cellAt(rc[0],rc[1]); if(el)el.classList.add('beam');});
    (f.hit ||[]).forEach(rc=>{const el=cellAt(rc[0],rc[1]); if(el)el.classList.add('hit');});
    (f.scan||[]).forEach(rc=>{const el=cellAt(rc[0],rc[1]); if(el)el.classList.add('scan');});
    (f.fog ||[]).forEach(rc=>{const el=cellAt(rc[0],rc[1]); if(el)el.classList.add('fog');});
    foes.forEach(e=>e.style.display='none');
    (f.foes||[]).forEach((rc,idx)=>{const e=foeAt(idx); place(e,rc[0],rc[1]); e.style.display='';});
  };
  const rest=()=>apply(frames[0]);
  rest();

  let iv=null, idx=0;
  const stop=()=>{ if(iv){clearInterval(iv); iv=null;} stage.classList.remove('playing');
    if(guideActive===stop) guideActive=null; rest(); };
  const start=()=>{ if(iv) return;
    if(guideActive && guideActive!==stop) guideActive();     // 다른 카드 재생 중이면 정지
    guideActive=stop; stage.classList.add('playing'); apply(frames[0]); idx=1;
    iv=setInterval(()=>{ apply(frames[idx % frames.length]); idx++; }, 850);
  };
  stage.addEventListener('mouseenter', start);
  stage.addEventListener('mouseleave', stop);
  stage.addEventListener('click', start);        // 터치/클릭도 재생(한 번에 하나만)
  return stop;
}
const PIECE_GUIDE = [
  {t:'P', nm:'폰 (Pawn)', move:'앞·좌·우·앞대각 1칸(첫 수는 앞으로 2칸). <b>후퇴 불가</b>.',
   atk:'좌·우·앞대각으로 맞닿은 적을 잡음. 끝 줄 도달 시 <b>승격</b>.',
   moves:[[-2,0],[0,-1]], capture:{mode:'move', enemy:[-1,1]}},
  {t:'N', nm:'나이트 (Knight)', move:'체스와 동일한 L자(2+1). 지형만 없으면 <b>건너뜀</b>.',
   atk:'도착 칸의 적을 잡음. <b>시야 3칸</b>(킹과 같음) — 정찰의 핵심(비숍의 천적).',
   moves:[[-2,1],[1,2]], capture:{mode:'move', enemy:[-2,-1]}},
  {t:'B', nm:'비숍 (Bishop · 저격수)', move:'대각선 최대 2칸.',
   atk:'대각선 이동 경로의 적을 잡음(움직여서 포획).',
   abil:'<b>단일 타일 저격</b>(사거리 5, 시야에 든 적만). 쏘면 <b>내 위치 노출</b>.',
   moves:[[-2,2],[2,-2]], capture:{mode:'move', enemy:[-1,1]},
   ability:{mode:'shot', enemies:[[-3,-3]], path:[[-1,-1],[-2,-2],[-3,-3]]}},
  {t:'R', nm:'전차 (Rook · 룩)', move:'상하좌우 최대 2칸.',
   atk:'상하좌우 이동 경로의 적을 잡음(움직여서 포획).',
   abil:'<b>십자 돌파 사격</b>(4칸 관통, 숲에 막힘). 부쉬 속 적도 수색. 쏘면 <b>노출</b>.',
   moves:[[-2,0],[0,2]], capture:{mode:'move', enemy:[0,-2]},
   ability:{mode:'shot', enemies:[[-2,0],[-3,0]], path:[[-1,0],[-2,0],[-3,0]]}},
  {t:'Q', nm:'퀸 (Queen · 정찰)', move:'8방향 최대 2칸.',
   atk:'이동 경로의 적을 잡음(움직여서 포획).',
   abil:'<b>스캔</b> — 지정한 2×2를 감시해 <b>안개·부쉬에 숨은 적</b>을 발각. <b>내 위치는 노출 안 됨</b>.',
   moves:[[-2,-2],[0,2]], capture:{mode:'move', enemy:[-2,0]},
   ability:{mode:'scan', area:[[-2,1],[-2,2],[-1,1],[-1,2]], hidden:[-2,2]}},
  {t:'K', nm:'킹 (King)', move:'8방향 1칸.',
   atk:'맞닿은 적을 잡음. <b>시야 3칸</b>. 목숨 1 — 지키는 게 최우선, 적 킹 처치 시 <b>승리</b>.',
   moves:[[-1,0],[0,1]], capture:{mode:'move', enemy:[-1,-1]}},
];
function buildGuide(){
  guideStops.forEach(fn=>fn()); guideStops=[]; guideActive=null;
  document.getElementById('gDemos').innerHTML='';                 // 상단 데모 영역은 비움(각 카드에 통합)
  const box = document.getElementById('gPieces'); box.innerHTML='';
  PIECE_GUIDE.forEach(spec=>{
    const card=document.createElement('div'); card.className='gp2';
    const st=document.createElement('div'); st.className='gd';
    const tx=document.createElement('div'); tx.className='gpx';
    tx.innerHTML=`<b>${spec.nm}</b>
      <div class="gpl"><span class="gtag">행마</span><span>${spec.move}</span></div>
      <div class="gpl"><span class="gtag atk">공격</span><span>${spec.atk}</span></div>`
      + (spec.abil ? `<div class="gpl"><span class="gtag abil">능력</span><span>${spec.abil}</span></div>` : '');
    card.append(st, tx); box.appendChild(card);
    guideStops.push(pieceDemo(st, spec));
  });
}
function openGuide(){ buildGuide(); document.getElementById('guide').style.display='flex'; }
function closeGuide(){ guideStops.forEach(fn=>fn()); guideStops=[]; guideActive=null; document.getElementById('guide').style.display='none'; }

document.getElementById('rematch').onclick = rematch;
document.getElementById('helpBtn').onclick = openHelp;
document.getElementById('helpClose').onclick = closeHelp;
document.getElementById('helpModal').onclick = (e)=>{ if(e.target.id==='helpModal') closeHelp(); };
document.getElementById('guideClose').onclick = closeGuide;
document.getElementById('guide').onclick = (e)=>{ if(e.target.id==='guide') closeGuide(); };
boardEl.oncontextmenu = (e)=>e.preventDefault();            // 우클릭 브라우저 메뉴 차단(주석용)
boardEl.addEventListener('pointerdown', annPointerDown);   // 우클릭=주석(화살표/원) · 좌클릭=주석 지우기
document.getElementById('copyBtn').onclick = ()=>{
  const el = document.getElementById('inviteUrl'); el.select();
  navigator.clipboard?.writeText(el.value); showMsg('링크 복사됨!');
};

// ---------- 시작 메뉴 · 설정 배선 ----------
const $ = (id)=>document.getElementById(id);
$('mLobby').onclick    = lobbyCreate;                       // 로비 게임 만들기(사설 방)
$('mJoin').onclick     = ()=>{ showScreen('joinMenu'); $('joinCode').value=''; $('joinCode').focus(); };
$('mBot').onclick      = ()=> showScreen('botMenu');        // 컴퓨터와 대국(난이도 선택)
$('mSolo').onclick     = soloStart;                         // 혼자 연습(핫시트)
$('mSettings').onclick = ()=> openSettings('home');         // 홈에서 연 설정 → 뒤로=홈
$('hlbMore').onclick   = openLeaderboard;                     // 홈 리더보드 → 전체 순위·티어 사다리·규칙 모달
$('setBtn').onclick    = ()=> openSettings('game');         // 게임 중 ⚙설정 → 뒤로=게임
$('lvEasy').onclick    = ()=> botStart('easy');
$('lvNormal').onclick  = ()=> botStart('normal');
$('lvHard').onclick    = ()=> botStart('hard');
$('joinGo').onclick    = ()=> joinByCode($('joinCode').value);
$('joinCode').addEventListener('keydown', (e)=>{ if(e.key==='Enter') joinByCode($('joinCode').value); });
// 뒤로: 메뉴 화면들은 홈으로, 설정만 열었던 곳(홈/게임)으로 복귀
document.querySelectorAll('#botMenu .back, #joinMenu .back').forEach(b=> b.onclick = ()=> showScreen('home'));
document.querySelectorAll('#settings .back').forEach(b=> b.onclick = closeSettings);
// 설정 항목 (기물 설명은 사이드바 [기물 설명]에 있음 → 설정에서는 제거)
$('thDark').onclick    = ()=> applyTheme('dark');
$('thLight').onclick   = ()=> applyTheme('light');
$('setSound').onchange = (e)=>{ soundOn = e.target.checked; localStorage.setItem('fog_sound', soundOn?'1':'0'); if(soundOn){ ac(); SND.place&&SND.place(); } render(); };
$('setBgm').onchange   = (e)=>{ ac(); setBgm(e.target.checked); };   // 배경음악 on/off
$('setVol').oninput    = (e)=>{ setMasterVol((+e.target.value)/100); };
$('setVol').onchange   = ()=>{ if(soundOn){ ac(); SND.place&&SND.place(); } };   // 놓을 때 한 번 미리듣기
$('setCb').onchange    = (e)=>{ applyCb(e.target.checked); render(); };          // 색약 모드
$('setFxOn').onchange  = (e)=>{ localStorage.setItem('fog_fx', e.target.checked?'1':'0'); };   // 파티클 이펙트
$('setFx').onclick     = openFxPreview;                                            // 이펙트 미리보기

// 왼쪽 내비 레일 배선
function setRailActive(which){   // 'play' | 'settings'
  const p=$('railPlay2'), s=$('railSettings');
  if(p) p.classList.toggle('active', which==='play');
  if(s) s.classList.toggle('active', which==='settings');
}
$('railPlay').onclick = $('railPlay2').onclick = ()=>{ setRailActive('play'); if(ROOM) showGame(); else showScreen('home'); };
$('railGuide').onclick    = openGuide;
$('railBoard').onclick    = openLeaderboard;
$('railFeedback').onclick = openFeedback;
$('railSettings').onclick = ()=>{ setRailActive('settings'); openSettings(ROOM ? 'game' : 'home'); };

// ---------- 계정 · 레이팅 (레일 하단 프로필) ----------
// 회원이면 티어 기물 + 닉네임 + 레이팅, 게스트면 로그인 안내. 세션 토큰은 localStorage 'fog_session'.
function renderProfile(){
  if(typeof HLB!=='undefined' && HLB.rows) renderHomeLb();   // 홈 리더보드의 '(나)' 강조·내 순위 갱신
  const ava=$('railAva'), nk=$('railNick'), sub=$('railNickSub');
  if(ME){
    ava.innerHTML = `<img src="${pieceSrc(ME.tier,'W')}" alt="${TIER_KR[ME.tier]}" draggable="false">`;
    nk.textContent = ME.name;
    sub.innerHTML = `<span class="rt">${ME.rating}</span> · ${TIER_KR[ME.tier]}`;
  }else{
    ava.textContent = '🙂'; nk.textContent = nick() || '게스트'; sub.textContent = '로그인 · 회원가입';
  }
}
async function fetchMe(){                       // 세션이 있으면 서버에서 내 프로필(현재 레이팅) 갱신
  if(!session()){ ME=null; renderProfile(); return; }
  try{ const r = await post('/me', {session: session()}); ME = r.ok ? r.user : null; }
  catch(e){ ME = null; }
  if(!ME) localStorage.removeItem('fog_session');   // 만료/무효 세션 정리
  renderProfile();
}
let authMode = 'login';
function openAuth(){
  $('authModal').style.display='flex';
  $('authForm').style.display = ME ? 'none' : '';
  $('authProfile').style.display = ME ? '' : 'none';
  $('authErr').textContent = '';
  if(ME){ renderProfileCard(); profMsg(''); openProfSection(ME.weakPw ? 'pw' : null); }
  else setTimeout(()=>$('authName').focus(), 50);
}
function closeAuth(){ $('authModal').style.display='none'; }
function setAuthMode(m){
  authMode = m;
  const su = m==='signup';
  $('tabLogin').classList.toggle('on', !su); $('tabSignup').classList.toggle('on', su);
  $('authGoIcon').textContent = su ? '🪖' : '🔑';                       // 회원가입=입대(헬멧) / 로그인=열쇠
  $('authGoText').textContent = su ? '회원가입' : '로그인';
  $('authGoSub').textContent = su ? '닉네임과 비밀번호만 있으면 끝 · 레이팅 1000부터 시작' : '닉네임과 비밀번호로 입장';
  $('authGo').classList.toggle('primary', su);
  $('authPw').autocomplete = su ? 'new-password' : 'current-password';
  $('authPw').placeholder = su ? '비밀번호 (8자 이상 · 영문+숫자+특수문자)' : '비밀번호';
  $('pwChecks').style.display = su ? '' : 'none';
  if(su) pwChecks($('pwChecks'), $('authPw').value);
  $('authErr').textContent = '';
}
// 비밀번호 규칙(서버 accounts.password_problem 과 동일): 8~64자, 영문(문자)·숫자·특수문자 각 1개 이상, 공백 없음
const PW_RULE = { len: pw=>pw.length>=8 && pw.length<=64, alpha: pw=>/\p{L}/u.test(pw), digit: pw=>/\d/.test(pw), special: pw=>/[^\p{L}\p{N}\s]/u.test(pw) };
function pwProblem(pw){
  if(!PW_RULE.len(pw)) return '비밀번호는 8~64자입니다.';
  if(/\s/.test(pw)) return '비밀번호에 공백은 쓸 수 없습니다.';
  if(!PW_RULE.alpha(pw)) return '비밀번호에 영문(문자)을 넣어주세요.';
  if(!PW_RULE.digit(pw)) return '비밀번호에 숫자를 넣어주세요.';
  if(!PW_RULE.special(pw)) return '비밀번호에 특수문자(!@#$ 등)를 넣어주세요.';
  return null;
}
function pwChecks(box, pw){ box.querySelectorAll('span[data-k]').forEach(s=>s.classList.toggle('ok', PW_RULE[s.dataset.k](pw||''))); }
// ---------- 프로필 편집: 닉네임 변경 · 비밀번호 변경 ----------
function profMsg(t){ const el=$('profMsg'); el.textContent=t; el.style.display = t ? '' : 'none'; }
function openProfSection(which){                       // 'name' | 'pw' | null
  $('nameForm').style.display = which==='name' ? '' : 'none';
  $('pwForm').style.display   = which==='pw'   ? '' : 'none';
  $('pwNotice').style.display = (ME && ME.weakPw) ? '' : 'none';
  $('nameErr').textContent=''; $('pwErr').textContent='';
  if(which==='name'){ $('newName').value = ME ? ME.name : ''; setTimeout(()=>$('newName').focus(), 50); }
  if(which==='pw'){ ['pwOld','pwNew','pwNew2'].forEach(id=>$(id).value=''); pwChecks($('pwChecks2'), ''); setTimeout(()=>$('pwOld').focus(), 50); }
}
async function saveName(){
  const name=$('newName').value.trim(); $('nameErr').textContent='';
  if(!/^[A-Za-z0-9가-힣_]{2,12}$/.test(name)){ $('nameErr').textContent='닉네임은 2~12자(한글·영문·숫자·_)만 가능합니다.'; return; }
  if(ME && name===ME.name){ openProfSection(null); return; }
  const r = await post('/account/name', {session: session(), name});
  if(!r.ok){ $('nameErr').textContent = r.msg || '실패했습니다.'; return; }
  const weak = !!(ME && ME.weakPw); ME = r.user; ME.weakPw = weak;
  renderProfile(); renderProfileCard(); openProfSection(null); profMsg('✅ 닉네임을 바꿨어요: ' + ME.name);
}
async function savePw(){
  const o=$('pwOld').value, n=$('pwNew').value, n2=$('pwNew2').value; $('pwErr').textContent='';
  const p=pwProblem(n); if(p){ $('pwErr').textContent=p; $('pwNew').focus(); return; }
  if(n!==n2){ $('pwErr').textContent='새 비밀번호 확인이 일치하지 않습니다.'; $('pwNew2').focus(); return; }
  if(o===n){ $('pwErr').textContent='현재 비밀번호와 다르게 정해주세요.'; return; }
  const r = await post('/account/pw', {session: session(), old: o, new: n});
  if(!r.ok){ $('pwErr').textContent = r.msg || '실패했습니다.'; return; }
  if(ME) ME.weakPw = false;
  openProfSection(null); profMsg('✅ 비밀번호를 바꿨어요. 다른 기기의 로그인은 풀렸어요.');
}
function renderProfileCard(){                   // 모달 안 프로필 카드: 티어·레이팅·전적·다음 티어까지
  if(!ME) return;
  $('profTier').src = pieceSrc(ME.tier,'W');
  $('profName').textContent = ME.name;
  $('profRating').textContent = `${ME.rating} · ${TIER_KR[ME.tier]}`;
  $('profRec').textContent = `${ME.wins}승 ${ME.losses}패 ${ME.draws}무`;
  const i = TIER_FLOORS.findIndex(([f,t])=>t===ME.tier);
  const lo = TIER_FLOORS[i][0], next = i>0 ? TIER_FLOORS[i-1] : null;
  if(next){
    const pct = Math.max(0, Math.min(100, (ME.rating-lo)/(next[0]-lo)*100));
    $('profBarFill').style.width = pct+'%';
    $('profNext').textContent = `다음 티어 ${TIER_KR[next[1]]}(${next[0]})까지 ${next[0]-ME.rating}점`;
  }else{ $('profBarFill').style.width='100%'; $('profNext').textContent='최고 티어 🏆'; }
  renderTierLadder(ME.tier, ME.rating);
  $('profRating').textContent = ME.rating + ' · ' + TIER_KR[ME.tier] + ' (' + tierRangeText(ME.tier) + ')';
}
// 티어 사다리: 6단계 기물 아이콘 + 레이팅 구간. 현재=골드 강조 · 지난 티어=흐리게 · 다음 티어=이름 강조
const TIER_ASC = TIER_FLOORS.slice().reverse();          // [[500,'P'],[1000,'N'],...,[1900,'K']] 낮은 순
function tierRangeText(t){
  const i = TIER_ASC.findIndex(([f,x])=>x===t);
  const lo = TIER_ASC[i][0], hi = i < TIER_ASC.length-1 ? TIER_ASC[i+1][0]-1 : null;
  if(i===0) return '~' + hi;                            // 폰: 999 이하
  return hi===null ? lo + '+' : lo + '~' + hi;
}
function renderTierLadder(curTier, rating, box){
  box = box || $('tierLadder'); if(!box) return;
  const ci = curTier ? TIER_ASC.findIndex(([f,x])=>x===curTier) : -1;      // 비로그인(null)이면 강조 없음
  box.innerHTML = TIER_ASC.map(([f,t],i)=>{
    const cls = ci<0 ? 'todo' : (i<ci ? 'done' : (i===ci ? 'cur' : (i===ci+1 ? 'next' : 'todo')));
    return '<div class="tl-step '+cls+'" title="'+TIER_KR[t]+' '+tierRangeText(t)+'">'
      + '<img src="'+pieceSrc(t,'W')+'" alt="'+TIER_KR[t]+'" draggable="false">'
      + '<b>'+TIER_KR[t]+'</b><small>'+tierRangeText(t)+'</small>'
      + (ci>=0 && i===ci ? '<em>현재</em>' : (ci>=0 && i===ci+1 ? '<em>다음</em>' : '')) + '</div>';
  }).join('');
}
async function authSubmit(){
  const name=$('authName').value.trim(), pw=$('authPw').value;
  $('authErr').textContent='';
  if(!name){ $('authErr').textContent='닉네임을 입력하세요.'; $('authName').focus(); return; }
  if(authMode==='signup'){ const p=pwProblem(pw); if(p){ $('authErr').textContent=p; $('authPw').focus(); return; } }
  else if(!pw){ $('authErr').textContent='비밀번호를 입력하세요.'; $('authPw').focus(); return; }
  const r = await post(authMode==='login' ? '/login' : '/signup', {name, pw});
  if(!r.ok){ $('authErr').textContent = r.msg || '실패했습니다.'; return; }
  localStorage.setItem('fog_session', r.session); ME = r.user; ME.weakPw = !!r.weakPw;
  $('authPw').value='';
  renderProfile();
  if(ME.weakPw) openAuth();                       // 옛 4자리 비밀번호 → 프로필의 비밀번호 변경 폼을 바로 열어 안내
  else closeAuth();
}
async function authLogout(){
  await post('/logout', {session: session()});
  localStorage.removeItem('fog_session'); ME=null; renderProfile(); closeAuth();
}
// ---------- 리더보드(레이팅 순위) ----------
function escapeHtml(s){ return String(s).replace(/[&<>"']/g, ch=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch])); }
async function openLeaderboard(){
  const m=$('lbModal'), body=$('lbBody');
  m.style.display='flex'; body.innerHTML='<p class="note">불러오는 중…</p>';
  let rows=[], rules=null;
  try{ const d=await api('/leaderboard'); rows=d.rows||[]; rules=d.rules||null; }catch(e){ body.innerHTML='<p class="note">불러오지 못했어요.</p>'; return; }
  renderTierLadder(ME ? ME.tier : null, ME ? ME.rating : 0, $('lbLadder'));   // 티어 사다리(로그인 시 내 위치 강조)
  $('lbLadderSub').textContent = ME ? ('내 티어: ' + TIER_KR[ME.tier] + ' · ' + ME.rating) : '레이팅 구간 · 로그인하면 내 위치 표시';
  if(rules) renderRatingRules(rules);
  if(!rows.length){ body.innerHTML='<p class="note">아직 아무도 없어요 — 첫 회원이 되어 보세요!</p>'; return; }
  const me = ME ? ME.name : null;
  body.innerHTML = '<table class="lbTable"><thead><tr><th>#</th><th></th><th>닉네임</th><th>레이팅</th><th>전적</th></tr></thead><tbody>'
    + rows.map(u=>'<tr class="'+(u.name===me?'me':'')+'"><td>'+u.rank+'</td>'
      + '<td><img src="'+pieceSrc(u.tier,'W')+'" alt="'+TIER_KR[u.tier]+'" title="'+TIER_KR[u.tier]+'" draggable="false"></td>'
      + '<td>'+escapeHtml(u.name)+(u.name===me?' <small>(나)</small>':'')+'</td><td><b>'+u.rating+'</b></td>'
      + '<td>'+u.wins+'승 '+u.losses+'패 '+u.draws+'무</td></tr>').join('')
    + '</tbody></table>';
}
function closeLeaderboard(){ $('lbModal').style.display='none'; }
// ---------- 메인 화면 리더보드 패널(상위 10명 · 내 순위) ----------
const HLB_TOP = 10;
let HLB = { rows: null, total: 0, loading: false, ok: true };
async function loadHomeLb(){                                    // 홈에 올 때마다 새로 받아 레이팅 변동을 바로 반영
  if(HLB.loading) return;
  HLB.loading = true;
  try{ const d = await api('/leaderboard'); HLB.rows = d.rows || []; HLB.total = d.total || HLB.rows.length; HLB.ok = true; }
  catch(e){ HLB.ok = false; }
  HLB.loading = false;
  renderHomeLb();
}
function renderHomeLb(){
  const list=$('hlbList'), meBox=$('hlbMe'), sub=$('hlbSub'); if(!list) return;
  if(!HLB.ok || !HLB.rows){ list.innerHTML='<div class="hlb-empty">리더보드를 불러오지 못했어요.</div>'; meBox.textContent=''; return; }
  const rows=HLB.rows, me=ME ? ME.name : null, medal=['🥇','🥈','🥉'];
  if(!rows.length){
    list.innerHTML='<div class="hlb-empty">아직 아무도 없어요.<br>첫 회원이 되어 1위를 차지해 보세요!</div>';
    sub.textContent='레이팅 순'; meBox.innerHTML = me ? '' : '로그인하면 순위에 오를 수 있어요'; return;
  }
  sub.textContent = '상위 '+Math.min(HLB_TOP, rows.length)+'명 · 전체 회원 '+HLB.total+'명';
  list.innerHTML = rows.slice(0, HLB_TOP).map((u,i)=>
    '<div class="hlb-row'+(u.name===me?' me':'')+(i<3?' top':'')+'">'
    + '<span class="hlb-rank">'+(i<3 ? medal[i] : u.rank)+'</span>'
    + '<img class="hlb-tier" src="'+pieceSrc(u.tier,'W')+'" alt="'+TIER_KR[u.tier]+'" title="'+TIER_KR[u.tier]+'" draggable="false">'
    + '<span class="hlb-name">'+escapeHtml(u.name)+(u.name===me?' <small>(나)</small>':'')+'</span>'
    + '<span class="hlb-rec">'+u.wins+'승 '+u.losses+'패</span>'
    + '<span class="hlb-rating">'+u.rating+'</span></div>').join('');
  if(!me){ meBox.innerHTML = '로그인하면 내 순위가 여기에 표시돼요'; return; }
  const mine = rows.find(u=>u.name===me);
  meBox.innerHTML = mine ? ('내 순위 <b>'+mine.rank+'위</b> · '+TIER_KR[mine.tier]+' · <b>'+mine.rating+'</b>')
                         : ('내 순위 <b>'+rows.length+'위 밖</b> · '+TIER_KR[ME.tier]+' · <b>'+ME.rating+'</b>');
}
// 레이팅 규칙(서버 config 값으로 계산해 그림 — 실제 정산 공식과 항상 동일)
function renderRatingRules(r){
  const exp=(a,b)=>1/(1+Math.pow(10,(b-a)/400));
  const d=(a,b,s)=>{ const v=Math.round(r.k*(s-exp(a,b))); return (v>0?'+':'')+v; };
  const base=r.default, row=(label,opp)=>'<tr><td>'+label+'</td><td class="up">'+d(base,opp,1)+'</td><td class="dn">'+d(base,opp,0)+'</td><td>'+d(base,opp,0.5)+'</td></tr>';
  const capTxt = r.botCap!=null ? (' 단, 난이도마다 <b>컴퓨터 레이팅 +'+r.botCap+'</b>까지만 올라요(쉬움 '+(r.bot.easy+r.botCap)+' · 보통 '+(r.bot.normal+r.botCap)+' · 어려움 '+(r.bot.hard+r.botCap)+'). 그 위로는 랭크 매칭으로.') : '';
  const bot = r.botRated ? ('<li><b>컴퓨터 대국</b>: 이기면 오르고' + (r.botNoLoss ? ' <b>져도 내려가지 않음</b>' : ' 지면 내려감') + ' — 컴퓨터는 고정 레이팅(쉬움 '+r.bot.easy+' · 보통 '+r.bot.normal+' · 어려움 '+r.bot.hard+').' + capTxt + '</li>')
                         : '<li>컴퓨터 대국은 레이팅에 반영되지 않음</li>';
  $('lbRulesBody').innerHTML =
    '<ul>'
    + '<li>시작 <b>'+base+'점</b>, 바닥 <b>'+r.floor+'점</b>. 티어는 레이팅 구간으로 자동(위 사다리).</li>'
    + '<li>변동 = <b>'+r.k+' × (결과 − 기대승률)</b>. 기대승률은 <b>상대와의 점수차</b>로 정해져요(400점 차 = 10배). '
    + '약한 상대를 이기면 조금, 강한 상대를 이기면 많이 얻고, 질 때는 반대.</li>'
    + '</ul>'
    + '<table><thead><tr><th>'+base+'점인 내가…</th><th>이기면</th><th>지면</th><th>비기면</th></tr></thead><tbody>'
    + row('같은 '+base+'점 상대', base) + row('300점 높은 상대('+(base+300)+')', base+300) + row('300점 낮은 상대('+(base-300)+')', base-300)
    + '</tbody></table>'
    + '<ul>'
    + '<li><b>레이팅전</b>: 랭크 매칭(로그인 회원끼리 자동 매칭)' + bot
    + '<li>로비(친구) 대전·혼자 연습·게스트 대국은 반영되지 않음 — 친구와는 부담 없이!</li>'
    + '<li><b>기권</b>, 접속 끊김 90초, 연속 3회 미행동은 <b>패배</b>로 정산. 정산은 게임이 끝날 때 한 번.</li>'
    + '</ul>';
}
$('lbClose').onclick = closeLeaderboard;
$('lbModal').onclick = (e)=>{ if(e.target.id==='lbModal') closeLeaderboard(); };
// ---------- 이펙트 미리보기(설정 → 🎬) : 8×8 미니 보드 위에서 연출 재생 ----------
let FXPREV = null;
function openFxPreview(){
  const m=$('fxModal'), stage=$('fxStage'), btns=$('fxBtns');
  m.style.display='flex';
  if(!FXPREV && window.FxLayer){
    const grid = obMiniGrid(8, 8, 36); grid.classList.add('obDemo'); stage.appendChild(grid);
    FXPREV = new FxLayer(stage, grid, {border:2, cols:8});
    const demos = [
      ['포획',    'capture', ()=>FXPREV.play('capture', [[3,4]])],
      ['저격',    'fire',    ()=>FXPREV.play('fire', [[1,6]], [6,1])],
      ['돌파',    'barrage', ()=>FXPREV.play('barrage', [[4,3],[4,4],[4,5],[4,6]], [4,2])],
      ['스캔',    'scan',    ()=>FXPREV.play('scan', [[2,4],[2,5],[3,4],[3,5]], null, [[2,5]])],
      ['킹 처치', 'kill',    ()=>FXPREV.play('kill', [[3,4]], [7,0])],
      ['승리',    'victory', ()=>FXPREV.victory()],
      ['패배',    'defeat',  ()=>FXPREV.defeat()],
      ['무승부',  'drawend', ()=>FXPREV.drawend()],
    ];
    demos.forEach(([label, snd, fn])=>{
      const b=document.createElement('button'); b.className='seg-b'; b.textContent=label;
      b.onclick=()=>{ FXPREV.resize(); fn(); if(soundOn){ ac(); (SND[snd]||function(){})(); } };
      btns.appendChild(b);
    });
  }
  if(FXPREV) FXPREV.resize();
}
function closeFxPreview(){ $('fxModal').style.display='none'; if(FXPREV) FXPREV.clear(); }
$('fxClose').onclick = closeFxPreview;
$('fxModal').onclick = (e)=>{ if(e.target.id==='fxModal') closeFxPreview(); };
// ---------- 개발자 피드백(레일 💬) ----------
function openFeedback(){
  $('fbModal').style.display='flex'; $('fbForm').style.display=''; $('fbDone').style.display='none';
  $('fbErr').textContent=''; setTimeout(()=>$('fbText').focus(), 50);
}
function closeFeedback(){ $('fbModal').style.display='none'; }
async function sendFeedback(){
  const message=$('fbText').value.trim(), category=$('fbCat').value;
  $('fbErr').textContent='';
  if(message.length<3){ $('fbErr').textContent='내용을 조금 더 적어주세요(3자 이상).'; $('fbText').focus(); return; }
  $('fbSend').disabled=true;
  let r;
  try{ r = await post('/feedback', {category, message, session: session(), name: nick(), room: ROOM||'', ua: navigator.userAgent.slice(0,200)}); }
  catch(e){ r = {ok:false, msg:'보내지 못했어요. 잠시 후 다시 시도해 주세요.'}; }
  $('fbSend').disabled=false;
  if(!r.ok){ $('fbErr').textContent = r.msg || '보내지 못했어요.'; return; }
  $('fbText').value=''; $('fbCount').textContent='0 / 1000';
  $('fbForm').style.display='none'; $('fbDone').style.display='';
  setTimeout(closeFeedback, 1800);
}
$('fbClose').onclick = closeFeedback;
$('fbModal').onclick = (e)=>{ if(e.target.id==='fbModal') closeFeedback(); };
$('fbSend').onclick = sendFeedback;
$('fbText').addEventListener('input', e=>{ $('fbCount').textContent = e.target.value.length + ' / 1000'; });
// ---------- 랭크 매칭(메인 카드) : 로그인 회원끼리 레이팅 근접 자동 대전 ----------
let matchTimer = null;
async function matchStart(){
  if(!ME){ openAuth(); $('authErr').textContent = '랭크 매칭은 로그인 후 이용할 수 있어요.'; return; }
  let r; try{ r = await post('/match/join', {session: session()}); }catch(e){ r = {ok:false}; }
  if(!r || !r.ok){ showMsg((r && r.msg) || '매칭을 시작하지 못했어요.'); return; }
  $('matchModal').style.display='flex'; $('matchFound').style.display='none'; $('matchBot').style.display='none';
  $('matchAccept').style.display='none'; $('matchCancel').style.display=''; matchFoundShown=false;
  $('matchSpin').style.display=''; $('matchTitle').textContent='⚔️ 상대를 찾는 중…';
  $('matchMe').textContent = ME.name + ' · ' + ME.rating + ' (' + TIER_KR[ME.tier] + ')';
  clearInterval(matchTimer); matchTimer = setInterval(matchPoll, 1000);
  matchHandle(r);                      // 상대가 이미 기다리고 있었으면 join 응답에 바로 '매칭 성사'가 실려 온다 → 즉시 입장
}
let matchFoundShown = false;             // 수락 창을 띄웠나(알림음 1회 · 다시 대기로 돌아가면 안내)
function matchShowFound(r){              // 짝이 잡힘 → A(레이팅) vs B(레이팅) 수락 창
  $('matchSpin').style.display='none'; $('matchCancel').style.display='none'; $('matchBot').style.display='none';
  $('matchTitle').textContent='⚔️ 상대를 찾았어요!';
  $('matchAccept').style.display='';
  const mt = tierOf(ME.rating), ot = tierOf(r.opp.rating);
  $('vsMeImg').src = pieceSrc(mt,'W'); $('vsMeName').textContent = ME.name; $('vsMeSub').textContent = ME.rating + ' · ' + TIER_KR[mt];
  $('vsOppImg').src = pieceSrc(ot,'W'); $('vsOppName').textContent = r.opp.name; $('vsOppSub').textContent = r.opp.rating + ' · ' + TIER_KR[ot];
  $('matchAcceptBtn').disabled = !!r.accepted;
  $('matchAcceptBtn').querySelector('b').textContent = r.accepted ? '수락함' : '수락';
  $('acceptInfo').textContent = r.accepted ? ('상대 수락 대기 중… ' + r.secondsLeft + '초' + (r.oppAccepted ? ' · 상대 수락!' : ''))
                                           : (r.secondsLeft + '초 안에 수락하세요' + (r.oppAccepted ? ' · 상대는 수락했어요' : ''));
  if(!matchFoundShown){ matchFoundShown=true; if(soundOn){ ac(); (SND.yourturn||function(){})(); } }
}
function matchShowWaiting(){             // 수락 창에서 다시 대기로(상대 거절/미응답)
  $('matchAccept').style.display='none'; $('matchSpin').style.display=''; $('matchCancel').style.display='';
  $('matchTitle').textContent='⚔️ 상대를 찾는 중…';
  if(matchFoundShown){ matchFoundShown=false; showMsg('상대가 응답하지 않아 다시 찾는 중이에요.'); }
}
function matchRender(r){
  if(r.state!=='waiting') return;
  if($('matchAccept').style.display!=='none') matchShowWaiting();
  const w = (r.window==null) ? '무제한' : ('±' + r.window);
  $('matchInfo').textContent = '대기 ' + r.waited + '초 · 검색 범위 ' + w + ' · 대기열 ' + r.queue + '명';
  if(r.waited >= 30) $('matchBot').style.display='';           // 30초 넘게 아무도 없으면 봇 제안
}
let matchRejoinAt = 0;                   // 대기열에서 빠졌다는 응답(idle)에 자동 재등록한 시각(무한 반복 방지)
async function matchPoll(){
  let r; try{ r = await post('/match/status', {session: session()}); }catch(e){ return; }
  matchHandle(r);
}
function matchHandle(r){
  if(!r || !r.ok || !matchTimer) return;   // 모달을 닫았거나(취소) 이미 입장했으면 무시
  if(r.state==='matched'){
    clearInterval(matchTimer); matchTimer = null;
    $('matchSpin').style.display='none'; $('matchTitle').textContent='⚔️ 매칭 성사!';
    $('matchFound').style.display=''; $('matchOpp').textContent = r.opp.name + ' (' + r.opp.rating + ')';
    if(soundOn){ ac(); (SND.yourturn||function(){})(); }
    setTimeout(()=>{
      ROOM = r.room; TOKEN = r.token; COLOR = r.color;
      location.hash = '#' + ROOM; localStorage.setItem('fog_' + ROOM, TOKEN);
      _resetGame(); $('matchModal').style.display='none'; showGame(); poll();
      post('/match/cancel', {session: session()}).catch(()=>{});   // 입장 완료 → 대기열의 결과 항목 정리(ack). 안 하면 30초 안 재매칭 시 같은 방으로 안내됨
    }, 1200);
    return;
  }
  if(r.state==='found'){ matchShowFound(r); return; }
  if(r.state==='idle'){                    // 대기열에서 빠짐(탭이 잠들어 폴링이 끊긴 경우 등) → 조용히 다시 등록
    if(Date.now() - matchRejoinAt > 5000){
      matchRejoinAt = Date.now();
      post('/match/join', {session: session()}).then(matchHandle).catch(()=>{});
    }else{ matchStop(false); showMsg('매칭 대기가 종료됐어요. 다시 시도해 주세요.'); }
    return;
  }
  matchRender(r);
}
async function matchStop(tell){
  clearInterval(matchTimer); matchTimer = null;
  $('matchModal').style.display='none';
  if(tell !== false){ try{ await post('/match/cancel', {session: session()}); }catch(e){} }
}
$('mMatch').onclick = matchStart;
$('matchCancel').onclick = ()=>matchStop(true);
$('matchAcceptBtn').onclick = async ()=>{ $('matchAcceptBtn').disabled = true; try{ matchHandle(await post('/match/accept', {session: session()})); }catch(e){} };
$('matchDeclineBtn').onclick = async ()=>{ await matchStop(false); try{ await post('/match/decline', {session: session()}); }catch(e){} showMsg('매칭을 거절했어요.'); };
$('matchBot').onclick = async ()=>{ await matchStop(true); showScreen('botMenu'); };
$('railUser').onclick = openAuth;
$('authClose').onclick = closeAuth;
$('authModal').onclick = (e)=>{ if(e.target.id==='authModal') closeAuth(); };
$('tabLogin').onclick = ()=>setAuthMode('login');
$('tabSignup').onclick = ()=>setAuthMode('signup');
$('authGo').onclick = authSubmit;
$('authLogout').onclick = authLogout;
['authName','authPw'].forEach(id=>$(id).addEventListener('keydown', e=>{ if(e.key==='Enter') authSubmit(); }));
$('authPw').addEventListener('input', e=>{ if(authMode==='signup') pwChecks($('pwChecks'), e.target.value); });   // 회원가입: 규칙 칩 실시간
$('btnName').onclick = ()=>openProfSection($('nameForm').style.display==='none' ? 'name' : null);
$('btnPw').onclick   = ()=>openProfSection($('pwForm').style.display==='none' ? 'pw' : null);
$('nameCancel').onclick = $('pwCancel').onclick = ()=>openProfSection(null);
$('nameSave').onclick = saveName; $('pwSave').onclick = savePw;
$('newName').addEventListener('keydown', e=>{ if(e.key==='Enter') saveName(); });
['pwOld','pwNew','pwNew2'].forEach(id=>$(id).addEventListener('keydown', e=>{ if(e.key==='Enter') savePw(); }));
$('pwNew').addEventListener('input', e=>pwChecks($('pwChecks2'), e.target.value));
renderProfile(); setRailActive('play');

// Material 리플(탭 파문) — 버튼·메뉴 카드·세그먼트에 파문 효과
document.addEventListener('pointerdown', (e)=>{
  const el = e.target.closest('button, .menu-btn');
  if(!el || el.disabled) return;
  const r = el.getBoundingClientRect(), s = Math.max(r.width, r.height);
  const rip = document.createElement('span'); rip.className = 'rip';
  rip.style.width = rip.style.height = s + 'px';
  rip.style.left = (e.clientX - r.left - s/2) + 'px';
  rip.style.top  = (e.clientY - r.top  - s/2) + 'px';
  el.appendChild(rip); setTimeout(()=> rip.remove(), 500);
});

(async function main(){
  applyTheme(localStorage.getItem('fog_theme') || 'dark');
  applyCb(localStorage.getItem('fog_cb') === '1');
  fetchMe();                                                // 로그인 세션이 있으면 레일 프로필(레이팅·티어) 표시
  api('/version').then(v=>{ if(v && v.version) $('verBadge').textContent = 'WW1 Fog Chess · v' + v.version; }).catch(()=>{});
  renderCoords();
  setInterval(poll, 900);
  const hash = (location.hash || '').replace('#','');
  if(hash){                                                 // 초대 링크로 들어온 경우 → 바로 그 방
    ROOM = hash;
    await join(); showGame(); await poll();
  }else{                                                    // 그 외 → 시작 메뉴
    showScreen('home');
  }
  // 첫 방문이면 '규칙 요약' 카드 하나만 자동으로(팝업은 최대 1개). 기물 상세는 설정 → 기물 설명 보기.
  if(!localStorage.getItem('fog_help_seen')){ openHelp(); localStorage.setItem('fog_help_seen','1'); }
})();
