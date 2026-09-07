# 안개전장 체스 서버 — 파이썬 표준 라이브러리만 사용(설치할 패키지 없음)
FROM python:3.13-slim

WORKDIR /app
COPY . /app

# 서버는 config.py에서 PORT 환경변수를 읽어 0.0.0.0:$PORT 로 listen 한다.
ENV PORT=8080
EXPOSE 8080

CMD ["python", "server.py"]
