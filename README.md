# Fog Chess · 안개전장 체스

Godot으로 화면·입력·연출을 구현하고, Python 서버가 규칙·봇·계정·매칭·전적을 처리하는 게임입니다.
현재 개발의 시작점은 `godot/project.godot`과 아래 실행 명령입니다.

## 개발 실행

저장소 루트의 PowerShell에서 실행합니다.

```powershell
.\start-dev.ps1              # 개발 서버와 Godot 편집기
.\start-dev.ps1 -Play        # 개발 서버와 게임 실행
.\start-dev.ps1 -ServerOnly  # 개발 서버만 실행
.\stop-dev.ps1               # 관리 중인 개발 서버 종료
```

개발 주소는 `http://127.0.0.1:7556`입니다. 편집기에서는 F5로 게임을 실행합니다.
다른 PC의 준비 절차는 [개발·실행 안내](<docs/godot/README(개발·실행 안내).txt>)를 확인하세요.
Godot 실행 파일을 직접 지정하려면 `-GodotPath` 옵션을 사용합니다.

## 폴더 안내

| 위치 | 담당 내용 |
| --- | --- |
| `godot/` | 실제 게임 프로젝트. 씬·스크립트·기물·숲·부쉬·폰트·음향 |
| `godot/features/` | 로그인, 매칭, 대국 UI, 채팅, 관전, 리플레이 등 기능별 코드 |
| `web/` | 기존 HTML 게임과 관리자 화면, JS·CSS·이미지. `/classic` 예비 경로에서 사용 |
| `tests/` | Python 회귀 검사와 Godot 통합 검사 실행기 |
| `tools/` | Web 빌드, 음원 생성, 개발용 Godot 설치·탐색 도구 |
| `docs/godot/` | 개발·배포·UI·관전·리플레이 등 설명 문서 |
| `docs/classic/` | 이전 웹 버전의 상세 설명 |
| `docs/feedback/` | 과거 피드백 원문 |
| `QA/` | 날짜별 QA 보고서, 봇·밸런스 분석 도구와 결과 |
| `게임 구조 지도/` | 구조도 4장과 전체 검토서. `review.html`에서 열람 |
| `.dev-data/` | 로컬 개발 DB·로그·엔진·검증 자료. Git 제외 |
| `godot/.godot/`, `godot/build/` | 엔진 캐시와 Web 빌드 산출물. Git 제외 |

## 루트의 서버 코드

| 파일 | 담당 내용 |
| --- | --- |
| `dev_server.py` | 개발 전용 주소·DB를 사용하는 실행 진입점 |
| `web_server.py` | Godot Web 파일과 Python API를 함께 제공 |
| `server.py` | HTTP, 방·좌석 인증, 대국 흐름, 타이머, 정산 연결 |
| `pieces.py` | 기물 이동·공격·능력, 시야, 승패와 기보 |
| `game_map.py` | 맵 생성과 지형 정보 |
| `bot.py`, `bot_worker.py` | 난이도별 판단과 별도 프로세스에서의 봇 계산 |
| `accounts.py` | 계정, 세션, 레이팅·전적, 피드백 DB |
| `matchmaking.py`, `match_social.py` | 랭크 매칭, 채팅, 2선승 재대결 |
| `spectator.py`, `replays.py` | 3분 지연 관전, 기보·리플레이 저장과 조회 |
| `config.py`, `패치노트.txt` | 공통 게임 설정과 게임 안에서 읽는 변경 이력 |

`Dockerfile`, `fly.toml`, `Procfile`, `render.yaml`, `.github/`는 배포 설정입니다.
파일을 수정하거나 로컬 빌드를 만드는 것만으로 배포되지는 않습니다.
다만 기존 GitHub Actions는 `main`/`master` push 시 Fly 배포를 실행하므로 해당 브랜치에 반영하기 전에 확인하세요.

## 검사와 로컬 Web 빌드

```powershell
python -m pip install -r requirements-dev.txt
python -m pytest -q
python tests/run_godot_smoke.py
python tests/run_board_focus_smoke.py
python tests/run_watch_smoke.py
python tests/run_replay_smoke.py
python tests/test_web_host.py
python tools/prepare_release.py
```

검사에는 임시 DB를 사용합니다. Web 내보내기에는 Godot Web 템플릿이 필요하며,
`tools/prepare_release.py`는 빌드만 수행합니다. 실제 배포는 별도 작업입니다.
네이티브 한글 입력은 아직 개선 과제로 남아 있습니다.

## 데이터와 정리 원칙

회원·전적 DB, 비밀번호, 토큰, `.env`, 로컬 설정은 Git에 넣지 않습니다.
개발 DB는 `.dev-data/fogchess-dev.db`이며, 기존 DB 파일을 폴더 정리 목적으로 옮기거나 삭제하지 않습니다.
`web/`은 아직 예비 웹 화면에서 사용하고 있으므로 삭제 대상이 아닙니다.
`godot/`의 `.uid`, `.import`와 에셋 라이선스는 엔진 연결·출처를 보존하므로 유지합니다.

2026-10-22 폴더 정리: 실행 명령과 정적 파일 경로를 함께 갱신했습니다.
구조 지도와 날짜별 QA 보고서는 작성 당시의 파일 경로를 담은 기록입니다.
현재 위치는 이 README와 [이동 목록](<docs/폴더 정리(이동 목록).txt>)을 기준으로 확인하세요.
