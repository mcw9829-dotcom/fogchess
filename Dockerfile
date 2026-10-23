# Godot Web client and the existing authoritative Python API.
FROM python:3.13-slim
WORKDIR /app
COPY server.py web_server.py accounts.py bot.py bot_worker.py config.py game_map.py matchmaking.py pieces.py spectator.py replays.py match_social.py security.py ./
COPY web/ ./web/
COPY 패치노트.txt ./
COPY godot/build/web/ ./godot/build/web/
RUN test -s godot/build/web/index.wasm && test -s godot/build/web/index.pck
ENV PORT=8080 FOG_CLIENT=godot
EXPOSE 8080
CMD ["python", "web_server.py"]
