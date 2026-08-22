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
// ============================================================

let AC = null;
function ac(){ if(!AC){ try{ AC = new (window.AudioContext||window.webkitAudioContext)(); }catch(e){} } return AC; }

function tone(freq, dur, type, vol, slideTo){
  const c = ac(); if(!c) return;
  const o = c.createOscillator(), g = c.createGain();
  o.type = type||'sine'; o.frequency.value = freq;
  if(slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, c.currentTime+dur);
  g.gain.value = vol||0.2; g.gain.exponentialRampToValueAtTime(0.001, c.currentTime+dur);
  o.connect(g).connect(c.destination); o.start(); o.stop(c.currentTime+dur);
}

function noise(dur, vol){
  const c = ac(); if(!c) return;
  const b = c.createBuffer(1, c.sampleRate*dur, c.sampleRate);
  const d = b.getChannelData(0);
  for(let i=0;i<d.length;i++) d[i] = (Math.random()*2-1)*Math.pow(1-i/d.length,2);
  const s = c.createBufferSource(); s.buffer = b;
  const g = c.createGain(); g.gain.value = vol||0.4;
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
};
