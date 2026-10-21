/* 고정 미션: 실제 대국과 분리된 연습판. 서버 방·전적을 만들지 않는다. */
const FogTutorial = (() => {
  const KEY = 'fog_learning_v1';
  const lessons = [
    ['안개 속에는 누가 있을까요?', '나이트를 선택하고 표시된 칸으로 이동하세요.', '이동하면 내 기물 주변의 안개가 걷힙니다.'],
    ['숨은 왕을 찾아보세요', '퀸을 선택하고 스캔 버튼을 누르세요.', '스캔은 멀리 있는 2×2 영역을 밝혀줍니다.'],
    ['발견한 왕을 저격하세요', '비숍을 선택하고 저격 버튼을 누르세요.', '비숍은 사거리 안의 보이는 적을 저격합니다.'],
    ['적 왕을 잡았습니다!', '정찰로 발견하고, 저격으로 승리했어요.', 'FOGCHESS는 체크메이트 대신 적 왕을 잡으면 승리합니다.']
  ];
  let modal, board, step = 0, selected = false, armed = false, savedFocus, startBot;
  function read(){ try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch { return {}; } }
  function save(){ try { localStorage.setItem(KEY, JSON.stringify({step, completed:step===3})); } catch {} }
  function label(){
    const s=read();
    document.getElementById('learnLabel').textContent=s.completed?'왕 찾기 미션 다시 하기':s.step>0?'왕 찾기 미션 이어하기':'직접 배우기 · 왕 찾기 미션';
  }
  function init(bot){
    startBot=bot;
    document.getElementById('mLearn').onclick=open;
    label();
  }
  function open(){
    savedFocus=document.activeElement;
    const s=read(); step=s.completed?0:Math.max(0,Math.min(2,Number(s.step)||0)); selected=false; armed=false;
    if(!modal){
      modal=document.createElement('dialog'); modal.className='learn-modal'; modal.setAttribute('aria-labelledby','learnTitle');
      modal.innerHTML=`<div class="learn-shell">
        <header class="learn-header"><span>FIELD GUIDE / 첫 정찰</span><button type="button" id="learnClose" aria-label="미션 닫기">✕</button></header>
        <div class="learn-layout"><section class="learn-map"><div class="learn-map-meta"><span>왕 찾기 미션</span><span>시간제한 없음</span></div><div class="learn-board" role="group" aria-label="8 곱하기 8 연습판"></div><p class="learn-map-foot">축소 연습판 · 흰 기물은 내 편 · 상대는 연습을 위해 대기합니다.</p></section>
        <section class="learn-panel"><ol class="learn-progress" aria-label="학습 순서"><li>1 이동</li><li>2 스캔</li><li>3 저격</li></ol>
        <p class="learn-eyebrow">목표 / 숨은 적 왕 잡기</p><h2 id="learnTitle"></h2><p id="learnInstruction"></p>
        <div id="learnFeedback" class="learn-feedback" role="status" aria-live="polite"></div>
        <button type="button" id="learnAbility" class="learn-action"></button><p id="learnReason" class="learn-reason"></p>
        <div id="learnSuccess" hidden><button type="button" id="learnBot" class="learn-action">컴퓨터(쉬움)와 첫 대국 →</button><button type="button" id="learnHome">홈으로 돌아가기</button></div>
        <footer class="learn-footer"><button type="button" id="learnReset">처음부터</button><span>진행 상황은 이 기기에 저장돼요</span></footer></section></div></div>`;
      document.body.appendChild(modal); board=modal.querySelector('.learn-board');
      modal.querySelector('#learnClose').onclick=close;
      modal.querySelector('#learnHome').onclick=close;
      modal.querySelector('#learnReset').onclick=()=>{step=0;selected=false;armed=false;save();render();};
      modal.querySelector('#learnBot').onclick=()=>{close();startBot();};
      modal.querySelector('#learnAbility').onclick=()=>{armed=true;render();feedback(step===1?'표시된 영역을 눌러 스캔하세요.':'밝게 드러난 검은 왕을 눌러 저격하세요.');};
      modal.addEventListener('cancel',e=>{e.preventDefault();close();});
    }
    render(); modal.showModal(); modal.querySelector('#learnClose').focus();
  }
  function close(){modal.close();label();if(savedFocus?.isConnected)savedFocus.focus();}
  function feedback(text){modal.querySelector('#learnFeedback').textContent=text;}
  function advance(){step++;selected=false;armed=false;save();render();feedback(['','적 폰을 발견했어요! 하지만 왕은 아직 안개 속에 있습니다.','스캔 성공! 적 왕이 드러났어요. 상대가 대기한 뒤 다시 내 차례입니다.','미션 완료 · 이제 직접 적 왕을 찾고 공격할 수 있어요.'][step]);}
  function click(r,c){
    if(step===3)return;
    const own=step===0?[6,2]:step===1?[6,4]:[5,2];
    if(r===own[0]&&c===own[1]){selected=true;armed=false;render();feedback(step===0?'점으로 표시된 칸을 누르면 이동합니다.':`${step===1?'퀸':'비숍'}을 선택했어요. ${step===1?'스캔':'저격'} 버튼을 누르세요.`);return;}
    if(step===0&&selected&&r===4&&c===1){advance();return;}
    if(step===1&&armed&&r>=1&&r<=2&&c>=5&&c<=6){advance();return;}
    if(step===2&&armed&&r===1&&c===5){advance();return;}
    feedback(!selected?lessons[step][1]:step===0?'점으로 표시된 칸을 눌러보세요.':!armed?`먼저 ${step===1?'스캔':'저격'} 버튼을 누르세요.`:step===1?'모서리가 표시된 스캔 영역을 눌러보세요.':'지금 보이는 검은 왕이 저격 목표예요.');
  }
  function render(){
    const [title,instruction,reason]=lessons[step];
    modal.querySelector('#learnTitle').textContent=title;modal.querySelector('#learnInstruction').textContent=instruction;modal.querySelector('#learnReason').textContent=reason;feedback('');
    modal.querySelectorAll('.learn-progress li').forEach((li,i)=>{li.classList.toggle('done',i<step);li.classList.toggle('current',i===step);if(i===step)li.setAttribute('aria-current','step');else li.removeAttribute('aria-current');});
    const ability=modal.querySelector('#learnAbility');ability.hidden=step===0||step===3;ability.disabled=!selected;
    ability.textContent=step===1?(armed?'스캔 준비됨 · 영역 선택':'퀸 스캔'):(armed?'저격 준비됨 · 왕 선택':'비숍 저격');
    modal.querySelector('#learnSuccess').hidden=step!==3;
    const pieces=[{t:'N',o:'W',r:step===0?6:4,c:step===0?2:1},{t:'Q',o:'W',r:6,c:4},{t:'B',o:'W',r:5,c:2},{t:'P',o:'B',r:2,c:1}];
    if(step<3)pieces.push({t:'K',o:'B',r:1,c:5});
    const own=step===0?[6,2]:step===1?[6,4]:[5,2];
    const active=document.activeElement, activeCell=board.contains(active)?active?.dataset?.cell:null;
    board.replaceChildren();
    for(let r=0;r<8;r++)for(let c=0;c<8;c++){
      const visible=pieces.some(p=>p.o==='W'&&Math.max(Math.abs(r-p.r),Math.abs(c-p.c))<=(p.t==='N'?3:1))||(step>=2&&r>=1&&r<=2&&c>=5&&c<=6);
      const p=pieces.find(p=>p.r===r&&p.c===c&&visible);
      const el=document.createElement('button');el.type='button';el.dataset.cell=`${r},${c}`;el.className=`learn-cell ${(r+c)%2?'dark':'light'} ${visible?'':'fog'}`;
      el.setAttribute('aria-label',`${String.fromCharCode(65+c)}${8-r} ${p?(p.o==='W'?'내 ':'적 ')+({N:'나이트',Q:'퀸',B:'비숍',P:'폰',K:'왕'}[p.t]):visible?'빈 칸':'안개'}`);
      if(step<3&&r===own[0]&&c===own[1])el.classList.add(selected?'chosen':'piece-hint');
      if(step===0&&selected&&r===4&&c===1){el.classList.add('move-target');el.setAttribute('aria-label',el.getAttribute('aria-label')+' 이동 목표');}
      if(step===1&&armed&&r>=1&&r<=2&&c>=5&&c<=6){el.classList.add('scan-target');el.setAttribute('aria-label',el.getAttribute('aria-label')+' 스캔 목표');}
      if(step===2&&r===1&&c===5)el.classList.add('king-target');
      if(p){const img=document.createElement('img');img.src=pieceSrc(p.t,p.o);img.alt='';img.draggable=false;el.appendChild(img);}
      el.onclick=()=>click(r,c);board.appendChild(el);
    }
    if(activeCell)board.querySelector(`[data-cell="${activeCell}"]`)?.focus();
  }
  return {init,open};
})();
