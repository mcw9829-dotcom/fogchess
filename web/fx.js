// fx.js — 안개전장 체스 파티클 이펙트 레이어 (Canvas 2D, 라이브러리 없음)
//  · new FxLayer(hostEl, gridEl, {border, cols}) : hostEl(position:relative) 위에 캔버스를 덮고 gridEl 크기에 맞춤
//  · play(type, cells, from, extra) : type = move|capture|fire|barrage|scan|kill (서버 fx.type 그대로)
//      cells=[[r,c],...] 착탄/대상 칸, from=[r,c] 사격 출발점(있으면 탄도선), extra=스캔으로 발각된 칸들
//  · victory() / defeat() / drawend() : 게임 종료 연출(색종이 / 잿가루 / 잔잔한 종이)
//  · 이펙트가 살아있는 동안만 requestAnimationFrame(평소 CPU 0) · DPR≤2 · 입자 상한 · 탭 숨김 시 정리
//  · prefers-reduced-motion: 입자 수 축소, 흔들림/슬로모 없음
(function(){
'use strict';
const RM  = !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches);
const MAX = 600;
const TAU = Math.PI * 2;
const rnd  = (a, b) => a + Math.random() * (b - a);
const pick = a => a[(Math.random() * a.length) | 0];
const SPARK    = ['#fff7d6', '#ffe08a', '#ffc24d', '#ffffff'];
const DEBRIS   = ['#3a2e22', '#6b5238', '#8a6d4a', '#2b2521', '#b08a55'];
const CONFETTI = ['#e6c96a', '#f3ecdf', '#c69a5e', '#d63a1a', '#3d7bd6', '#ffffff'];

// ---- 입자 그리기(종류별) : (ctx, 입자, 진행도 0~1, 레이어) ----
const D = {
  spark(g, p, k){                                   // 불꽃: 속도 방향으로 짧은 꼬리
    const tx = p.x - p.vx * 0.025, ty = p.y - p.vy * 0.025;
    g.strokeStyle = p.color; g.lineWidth = p.size; g.lineCap = 'round';
    g.beginPath(); g.moveTo(p.x, p.y); g.lineTo(tx, ty); g.stroke();
  },
  dot(g, p, k){ g.fillStyle = p.color; g.beginPath(); g.arc(p.x, p.y, p.size, 0, TAU); g.fill(); },
  smoke(g, p, k){                                   // 연기/먼지/화구: 커지며 흐려지는 원(그라디언트)
    const r = p.size * (0.35 + k * 1.1);
    const gr = g.createRadialGradient(p.x, p.y, 0, p.x, p.y, r);
    gr.addColorStop(0, p.color); gr.addColorStop(1, p.color2 || 'rgba(0,0,0,0)');
    g.fillStyle = gr; g.beginPath(); g.arc(p.x, p.y, r, 0, TAU); g.fill();
  },
  debris(g, p, k){                                  // 파편: 회전하는 작은 조각
    g.save(); g.translate(p.x, p.y); g.rotate(p.rot || 0);
    g.fillStyle = p.color; g.fillRect(-p.size / 2, -p.size / 3, p.size, p.size * 0.66); g.restore();
  },
  ring(g, p, k){                                    // 충격파 링: 빠르게 퍼지며 얇아짐
    const e = 1 - Math.pow(1 - k, 3), r = p.r0 + (p.r1 - p.r0) * e;
    g.strokeStyle = p.color; g.lineWidth = Math.max(1, p.size * (1 - k));
    g.beginPath(); g.arc(p.x, p.y, r, 0, TAU); g.stroke();
  },
  flash(g, p, k){                                   // 섬광: 흰 중심 → 색 → 투명
    const e = 1 - Math.pow(1 - k, 2), r = p.r0 + (p.r1 - p.r0) * e;
    const gr = g.createRadialGradient(p.x, p.y, 0, p.x, p.y, r);
    gr.addColorStop(0, 'rgba(255,255,255,1)'); gr.addColorStop(0.35, p.color); gr.addColorStop(1, 'rgba(255,120,30,0)');
    g.fillStyle = gr; g.beginPath(); g.arc(p.x, p.y, r, 0, TAU); g.fill();
  },
  tracer(g, p, k){                                  // 탄도선: 빛나는 선의 머리가 A→B로 달림
    const h = Math.min(1, k * 1.15), t0 = Math.max(0, h - p.len);
    const x0 = p.x + (p.x2 - p.x) * t0, y0 = p.y + (p.y2 - p.y) * t0;
    const x1 = p.x + (p.x2 - p.x) * h,  y1 = p.y + (p.y2 - p.y) * h;
    g.shadowBlur = 12; g.shadowColor = p.color; g.strokeStyle = p.color; g.lineWidth = p.size; g.lineCap = 'round';
    g.beginPath(); g.moveTo(x0, y0); g.lineTo(x1, y1); g.stroke(); g.shadowBlur = 0;
  },
  sweep(g, p, k){                                   // 레이더 스윕: 회전하는 부채꼴 + 외곽 링
    g.save(); g.translate(p.x, p.y); g.rotate(p.a0 + k * p.turns * TAU);
    for(let i = 0; i < 7; i++){
      g.fillStyle = 'rgba(' + p.rgb + ',' + (0.38 * (1 - i / 7)).toFixed(3) + ')';
      g.beginPath(); g.moveTo(0, 0); g.arc(0, 0, p.r, -(i + 1) * 0.2, -i * 0.2); g.closePath(); g.fill();
    }
    g.restore();
    g.strokeStyle = 'rgba(' + p.rgb + ',0.85)'; g.lineWidth = 1.5; g.beginPath(); g.arc(p.x, p.y, p.r, 0, TAU); g.stroke();
  },
  vignette(g, p, k, L){                             // 화면 가장자리 어둡게(킹 처치·패배)
    const gr = g.createRadialGradient(L.W / 2, L.H / 2, L.W * 0.25, L.W / 2, L.H / 2, L.W * 0.78);
    gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, p.color);
    g.fillStyle = gr; g.fillRect(0, 0, L.W, L.H);
  },
  confetti(g, p, k){                                // 색종이: 좌우로 팔랑이며 회전 낙하
    g.save(); g.translate(p.x + Math.sin(p.age * p.freq) * p.amp, p.y); g.rotate(p.rot || 0);
    g.fillStyle = p.color; g.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2); g.restore();
  },
};

class FxLayer {
  constructor(host, grid, opt){
    opt = opt || {};
    this.host = host; this.grid = grid;
    this.border = opt.border == null ? 4 : opt.border;   // 그리드 테두리 두께(캔버스 오프셋)
    this.cols = opt.cols || 12;
    this.cv = document.createElement('canvas'); this.cv.className = 'fxcanvas';
    host.appendChild(this.cv); this.ctx = this.cv.getContext('2d');
    this.parts = []; this.timers = []; this.raf = null; this.last = 0; this.t = 0;
    this.shake = 0; this.slow = 0; this.W = 0; this.H = 0; this.dpr = 0; this.cw = 28;
    this._tick = this._tick.bind(this);
    document.addEventListener('visibilitychange', () => { if(document.hidden) this.clear(); });
    this.resize();
  }
  resize(){
    const w = this.grid.clientWidth, h = this.grid.clientHeight || w;
    if(!w) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if(w === this.W && h === this.H && dpr === this.dpr) return;
    this.W = w; this.H = h; this.dpr = dpr; this.cw = w / this.cols;
    const s = this.cv.style; s.left = this.border + 'px'; s.top = this.border + 'px'; s.width = w + 'px'; s.height = h + 'px';
    this.cv.width = Math.round(w * dpr); this.cv.height = Math.round(h * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  clear(){
    this.parts.length = 0; this.timers.length = 0; this.shake = 0; this.slow = 0;
    if(this.raf){ cancelAnimationFrame(this.raf); this.raf = null; }
    this.ctx.clearRect(0, 0, this.W, this.H); this.host.style.transform = '';
  }
  cx(c){ return (c + 0.5) * this.cw; }
  cy(r){ return (r + 0.5) * this.cw; }
  get busy(){ return this.raf !== null; }

  // ---------- 엔진 ----------
  add(p){ if(this.parts.length >= MAX) this.parts.shift(); p.age = 0; this.parts.push(p); this._start(); }
  after(sec, fn){ this.timers.push({ at: this.t + sec, fn }); this._start(); }
  _start(){ if(!this.raf){ this.last = performance.now(); this.raf = requestAnimationFrame(this._tick); } }
  _tick(now){
    const real = Math.min(0.05, (now - this.last) / 1000); this.last = now;
    const dt = this.slow > 0 ? real * 0.35 : real;          // 슬로모(킹 처치)
    if(this.slow > 0) this.slow -= real;
    this.t += dt;
    if(this.timers.length){                                  // 예약된 단계(타이밍은 엔진 시계 기준)
      const due = this.timers.filter(x => x.at <= this.t);
      this.timers = this.timers.filter(x => x.at > this.t);
      due.forEach(x => x.fn());
    }
    const alive = [];
    for(const p of this.parts){
      p.age += dt; if(p.age >= p.life) continue;
      p.x += p.vx * dt; p.y += p.vy * dt;
      if(p.grav) p.vy += p.grav * dt;
      if(p.drag){ const k = Math.max(0, 1 - p.drag * dt); p.vx *= k; p.vy *= k; }
      if(p.vr) p.rot = (p.rot || 0) + p.vr * dt;
      alive.push(p);
    }
    this.parts = alive;
    this._draw();
    if(this.shake > 0){                                      // 화면 흔들림(호스트 transform)
      const a = this.shake * 7;
      this.host.style.transform = 'translate(' + rnd(-a, a).toFixed(1) + 'px,' + rnd(-a, a).toFixed(1) + 'px)';
      this.shake -= real * 2.4;
      if(this.shake <= 0){ this.shake = 0; this.host.style.transform = ''; }
    }
    if(this.parts.length || this.timers.length || this.shake > 0) this.raf = requestAnimationFrame(this._tick);
    else { this.raf = null; this.ctx.clearRect(0, 0, this.W, this.H); this.host.style.transform = ''; }
  }
  _draw(){
    const g = this.ctx; g.clearRect(0, 0, this.W, this.H);
    for(const p of this.parts){
      const k = p.age / p.life;
      g.globalCompositeOperation = p.blend || 'source-over';
      let a = (p.a == null ? 1 : p.a) * (p.hold ? 1 : (1 - k));
      if(p.fadeIn) a *= Math.min(1, k * 4);
      g.globalAlpha = Math.max(0, Math.min(1, a));
      p.draw(g, p, k, this);
    }
    g.globalAlpha = 1; g.globalCompositeOperation = 'source-over';
  }

  // ---------- 이미터(기본 재료) ----------
  sparks(x, y, n, sp){
    n = RM ? Math.ceil(n / 4) : n;
    for(let i = 0; i < n; i++){
      const a = rnd(0, TAU), s = rnd(sp * 0.35, sp);
      this.add({ draw: D.spark, x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - sp * 0.15, grav: this.cw * 9, drag: 1.8,
                 life: rnd(0.3, 0.6), size: rnd(1, 2.2), color: pick(SPARK), blend: 'lighter' });
    }
  }
  dust(x, y, n){                                     // 흙먼지(갈색, 낮게 퍼짐)
    n = RM ? 2 : n;
    for(let i = 0; i < n; i++){
      const a = rnd(0, TAU), s = rnd(this.cw * 0.5, this.cw * 1.6);
      this.add({ draw: D.smoke, x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s * 0.5 - this.cw * 0.4, drag: 2.5,
                 life: rnd(0.45, 0.8), size: this.cw * rnd(0.28, 0.45), color: 'rgba(181,154,106,.6)', color2: 'rgba(181,154,106,0)' });
    }
  }
  smoke(x, y, n, big){                               // 회색 연기(위로 솟음)
    n = RM ? 3 : n;
    for(let i = 0; i < n; i++){
      const a = rnd(0, TAU), s = rnd(this.cw * 0.3, this.cw * (big ? 2.2 : 1.2));
      this.add({ draw: D.smoke, x: x + rnd(-4, 4), y: y + rnd(-4, 4), vx: Math.cos(a) * s * 0.5,
                 vy: -Math.abs(Math.sin(a)) * s - this.cw * (big ? 1.2 : 0.6), drag: 0.9,
                 life: rnd(big ? 1.2 : 0.8, big ? 2.0 : 1.4), size: this.cw * rnd(0.4, big ? 0.9 : 0.6),
                 color: 'rgba(78,74,70,.55)', color2: 'rgba(60,58,56,0)' });
    }
  }
  fireball(x, y, n){                                 // 화구(가산 혼합 주황)
    n = RM ? 4 : n;
    for(let i = 0; i < n; i++){
      const a = rnd(0, TAU), s = rnd(this.cw * 1.5, this.cw * 5);
      this.add({ draw: D.smoke, x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - this.cw * 1.5, drag: 2.2,
                 life: rnd(0.35, 0.6), size: this.cw * rnd(0.45, 0.75), color: 'rgba(255,150,50,.95)', color2: 'rgba(255,60,10,0)', blend: 'lighter' });
    }
  }
  debris(x, y, n, sp){                               // 파편(위로 튀어 중력 낙하)
    n = RM ? 0 : n;
    for(let i = 0; i < n; i++){
      const a = -rnd(0.15, Math.PI - 0.15), s = rnd(sp * 0.4, sp);
      this.add({ draw: D.debris, x, y, vx: Math.cos(a) * s * rnd(0.6, 1.4), vy: Math.sin(a) * s, grav: this.cw * 16, drag: 0.4,
                 vr: rnd(-12, 12), rot: rnd(0, TAU), life: rnd(0.6, 1.0), size: rnd(2.5, 5.5), color: pick(DEBRIS) });
    }
  }
  ring(x, y, r0, r1, dur, color, width){ this.add({ draw: D.ring, x, y, vx: 0, vy: 0, r0, r1, life: dur, color, size: width || 4 }); }
  flash(x, y, r, dur, color){ this.add({ draw: D.flash, x, y, vx: 0, vy: 0, r0: r * 0.2, r1: r, life: dur, color: color || 'rgba(255,200,90,.95)', blend: 'lighter' }); }
  tracer(x, y, x2, y2, dur, color, width, len){
    this.add({ draw: D.tracer, x, y, x2, y2, vx: 0, vy: 0, life: dur, color: color || '#ffe9a0', size: width || 2.5, len: len || 0.35, blend: 'lighter', hold: true });
  }
  vignette(color, dur){ this.add({ draw: D.vignette, x: 0, y: 0, vx: 0, vy: 0, life: dur, color: color || 'rgba(0,0,0,.55)' }); }
  shakeBy(v){ if(!RM) this.shake = Math.max(this.shake, v); }
  slowmo(sec){ if(!RM) this.slow = sec; }

  // ---------- 게임 이벤트 연출 ----------
  play(type, cells, from, extra){
    this.resize(); if(!this.W) return;
    const C = (cells || []).map(([r, c]) => [this.cx(c), this.cy(r)]);
    const F = from ? [this.cx(from[1]), this.cy(from[0])] : null;
    switch(type){
      case 'move':    break;                                                          // 이동은 연출 없음(사용자 결정)
      case 'capture': C.forEach(([x, y]) => {                                          // 포획: 섬광 + 링 + 약한 흔들림만
        this.flash(x, y, this.cw * 0.95, 0.18);
        this.ring(x, y, this.cw * 0.2, this.cw * 1.05, 0.45, 'rgba(255,220,140,.9)', 3);
      }); this.shakeBy(0.15); break;
      case 'fire':    this._shot(F, C[0], 0.95, 0.12); break;                          // 저격: 탄도선 → 착탄
      case 'barrage': this._barrage(F, C); break;                                     // 돌파: 칸 순서대로 관통
      case 'scan':    this._scan(C, (extra || []).map(([r, c]) => [this.cx(c), this.cy(r)])); break;
      case 'kill':    this._kill(F, C[C.length - 1]); break;                           // 킹 처치: 대폭발
    }
  }
  _impact(x, y, s){                                  // 착탄 기본형: 섬광 + 링 + 불꽃 + 먼지 + 파편
    s = s || 1;
    this.flash(x, y, this.cw * 1.2 * s, 0.18);
    this.ring(x, y, this.cw * 0.2, this.cw * 1.3 * s, 0.45, 'rgba(255,220,140,.9)', 3);
    this.sparks(x, y, Math.round(22 * s), this.cw * 9 * s);
    this.dust(x, y, Math.round(8 * s));
    this.debris(x, y, Math.round(8 * s), this.cw * 7 * s);
  }
  _shot(F, T, s, delay){
    if(!T) return;
    const hit = () => { this._impact(T[0], T[1], s); this.smoke(T[0], T[1], 8); this.shakeBy(0.25); };
    if(F){
      this.flash(F[0], F[1], this.cw * 0.7, 0.14, 'rgba(255,240,180,.95)');       // 총구 섬광
      this.tracer(F[0], F[1], T[0], T[1], delay, '#ffe9a0', 2.5, 0.3);
      this.after(delay, hit);
    } else hit();
  }
  _barrage(F, C){                                  // 전차 돌파 사격: 포구 화염 → 굵은 탄도가 칸마다 착탄(연쇄 폭발) → 마지막 칸 충격파
    if(!C.length) return;                            //   저격(한 점 착탄)과 달리 경로 전체가 폭발하고, 진동은 모든 공격 중 가장 강함(킹 처치 다음)
    const n = C.length;
    if(F){ this.flash(F[0], F[1], this.cw * 1.1, 0.18, 'rgba(255,230,160,.98)'); this.smoke(F[0], F[1], 6); this.dust(F[0], F[1], 8); }
    this.shakeBy(0.45);                                                      // 발사 반동
    let prev = F || C[0];
    C.forEach((pt, i) => {
      const from = prev; prev = pt;
      const last = i === n - 1, s = last ? 1.1 : 0.8;
      this.after(0.09 * i + (F ? 0.05 : 0), () => {
        if(from !== pt) this.tracer(from[0], from[1], pt[0], pt[1], 0.08, '#ffd88a', 4, 0.9);   // 굵은 탄도(포탄)
        this._impact(pt[0], pt[1], s);                                       // 칸마다 진짜 폭발: 섬광·링·불꽃·먼지·파편
        this.smoke(pt[0], pt[1], last ? 12 : 5);
        this.shakeBy(last ? 0.55 : 0.4);                                     // 연쇄 폭발마다 흔들림을 이어감(전차 컨셉)
        if(last) this.ring(pt[0], pt[1], this.cw * 0.3, this.cw * 2.4, 0.6, 'rgba(255,200,120,.85)', 4);   // 마지막 칸 큰 충격파
      });
    });
  }
  _scan(C, found){
    if(!C.length) return;
    const x = C.reduce((s, p) => s + p[0], 0) / C.length, y = C.reduce((s, p) => s + p[1], 0) / C.length, r = this.cw * 1.5;
    this.add({ draw: D.sweep, x, y, vx: 0, vy: 0, r, a0: rnd(0, TAU), turns: 1.5, life: 1.0, rgb: '56,135,235' });
    this.ring(x, y, this.cw * 0.3, r * 1.25, 0.6, 'rgba(56,135,235,.85)', 2);
    this.after(0.3, () => this.ring(x, y, this.cw * 0.3, r * 1.25, 0.6, 'rgba(56,135,235,.6)', 2));
    found.forEach(([fx, fy], i) => this.after(0.35 + i * 0.1, () => {          // 발각된 적: 핑
      this.ring(fx, fy, this.cw * 0.1, this.cw * 0.8, 0.5, 'rgba(120,190,255,1)', 3);
      this.add({ draw: D.dot, x: fx, y: fy, vx: 0, vy: 0, life: 0.6, size: this.cw * 0.14, color: '#9fd0ff', blend: 'lighter' });
    }));
  }
  _kill(F, T){
    if(!T) return;
    const go = () => {
      const [x, y] = T;
      this.vignette('rgba(0,0,0,.6)', 0.5);
      this.flash(x, y, this.cw * 2.6, 0.28, 'rgba(255,220,120,1)');
      this.ring(x, y, this.cw * 0.3, this.cw * 3.2, 0.7, 'rgba(255,230,160,.95)', 5);
      this.sparks(x, y, 44, this.cw * 13);
      this.shakeBy(0.65); this.slowmo(0.3);
      this.after(0.06, () => { this.fireball(x, y, 26); this.debris(x, y, 26, this.cw * 11); });
      this.after(0.20, () => this.smoke(x, y, 30, true));
      this.after(0.45, () => this.sparks(x, y, 14, this.cw * 5));
    };
    if(F){                                           // 사격으로 처치: 탄도선 먼저
      this.flash(F[0], F[1], this.cw * 0.8, 0.14, 'rgba(255,240,180,.95)');
      this.tracer(F[0], F[1], T[0], T[1], 0.12, '#ffe9a0', 3, 0.3);
      this.after(0.12, go);
    } else go();
  }

  // ---------- 게임 종료 ----------
  victory(){
    this.resize(); const n = RM ? 20 : 120;
    for(let i = 0; i < n; i++) this.after(rnd(0, 0.9), () => this.add({
      draw: D.confetti, x: rnd(0, this.W), y: rnd(-this.cw, 0), vx: rnd(-20, 20), vy: rnd(this.cw * 1.2, this.cw * 2.4),
      grav: this.cw * 1.5, drag: 0.4, vr: rnd(-4, 4), rot: rnd(0, TAU), freq: rnd(3, 7), amp: rnd(4, 12),
      life: rnd(2.2, 3.2), size: rnd(5, 9), color: pick(CONFETTI), fadeIn: true }));
    this.after(0.2, () => this.sparks(this.W / 2, this.H * 0.4, 30, this.cw * 8));
  }
  defeat(){
    this.resize(); this.vignette('rgba(0,0,0,.7)', 2.2); const n = RM ? 15 : 80;
    for(let i = 0; i < n; i++) this.after(rnd(0, 1.2), () => this.add({
      draw: D.dot, x: rnd(0, this.W), y: rnd(-this.cw, 0), vx: rnd(-8, 8), vy: rnd(this.cw * 0.5, this.cw * 1.1), drag: 0.2,
      life: rnd(2, 3.2), size: rnd(1.2, 2.6), color: 'rgba(150,150,150,.8)', fadeIn: true }));
  }
  drawend(){
    this.resize(); const n = RM ? 10 : 40;
    for(let i = 0; i < n; i++) this.after(rnd(0, 0.8), () => this.add({
      draw: D.confetti, x: rnd(0, this.W), y: rnd(-this.cw, 0), vx: rnd(-10, 10), vy: rnd(this.cw * 0.9, this.cw * 1.6),
      grav: this.cw, drag: 0.4, vr: rnd(-3, 3), rot: rnd(0, TAU), freq: rnd(3, 6), amp: rnd(3, 8),
      life: rnd(2, 2.8), size: rnd(4, 7), color: pick(['#cfc7bb', '#a49d93', '#e6c96a']), fadeIn: true }));
  }
}
window.FxLayer = FxLayer;
})();
