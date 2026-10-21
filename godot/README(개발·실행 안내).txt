Fog Chess — Godot 개발 클라이언트
================================

다른 Windows PC에서 개발하기
--------------------------
Git과 Python 3.12 이상을 설치하고 새 터미널에서 다음 순서로 실행합니다.
  git clone --branch codex/godot-development https://github.com/mcw9829-dotcom/fogchess.git
  cd fogchess
  python setup_godot_runtime.py
  .\start-dev.ps1

처음에는 Godot 편집기에서 리소스 가져오기가 끝날 때까지 기다린 뒤 F5로 실행합니다.
이후에는 .\start-dev.ps1 -Play로 게임을 바로 실행할 수 있습니다.

setup_godot_runtime.py는 공식 Godot 4.7.1 Windows 실행 파일을 다운로드하고
공식 SHA-512 체크섬을 검증하여 .dev-data/tools/ 안에 설치합니다.
직접 설치한 Godot을 사용하려면 start-dev.ps1 -GodotPath <실행 파일 경로>를 지정합니다.
Godot 편집기에서 godot/project.godot을 가져와 열어도 됩니다.
서버에는 추가 Python 패키지가 필요하지 않습니다. 회귀 검사를 하려면:
  python -m venv .dev-data/test-venv
  .\.dev-data\test-venv\Scripts\python.exe -m pip install -r requirements-dev.txt
  .\.dev-data\test-venv\Scripts\python.exe -m pytest -q

작업 전 git pull, 작업 후 검토한 파일을 git add → git commit → git push 합니다.
Godot 소스·기물·지형·폰트·음원·라이선스는 Git에 포함합니다.
.dev-data/, .godot/, Web 빌드, 로컬 DB, .env, Godot 로그인 설정은 포함하지 않습니다.
따라서 새 PC의 테스트 DB는 처음 실행할 때 새로 생성됩니다.
Fly.io 회원/전적 DB를 개발 PC에 복사할 필요는 없습니다.
웹 빌드는 별도로 Godot Web 내보내기 템플릿을 설치하고 prepare_release.py를 실행합니다.
현재 CI의 웹 내보내기는 Godot 4.7.2와 일치하는 템플릿을 사용합니다.
네이티브 채팅의 한글 IME 문제는 개선 예정 사항으로 남아 있습니다.

실행
----
개발용 저장소 루트에서 PowerShell:
  .\start-dev.ps1              개발 서버 + Godot 편집기
  .\start-dev.ps1 -Play        개발 서버 + 게임 실행
  .\start-dev.ps1 -ServerOnly  개발 서버만 실행

편집기가 이미 열려 있다면 서버 실행 후 F5를 누릅니다.
기본 주소: http://127.0.0.1:7556
서버 수동 실행: python dev_server.py
DB: .dev-data/fogchess-dev.db (자동 생성, Git/Docker 제외)
로그: .dev-data/server.log, .dev-data/server-error.log
개발 서버는 창을 닫아도 실행 상태를 유지합니다. 종료: stop-dev.ps1
기존 server.py와 fogchess.db, Fly.io 운영 환경은 변경하지 않습니다.

구현
----
- 기존 Python 서버의 지형·시야·합법수·능력·타이머·봇·매칭·레이팅을 사용합니다.
- Godot에 게임 규칙을 별도로 복제하지 않습니다.
- 실제 방 생성/참가, AI 3단계, 자유 연습, 배치/교환/기본/랜덤/준비.
- 클릭/드래그 이동, 저격, 돌파 사격, 스캔, 승격, 기권, 재대결.
- 플레이어별 안개, 흑 시점 회전, 혼자 연습 안개 해제, 시계와 결과/기록.
- 우클릭 원/화살표, 부쉬 움직임, 시야 열림 효과, 공격/스캔 이펙트.
- 회원가입/로그인/복구/닉네임·비밀번호 변경/로그아웃, 순위/최근 전적.
- 랭크 매칭/수락/취소, 패치노트, 피드백, 규칙·기물 설명.
- 효과음/배경음악/볼륨/밝은 UI/색약 모드/이펙트 설정.
- 세션·방 토큰·설정은 Godot user://client.cfg에 서버 주소별로 저장됩니다.
  비밀번호/복구 코드는 저장하지 않습니다. 다른 서버로 바꿀 때 토큰을 재사용하지 않습니다.

기존 웹과 차이
--------------
HTML/CSS 화면을 그대로 변환한 것이 아니라 Godot Control로 다시 구성했습니다.
기존 기물 SVG는 변경 없이 복사했습니다. 사운드는 Godot용으로 새로 합성합니다.
웹의 4개 슬라이드 인트로와 6개 기물 안내 장면·타이밍을 Godot으로 이식했습니다.
왕 찾기 미션은 로컬 고정 연습판이며 진행 상황을 저장합니다.
최근 전적 목록과 시간순 레이팅 그래프를 제공합니다.
관리자는 설정 → 관리자 또는 /admin으로 Godot에서 실행합니다. 기존 웹은 /admin-classic에 남겨 둡니다.
맵 생성과 규칙은 기존 코드 기준이며, 지형을 파괴하는 등의 새 규칙은 추가하지 않았습니다.

웹 빌드
-------
Compatibility + GDScript, Web 프리셋은 단일 스레드입니다.
Godot 내보내기에서 Web을 선택하면 godot/build/web/index.html에 빌드됩니다.
빌드 후 http://127.0.0.1:7556/godot/ 로 접속합니다.
웹 클라이언트는 현재 접속 주소의 API에 연결합니다(동일 출처).
기본 개발 서버는 localhost에만 열립니다. LAN 테스트가 필요할 때만
FOG_DEV_HOST=0.0.0.0 환경변수를 지정하고 클라이언트에 해당 PC의 IP를 입력하세요.
웹 환경의 백그라운드 탭 정지/모바일 성능은 추가 실기기 검증이 필요합니다.

개발 구조
---------
main(게임 시작·기능 연결).gd     화면 구성, 계정/매칭, 게임 흐름
board(보드·기물·이동 연출).gd    서버 뷰를 그리는 보드, 입력/주석/지형/이펙트
net(서버 요청·응답).gd      비동기 HTTP, JSON/오류 처리
audio(배경음·효과음).gd    합성 효과음/배경음악
../dev_server.py  격리된 DB/포트와 로컬 웹 빌드 제공
../run_godot_smoke.py + tests/smoke.gd  실제 클라이언트와 HTTP 서버 통합 검증

검증 명령
---------
python -m pytest -q
python run_godot_smoke.py
python run_godot_smoke.py --capture  실제 렌더 화면을 tests/*.png에 저장
통합 테스트는 임시 DB와 임의 localhost 포트를 사용합니다. 테스트 전용 fixture
엔드포인트는 테스트 프로세스 안에만 있으며 개발/운영 서버에는 없습니다.

브랜치: codex/godot-development. 자동 배포 대상인 main/master에 푸시하지 않습니다.
기존 미커밋 웹 튜토리얼 변경도 이 worktree에 보존되어 있습니다.
기준 커밋 785b5b1은 실제 Fly.io 배포 커밋과 대조하지 않았습니다.

크레딧
------
Godot Engine: https://godotengine.org/license/ (MIT)
체스 기물: 기존 프로젝트의 Lichess/cburnett SVG 자산 유지.
한글 폰트: Noto Sans KR, Google Fonts (SIL Open Font License 1.1).
원본/라이선스: https://github.com/google/fonts/tree/main/ofl/notosanskr
폰트 라이선스 전문은 fonts/OFL.txt에 포함되어 있습니다.


2026-10-14 · 원본 웹 UI 이식
- style.css의 갈색 패널/우드 보드/골드 강조색을 Godot Theme에 적용.
- 좌측 메뉴, 실제 서버 리더보드, 설명이 있는 모드 카드, 난이도/친구 참가 창.
- 대국 정보·조작·기록 카드와 턴 배너, 내 차례 보드 테두리.
- 원본 기물 SVG 유지. game.js의 숲 2종·좌표별 부쉬 144종 SVG를 terrain/으로 추출.
- 강의 물결·연결된 물가, 안개, 부쉬의 기물 앞 잎, 이동 점/잡기 링, 저격·스캔 연출.
- 좁은 화면은 메뉴와 리더보드를 세로 배치하고 대국 패널을 보드 아래에 표시.
- Noto Sans KR의 가변 굵기를 Godot 정수 OpenType 태그로 지정해 가는 글꼴 문제 수정.
검증: python run_godot_smoke.py --capture (33개 기능 검사 및 데스크톱/모바일 폭 렌더링).
원본 웹 화면의 디자인/흐름을 재구성한 버전이며 HTML/CSS를 그대로 실행하는 방식은 아닙니다.
이 단계 이후 파티클/음향 후속 이식은 아래 최신 항목 참조.

2026-10-14 · 운영판 실제 브라우저 대조 후 재작업
세부 변경과 남아 있는 차이는 UI_COMPARISON(원본 UI 비교 기록).txt 참조.
검증: 기능/화면 전환 36개 검사 통과. 데스크톱·모바일 폭 렌더링과 실제 웹 클릭 확인.


2026-10-14 · 원본 파티클·음향·관리 폼 후속 이식
- 설정 → 이펙트 미리보기에서 원본 8종을 재생할 수 있습니다.
- 11종 효과음과 원본 화음/LFO 배경음악을 포함했습니다. 음원 재생성은 루트의 build_audio.py.
- 프로필의 티어/전적/변경 폼, 비밀번호 규칙/확인, 복구 코드 흐름, 피드백 4분류/1000자 입력을 이식했습니다.
- 기능·폼 제출·연출·모바일 크기 변경을 포함한 실제 엔진 검사 78개 통과.
- 운영 원본 검증 방법과 남은 렌더링 차이는 UI_COMPARISON(원본 UI 비교 기록).txt에 기록했습니다.


2026-10-14 · 남은 원본 UI/UX 후속 이식
- 배포판 안내 데이터/타임라인, 시스템 이모지, Roboto 폰트, 매칭·종료 상태별 화면.
- 패치노트 접기, 상세 레이팅 표와 봇 상한, 44px 전적 그래프, 버튼 물결.
- 101개 엔진 검사 통과, 데스크톱/모바일 캡처 및 Web 실행 확인.
- original_scenes(원본 시연 데이터).json: 배포 game.js에서 추출한 기존 프로젝트 소유 안내 데이터.
- fonts/Roboto.ttf: https://github.com/google/fonts/tree/main/ofl/roboto
  SIL OFL 1.1 전문: fonts/Roboto-OFL.txt. 시스템 폰트 파일은 배포에 포함하지 않음.
- 최신 완료 범위와 플랫폼 차이는 UI_COMPARISON(원본 UI 비교 기록).txt 첫 항목 참조.


2026-10-16 · 개발/운영 공통 Godot Web 준비
- Python 서버/계정 DB 유지, Godot 클라이언트를 개발과 배포에서 공통 사용.
- 관리자 화면과 초대 링크 이식. 배포 호스트/Docker/Fly/GitHub 빌드 절차 연결.
- Godot 112개(캡처/headless), 규칙 88개, 호스트 7개 검사 통과.
- 로컬 Web 및 관리자 진입 검증, 운영 배포는 하지 않음.
- 상세 절차와 검증 한계: DEPLOYMENT(배포 안내).txt, UI_COMPARISON(원본 UI 비교 기록).txt 최신 항목 참조.


2026-10-16 개발 UI 개선 (Fly 배포 없음)
- 대국 중 전역 메뉴 접기, 보드 위 차례/시간/턴 표시, 간결한 플레이어 표시.
- 기물 클릭 시 46px 공격/고유능력/이동 아이콘이 기물에서 펼쳐짐.
- 펼침 280ms ease-out/back, 닫힘 160ms 가속, 흰색 hover/focus 테두리.
- 보드 가장자리 반전/보정, 비활성 능력 표시, Esc/우클릭/재클릭 취소.
- 공격은 서버의 기존 합법수 중 보이는 적 포획; 드래그 이동 유지.
- 킬로그: 공격자/대상/방식. 상대 생존 총수는 서버값, 종류별은 기본 편성-처치 추정(승격 미반영).
- 부쉬 속 아군 SVG를 선명하게 표시하고 은폐 표식 추가.
- 이펙트 설정 OFF일 때 메뉴 애니메이션도 즉시 전환.
- 개발용 임시 DB의 실제 HTTP 회귀 및 PC/모바일 캡처 확인. 운영 DB/배포 변경 없음.

2026-10-16 이동/전투 연출 개선 (개발 전용)
- 확인된 내 이동: 240ms 가감속, 나이트 280ms 도약, 도착 후 착지 파동.
- 포획 타격/효과음을 도착 시점에 맞춤, 저격 반동/탄선/명중 분리.
- 돌파 연속 충격은 유지하고 연기를 줄여 보드 가독성 개선.
- 스캔 대상 칸 모서리 프레임과 레이더 파동.
- 상대 발사 위치는 서버가 공개하지 않으므로 추측 탄선/반동을 만들지 않음.
- 안개/방/시점 전환에서 잔류 이동 스프라이트 정리. 이펙트 OFF 및 reduced-motion 지원.
- 연출 전용 검사: Godot --script res://tests/motion.gd (선택 -- --capture).
