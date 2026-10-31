# Fog Chess · 안개전장 체스

현재 개발 버전: **1.58.5** (`config.py`의 `APP_VERSION`).
Godot이 화면·입력·연출을, Python 서버가 규칙·봇·계정·매칭·전적을 담당합니다.
이 저장소에는 개발 소스·에셋·테스트·설명 문서만 포함합니다. 운영 DB와 인증 정보는 포함하지 않습니다.

## 개발 시작

Python 3.12 이상과 Godot을 준비합니다. 네이티브 개발은 Godot 4.7.1 이상,
기존 Web 빌드는 Godot 4.7.2와 같은 버전의 Web 내보내기 템플릿을 사용합니다.

```powershell
git clone https://github.com/mcw9829-dotcom/fogchess.git
cd fogchess
python -m venv .dev-data/test-venv
.\.dev-data\test-venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\start-dev.ps1 -ServerOnly
```

Godot에서 `godot/project.godot`을 열고 리소스 가져오기가 끝난 뒤 F5를 누릅니다.
`start-dev.ps1 -GodotPath <Godot 실행 파일>`로 편집기를 함께 열거나 `-Play`로 바로 실행할 수도 있습니다.
종료는 `.\stop-dev.ps1`입니다. Python 서버 자체에는 외부 패키지가 필요하지 않습니다.
기본 개발 API 주소는 `http://127.0.0.1:7556`이며 Web 화면은 내보내기 후 `/godot/`에서 열립니다.

DB 파일을 별도로 받을 필요가 없습니다. 첫 실행/DB 접근 시 `.dev-data/`에 새 개발 DB와 스키마가 자동 생성됩니다.
환경변수 이름과 안전한 로컬 경로는 `.env.example`을 참고하세요. `.env` 자동 로딩 기능은 없으므로 필요한 변수는 프로세스 환경에 지정합니다.

## 폴더와 코드

| 위치 | 역할 |
| --- | --- |
| `godot/` | 씬·스크립트·UI·기물·지형·폰트·음향과 라이선스 |
| `godot/features/` | 로그인·매칭·대국·채팅·관전·리플레이 |
| `web/` | 기존 HTML 게임과 관리자 화면. `/classic` 예비 경로 |
| `tests/`, `godot/tests/` | 서버 회귀 검사 및 실제 Godot UI 검사 |
| `tools/` | 엔진 탐색·설치, 음원 생성, Web 빌드 도구 |
| `docs/godot/` | 구조·개발·배포·관전·리플레이 설명 |
| `server.py`, `web_server.py` | 대국 API 및 Web 자산 제공 |
| `accounts.py`, `account_lifecycle.py` | 계정·세션·전적·계정 관리 |
| `admin_ops.py`, `admin_http.py`, `security.py` | 관리자·감사 기록·요청 제한 |
| `config.py`, `패치노트.txt` | 버전·게임 설정·변경 이력 |

자세한 구조는 [코드 구조 안내](<docs/godot/CODE_STRUCTURE(코드 구조 안내).txt>),
관리자 기능은 [운영 안내](docs/ADMIN_OPERATIONS.txt)를 참고하세요.
로컬 인수인계, 원본 피드백, QA 캡처와 운영 점검 결과는 공개 저장소에서 제외합니다.

## 검사와 Web 빌드

```powershell
.\.dev-data\test-venv\Scripts\python.exe -m pytest -q
python tests/run_godot_smoke.py
python tests/test_web_host.py
python tools/prepare_release.py --godot <Godot 실행 파일>
```

검사는 임시 DB를 사용합니다. `godot/build/web/`와 엔진 캐시는 Git에 넣지 않고 재생성합니다.
Godot 리소스 참조용 `.uid`, `.import`와 에셋 라이선스는 유지합니다.

## 배포와 민감 정보

GitHub 업로드와 운영 배포를 구분하기 위해 Fly Deploy 워크플로는 **수동 실행(`workflow_dispatch`)**입니다.
GitHub Actions의 Run workflow 또는 검증된 Web 빌드로 별도 배포합니다. 실제 배포 토큰은 Actions secrets에만 설정합니다.
기존 운영 DB는 Fly 볼륨에서 유지하며, 소스 업로드가 DB를 비우거나 교체하지 않습니다.

[민감 정보 관리 안내](docs/SENSITIVE_FILES.txt)에 제외 대상과 점검 방법을 정리했습니다.
`git add -f`로 제외 규칙을 우회하지 마세요. 테스트 소스의 고정 가짜 자격 증명은 운영 인증 정보가 아닙니다.
