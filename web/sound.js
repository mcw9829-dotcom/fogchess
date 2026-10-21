// ============================================================
//  안개전장 체스 — 사운드 (효과음 전용)
// ------------------------------------------------------------
//  · 오디오 '파일'은 없습니다. 아래 코드로 실시간 합성합니다(Web Audio API).
//  · 소리를 바꾸려면 맨 아래 SND 표의 숫자만 고치면 됩니다.
//    (재생을 켜고/끄는 on/off 토글은 client.html 쪽에 있음)
//
//  tone(freq, dur, type, vol, slideTo)
//    freq    : 시작 주파수(Hz) — 높을수록 고음
//    dur     : 길이(초)
//    type    : 파형 'sine' | 'triangle' | 'square' | 'sawtooth'
//    vol     : 볼륨 0.0 ~ 1.0
//    slideTo : (선택) 이 주파수로 미끄러짐 → 하강음/상승음 효과
//  noise(dur, vol) : 잡음 버스트(타격·폭발감)
//
//  효과음 목록(SND):
//    move    이동         place   배치          capture 근접 처치
//    fire    비숍 저격    barrage 룩 돌파사격   kill    킹 처치(승부)
//    victory 승리         defeat  패배          drawend 무승부
//    yourturn 내 차례 알림(딩)   scan  퀸 스캔(핑)
// ============================================================

let AC = null;
function ac(){ if(!AC){ try{ AC = new (window.AudioContext||window.webkitAudioContext)(); }catch(e){} } return AC; }

// 마스터 볼륨(0~1) — 설정에서 조절, 브라우저에 저장. tone/noise 볼륨에 곱해짐.
let MASTER = parseFloat(localStorage.getItem('fog_vol') || '1');
function masterVol(){ return MASTER; }
function setMasterVol(v){ MASTER = Math.max(0, Math.min(1, +v || 0)); localStorage.setItem('fog_vol', String(MASTER));
  if(typeof bgmVolRefresh === 'function') bgmVolRefresh(); }

function tone(freq, dur, type, vol, slideTo){
  const c = ac(); if(!c) return;
  const o = c.createOscillator(), g = c.createGain();
  o.type = type||'sine'; o.frequency.value = freq;
  if(slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, c.currentTime+dur);
  g.gain.value = (vol||0.2) * MASTER; g.gain.exponentialRampToValueAtTime(0.001, c.currentTime+dur);
  o.connect(g).connect(c.destination); o.start(); o.stop(c.currentTime+dur);
}

function noise(dur, vol){
  const c = ac(); if(!c) return;
  const b = c.createBuffer(1, c.sampleRate*dur, c.sampleRate);
  const d = b.getChannelData(0);
  for(let i=0;i<d.length;i++) d[i] = (Math.random()*2-1)*Math.pow(1-i/d.length,2);
  const s = c.createBufferSource(); s.buffer = b;
  const g = c.createGain(); g.gain.value = (vol||0.4) * MASTER;
  s.connect(g).connect(c.destination); s.start();
}

// ── 효과음 정의: 여기 숫자만 바꾸면 소리가 바뀝니다 ──
const SND = {
  move:    ()=> tone(320, .08, 'triangle', .18),                          // 이동: 짧고 가벼운 '톡'
  place:   ()=> tone(440, .05, 'square', .12),                            // 배치: 딸깍
  capture: ()=>{ tone(180,.12,'sawtooth',.22,90); noise(.15,.25); },      // 근접 처치: 둔탁 + 잡음
  fire:    ()=>{ tone(90,.5,'sawtooth',.3,40); noise(.5,.5); },           // 비숍 저격: 저음 발사
  barrage: ()=>{ for(let i=0;i<4;i++) setTimeout(()=>tone(140,.06,'square',.16),i*55); noise(.35,.4); }, // 룩 돌파사격: 연사
  kill:    ()=>{ tone(70,.7,'sawtooth',.35,30); noise(.7,.6); setTimeout(()=>tone(520,.3,'square',.2),120); }, // 킹 처치: 큰 폭발 + 여운
  victory: ()=>{ [523,659,784,1047].forEach((f,i)=>setTimeout(()=>tone(f,.2,'square',.16),i*95)); },    // 승리: 상승 팡파레
  defeat:  ()=>{ [392,330,262].forEach((f,i)=>setTimeout(()=>tone(f,.28,'sawtooth',.16),i*130)); },      // 패배: 하강음
  drawend: ()=>{ tone(440,.18,'triangle',.14); setTimeout(()=>tone(392,.24,'triangle',.14),150); },      // 무승부: 무던한 2음
  yourturn:()=>{ tone(880,.12,'sine',.16); setTimeout(()=>tone(1175,.16,'sine',.16),90); },              // 내 차례 알림: 딩(상승 2음)
  scan:    ()=>{ tone(600,.18,'sine',.13,1500); setTimeout(()=>tone(950,.14,'sine',.11,1700),90); },     // 퀸 스캔: 레이더 핑(상승 스윕)
};

// ============================================================
//  배경음악(BGM) — 파일 없이 합성한 잔잔한 앰비언트 드론(안개 낀 전장 분위기)
//   · 낮은 드론 화음 + 아주 느린 로우패스 필터 스윕(LFO)으로 은은한 움직임.
//   · 효과음과 별개 토글(fog_bgm). 음량은 마스터 볼륨을 따름. 기본 off.
// ============================================================
let BGM = null;
let bgmOn = localStorage.getItem('fog_bgm') !== '0';   // 기본 켜짐(끄면 '0' 저장). 게임 진입 시 조용히 재생
function bgmEnabled(){ return bgmOn; }
function bgmVolRefresh(){ if(BGM){ const c=ac(); if(c) BGM.master.gain.setTargetAtTime(0.06*MASTER, c.currentTime, 0.3); } }
function startBgm(){
  const c = ac(); if(!c || BGM) return;
  const master = c.createGain(); master.gain.value = 0;              // 무음에서 페이드 인
  master.connect(c.destination);
  const filt = c.createBiquadFilter(); filt.type='lowpass'; filt.frequency.value=520; filt.Q.value=5;
  filt.connect(master);
  const freqs = [110.0, 164.81, 220.0];                              // A2 · E3 · A3 (열린 5도 화음)
  const oscs = freqs.map((f,i)=>{
    const o=c.createOscillator(); o.type = (i===2?'triangle':'sine'); o.frequency.value=f;
    const g=c.createGain(); g.gain.value = (i===0?0.5:i===1?0.3:0.18);
    o.connect(g).connect(filt); o.start(); return o;
  });
  const lfo=c.createOscillator(); lfo.frequency.value=0.05;          // 20초 주기 필터 스윕
  const lfoGain=c.createGain(); lfoGain.gain.value=170;
  lfo.connect(lfoGain).connect(filt.frequency); lfo.start();
  master.gain.setTargetAtTime(0.06*MASTER, c.currentTime, 2.5);      // 조용히 서서히 등장
  BGM = { oscs, lfo, master };
}
function stopBgm(){
  if(!BGM) return; const c=ac(); const b=BGM; BGM=null;
  try{ if(c) b.master.gain.setTargetAtTime(0, c.currentTime, 0.6); }catch(e){}
  setTimeout(()=>{ b.oscs.forEach(o=>{try{o.stop()}catch(e){}}); try{b.lfo.stop()}catch(e){} }, 900);
}
function setBgm(on){
  bgmOn = !!on; localStorage.setItem('fog_bgm', bgmOn?'1':'0');
  if(bgmOn) startBgm(); else stopBgm();
}
