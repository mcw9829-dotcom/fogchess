let ROOM = null, TOKEN = '', COLOR = null, VIEW = null;
let SEL = null, MOVES = [], canFire = false, fireCells = [], fireRange = [], canBarrage = false, barrageCells = [];
let canScan = false, scanCells = [];
let attackMode = null, lastFx = 0, hoverCell = null, feedSeen = 0;
let prevPos = {}, overShown = null, soloReveal = false;
let prevFog = null;   // 직전 렌더의 안개 칸 index Set (null=최초) — 안개 걷힘/덮임 트랜지션용
let prevCanAct = false;   // 직전에 '내가 둘 수 있었나' — 내 차례로 바뀌는 순간 딩 소리용

const boardEl = document.getElementById('board');
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

async function join(){
  const stored = ROOM ? (localStorage.getItem('fog_'+ROOM) || '') : '';
  const r = await post('/join', {room: ROOM, token: stored});
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
}
function showGame(){
  SCREENS.forEach(s=>{ document.getElementById(s).style.display = 'none'; });
  document.getElementById('game').style.display = 'flex';
  if(bgmEnabled()) startBgm();          // 게임 화면 진입 시 배경음악(켜져 있으면)
}
function _resetGame(){ clearSel(); prevPos={}; prevFog=null; overShown=null; lastFx=0; feedSeen=0; }

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
  const r = await post('/join', {solo:true});
  ROOM = r.room; TOKEN = r.token; COLOR = r.color;   // 'solo'
  location.hash = '#'+ROOM; localStorage.setItem('fog_'+ROOM, TOKEN);
  _resetGame(); showGame(); poll();
}
async function botStart(level){
  const r = await post('/join', {vs_bot:true, level});
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
}
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
  return r;
}
function clearSel(){ SEL=null; MOVES=[]; fireCells=[]; fireRange=[]; attackMode=null; hoverCell=null; }
async function doMove(r,c){ await act({type:'move', pid:SEL.id, r, c}); clearSel(); poll(); }
async function doFire(r,c){ await act({type:'fire', pid:SEL.id, r, c}); clearSel(); poll(); }
async function doBarrage(r,c){ await act({type:'barrage', pid:SEL.id, r, c}); clearSel(); poll(); }
async function doScan(r,c){ await act({type:'scan', pid:SEL.id, r, c}); clearSel(); poll(); }
async function placePiece(r,c){ ac(); await act({type:'place', pid:SEL.id, r, c}); if(soundOn) SND.place(); SEL=null; poll(); }
async function setReady(v){ await act({type:'ready', value:v}); poll(); }
async function rematch(){ await act({type:'rematch'}); clearSel(); clearAnnotations(); lastFx=0; feedSeen=0; prevPos={}; prevFog=null; overShown=null; poll(); }
async function doPromote(t){ await act({type:'promote', choice:t}); document.getElementById('promoModal').style.display='none'; poll(); }
async function doResign(){ if(!confirm('정말 기권할까요? 상대가 승리합니다.')) return; await act({type:'resign'}); clearSel(); poll(); }
async function leaveRoom(){
  if(!confirm('이 방에서 나가 홈으로 갈까요?')) return;
  if(ROOM) localStorage.removeItem('fog_'+ROOM);
  ROOM=null; TOKEN=''; COLOR=null; VIEW=null; location.hash='';
  clearSel(); clearAnnotations(); prevPos={}; prevFog=null; overShown=null; lastFx=0; feedSeen=0;
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
  if(setup){ SEL = pd; render(); }                   // 배치: 선택
  else if(!(SEL && SEL.id===pd.id)) selectPiece(pd); // 플레이: 선택(+행마 조회)
  dragState = { pd, moved:false, x:ev.clientX, y:ev.clientY, clone:null, setup };
  window.addEventListener('pointermove', piecePointerMove);
  window.addEventListener('pointerup', piecePointerUp);
}
function piecePointerMove(ev){
  if(!dragState) return;
  if(!dragState.moved && Math.hypot(ev.clientX-dragState.x, ev.clientY-dragState.y) < 5) return;
  dragState.moved = true;
  if(!dragState.clone){                            // 커서를 따라오는 반투명 클론
    const img = document.createElement('img');
    img.className = 'dragclone';
    img.src = pieceSrc(dragState.pd.t, VIEW.yourColor);
    document.body.appendChild(img);
    dragState.clone = img;
  }
  dragState.clone.style.left = ev.clientX + 'px';
  dragState.clone.style.top  = ev.clientY + 'px';
}
function piecePointerUp(ev){
  window.removeEventListener('pointermove', piecePointerMove);
  window.removeEventListener('pointerup', piecePointerUp);
  const ds = dragState; dragState = null;
  if(ds && ds.clone) ds.clone.remove();
  if(!ds || !ds.moved) return;                     // 움직임 없으면 그냥 클릭(선택 유지)
  const cell = boardCellFromEvent(ev); if(!cell) return;
  const [r,c] = cell;
  if(ds.setup){                                    // 배치: 내 진영 빈 땅·부쉬에 놓기
    const [z0,z1] = VIEW.zone||[0,0];
    const t = (VIEW.grid[r] && VIEW.grid[r][c]) ? VIEW.grid[r][c].t : 1;
    if(r>=z0 && r<=z1 && (t===0 || t===3)) placePiece(r, c);
    return;
  }
  if(SEL && SEL.id===ds.pd.id && !attackMode && inList(MOVES, r, c))
    doMove(r, c);                                  // 합법 이동칸에 놓으면 이동
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
  const d = annDrag; annDrag = null; if(!d) return;
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

function playFx(){
  if(!VIEW.fx || VIEW.fx.seq === lastFx) return;
  lastFx = VIEW.fx.seq;
  const tp = VIEW.fx.type;
  if(soundOn) (SND[tp]||SND.move)();
  if(['capture','kill','fire','barrage'].includes(tp)){
    VIEW.fx.cells.forEach(([r,c])=>{
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
    VIEW.fx.cells.forEach(([r,c])=>{ const el=boardEl.children[r*12+c]; if(!el) return;
      const fl=document.createElement('div'); fl.className='scanflash'; el.appendChild(fl); setTimeout(()=>fl.remove(),500); });
  }
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
  else if(solo){ big=`🏳 ${VIEW.winner==='W'?'백':'흑'} 승리`; sub='혼자 테스트'; snd='victory'; }
  else if(VIEW.winner===VIEW.yourColor){ big='🏆 승리!'; sub='적 왕 처치'; snd='victory'; }
  else { big='💀 패배'; sub='내 왕이 당했다'; snd='defeat'; }
  ov.innerHTML = `<div class="big">${big}</div><div class="sub">${sub}</div>`;
  const b = document.createElement('button'); b.className='big'; b.textContent='↻ 재대결';
  b.onclick = rematch; ov.appendChild(b);
  ac(); if(soundOn) (SND[snd]||function(){})();
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
  if(solo) wi.textContent = `🧪 혼자 테스트 · 지금 ${me==='W'?'백':'흑'} 차례`;
  else wi.textContent = COLOR==='spectator' ? '👀 관전자' : `당신은 ${COLOR==='W'?'백(아래)':'흑(위)'} 진영`;
  wi.style.background = solo ? '#4a3a1e' : (COLOR==='W' ? '#22406b' : (COLOR==='B'?'#6b2222':'#333'));
  document.getElementById('roomtag').textContent = ROOM ? `방 ${ROOM}` : '';

  renderInvite();

  // 시계: 배치=⏱ 전체시간 / 플레이=⏳ 턴 제한시간
  const tEl = document.getElementById('timer');
  if(VIEW.phase==='setup' && VIEW.secondsLeft!=null && VIEW.bothJoined){
    tEl.className = 'clock setup'; tEl.textContent = `⏱ ${VIEW.secondsLeft}s (배치)`;
  } else if(VIEW.phase==='play' && VIEW.turnSecondsLeft!=null){
    const n = VIEW.turnSecondsLeft, mine = (VIEW.turn===me);
    tEl.className = 'clock play ' + (mine?'mine':'opp') + (mine && n<=6 ? ' low' : '');
    tEl.textContent = `⏳ ${n}s · ${mine?'내 턴':'상대 턴'}`;
  } else { tEl.className=''; tEl.textContent=''; }
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
    s += `  ·  ${VIEW.turnCount}/${VIEW.turnLimit}턴`;
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
    bt = `🧪 지금 ${me==='W'?'백':'흑'} 차례`;
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

  // 병력 수
  const f = document.getElementById('forces');
  if(COLOR!=='spectator' && VIEW.phase!=='setup'){
    f.innerHTML = `<span><span class="dotc" style="background:rgb(var(--sig-me))"></span>내 병력 ${VIEW.aliveMe}</span>`
      + `<span>적 병력 ${VIEW.aliveOpp} <span class="dotc" style="background:rgb(var(--sig-opp))"></span></span>`;
  } else f.innerHTML='';

  // 컨트롤
  const ctr = document.getElementById('controls'); ctr.innerHTML = '';
  const mkBtn = (txt, fn, cls)=>{ const b=document.createElement('button'); b.textContent=txt; if(cls) b.className=cls; b.onclick=fn; ctr.appendChild(b); return b; };
  if(solo){
    mkBtn(soloReveal ? '👁 전체 보기 ON' : '🌫 전체 보기 OFF(안개)',
          ()=>{ soloReveal=!soloReveal; poll(); }, soloReveal ? 'on' : '');
  }
  // (컴퓨터 대전·혼자 테스트는 시작 메뉴로 분리 — 대기 화면 패널에는 표시하지 않음)
  if(VIEW.phase==='setup' && VIEW.bothJoined && COLOR!=='spectator'){
    mkBtn('↩ 기본 포진', ()=>autoplace('default'));
    mkBtn('🎲 무작위 배치', ()=>autoplace('random'));
    mkBtn(VIEW.ready ? '✔ 준비 완료 (취소하려면 클릭)' : '준비 완료',
          ()=>setReady(!VIEW.ready), VIEW.ready ? 'on' : '');
    const hint = document.createElement('div');
    hint.className='help'; hint.style.marginTop='2px';
    hint.textContent='기물을 끌어다 놓거나(드래그) 클릭해서 배치하세요.';
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
          const dy=(pv[0]-r)*42, dx=(pv[1]-c)*42;
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
      }
    }

    if(canSetup && r>=z0 && r<=z1 && (cell.t===0 || cell.t===3)){   // 빈 땅·부쉬 배치 가능(숲·강은 불가)
      const rr=r, cc=c;
      if(SEL){ d.classList.add('zone'); d.onclick = ()=>placePiece(rr, cc); }   // 드롭은 pointer 드래그가 처리
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
  playFx();
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

// 규칙 모달
function fillHelpPieces(){
  const box = document.getElementById('helpPieces'); if(box.childElementCount) return;
  const rows = [
    ['P','폰 — 앞·좌·우·앞대각 1칸(첫수 2칸), 후퇴 불가. 수비 라인.'],
    ['N','나이트 — 체스와 동일, 시야 2칸. 정찰의 핵심(비숍의 천적).'],
    ['B','비숍(저격수) — 대각 2 이동 / 단일 저격(사거리 5, 시야에 든 적만·쏘면 노출).'],
    ['R','전차(룩) — 상하좌우 2칸 이동 / 돌파 사격(십자 4칸, 숲에 막힘).'],
    ['Q','퀸(정찰) — 8방향 2칸 이동 / 스캔(맨해튼 6 안 2×2를 ~2턴 감시, 상대도 봄).'],
    ['K','킹 — 8방향 1칸 이동, 시야 3칸(정찰). 목숨 1. 이걸 지키고, 적 것을 노려라.'],
  ];
  box.innerHTML = rows.map(([t,desc])=>
    `<div class="hp"><img src="${pieceSrc(t,COLOR==='B'?'B':'W')}"><span>${desc}</span></div>`).join('');
}
function openHelp(){ fillHelpPieces(); document.getElementById('helpModal').style.display='flex'; }
function closeHelp(){ document.getElementById('helpModal').style.display='none'; }

document.getElementById('rematch').onclick = rematch;
document.getElementById('helpBtn').onclick = openHelp;
document.getElementById('helpClose').onclick = closeHelp;
document.getElementById('helpModal').onclick = (e)=>{ if(e.target.id==='helpModal') closeHelp(); };
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
$('mSolo').onclick     = soloStart;                         // 혼자 테스트(핫시트)
$('mSettings').onclick = ()=> openSettings('home');         // 홈에서 연 설정 → 뒤로=홈
$('setBtn').onclick    = ()=> openSettings('game');         // 게임 중 ⚙설정 → 뒤로=게임
$('lvEasy').onclick    = ()=> botStart('easy');
$('lvNormal').onclick  = ()=> botStart('normal');
$('lvHard').onclick    = ()=> botStart('hard');
$('joinGo').onclick    = ()=> joinByCode($('joinCode').value);
$('joinCode').addEventListener('keydown', (e)=>{ if(e.key==='Enter') joinByCode($('joinCode').value); });
// 뒤로: 메뉴 화면들은 홈으로, 설정만 열었던 곳(홈/게임)으로 복귀
document.querySelectorAll('#botMenu .back, #joinMenu .back').forEach(b=> b.onclick = ()=> showScreen('home'));
document.querySelectorAll('#settings .back').forEach(b=> b.onclick = closeSettings);
// 설정 항목
$('setPieces').onclick = openHelp;                          // 기물 설명 모달
$('thDark').onclick    = ()=> applyTheme('dark');
$('thLight').onclick   = ()=> applyTheme('light');
$('setSound').onchange = (e)=>{ soundOn = e.target.checked; localStorage.setItem('fog_sound', soundOn?'1':'0'); if(soundOn){ ac(); SND.place&&SND.place(); } render(); };
$('setBgm').onchange   = (e)=>{ ac(); setBgm(e.target.checked); };   // 배경음악 on/off
$('setVol').oninput    = (e)=>{ setMasterVol((+e.target.value)/100); };
$('setVol').onchange   = ()=>{ if(soundOn){ ac(); SND.place&&SND.place(); } };   // 놓을 때 한 번 미리듣기
$('setCb').onchange    = (e)=>{ applyCb(e.target.checked); render(); };          // 색약 모드

(async function main(){
  applyTheme(localStorage.getItem('fog_theme') || 'dark');
  applyCb(localStorage.getItem('fog_cb') === '1');
  renderCoords();
  setInterval(poll, 900);
  const hash = (location.hash || '').replace('#','');
  if(hash){                                                 // 초대 링크로 들어온 경우 → 바로 그 방
    ROOM = hash;
    await join(); showGame(); await poll();
    if(!localStorage.getItem('fog_help_seen')){ openHelp(); localStorage.setItem('fog_help_seen','1'); }
  }else{                                                    // 그 외 → 시작 메뉴
    showScreen('home');
  }
})();
