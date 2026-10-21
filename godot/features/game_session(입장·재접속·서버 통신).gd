extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

func _init(context: Control) -> void:
	app = context

func _join(data: Dictionary) -> void:
	if app.busy or app.matching: return
	app.busy = true
	app._message("대국을 준비하고 있습니다…")
	data["name"] = app.guest_field.text
	data["session"] = app.session
	var response: Dictionary = await app.api.request("/join",data)
	app.busy = false
	if not response.has("room"): app._report(response); return
	app._enter(response)
	await app._poll()

func _enter(data: Dictionary) -> void:
	app.generation += 1
	app.room = str(data.room)
	app.token = str(data.token)
	app.seat = str(data.color)
	app.chat.reset()
	app.view = {}
	app.spectating.last_count = -1
	app.spectating.flipped = false
	app.last_fx = 0
	app.last_turn = -1
	app.reveal = false
	app.matching = false
	app._clear_selection()
	app.home.hide()
	app.subpage.hide()
	app.game.show()
	app._layout()
	app.page_scroll.scroll_vertical = 0
	app._nav_active("플레이")
	app._save()
	app._message(("방 %s · 전체 보드 3분 지연 관전" if app.seat=="spectator" else "방 %s · 기물을 클릭하거나 드래그해 조작하세요.") % app.room)

func _poll() -> void:
	if app.replay.active: return
	if app.polling or app.busy: return
	if app.matching:
		app.polling = true
		var stamp = app.generation
		var data: Dictionary = await app.api.request("/match/status",{"session":app.session})
		app.polling = false
		if stamp==app.generation: await app._match_update(data)
		return
	if app.room.is_empty(): return
	app.polling = true
	var stamp = app.generation
	var response: Dictionary = await app.api.request("/state?room=%s&token=%s&reveal=%s" % [app.room.uri_encode(),app.token.uri_encode(),1 if app.reveal else 0])
	app.polling = false
	if stamp!=app.generation: return
	if response.get("gone"):
		app._return_home()
		app._message("서버에서 방이 종료되었습니다. 새 대국을 시작하세요.")
		return
	if not response.has("grid"): app._report(response); return
	app._apply_state(response)

func _apply_state(data: Dictionary) -> void:
	if app.view.get("turnCount")!=data.get("turnCount") or app.view.get("phase")!=data.get("phase"):
		app._clear_selection()
	if int(data.get("turnCount",0)) < app.last_turn: app.last_fx = 0
	var next_turn = int(data.get("turnCount",0))
	var was_over: bool = app.view.get("phase")=="over"
	var could_act: bool = app.view.get("phase")=="play" and app.view.get("turn")==app.view.get("yourColor")
	if data.get("phase")=="play" and data.turn==data.yourColor and not could_act: app.audio.cue("yourturn")
	app.last_turn = next_turn
	app.view = data
	app.board.set_view(data,app.seat=="B")
	if not app.pending_fx.is_empty():
		app._effect(app.pending_fx)
		app.pending_fx = {}
	if data.get("fx") is Dictionary: app._effect(data.fx)
	if data.get("phase")=="over" and not was_over and app.seat!="spectator":
		var ending = "drawend" if data.get("winner")=="draw" else ("victory" if data.get("solo",false) or data.get("winner")==data.get("yourColor") else "defeat")
		app.audio.cue(ending)
		if app.board.effects: app.board.fx.play({"type":ending})
	app.audio.music(bool(app.prefs.get_value("settings","music",true)))
	app._render()

func _act(body: Dictionary) -> void:
	if app.replay.active: return
	if app.busy or app.room.is_empty() or app.seat=="spectator": return
	app.busy = true
	app.generation += 1
	app._update_selection_ui()
	body["room"] = app.room
	body["token"] = app.token
	var origin: Variant = null
	var moving_piece: Dictionary = app.selection.duplicate(true)
	if body.type in ["move","fire","barrage","scan"] and app.selection.get("cell") is Vector2i:
		origin = [app.selection.cell.x,app.selection.cell.y]
	var response: Dictionary = await app.api.request("/action",body)
	app.busy = false
	if response.get("ok"):
		if body.type=="rematch" and not response.get("pending"): app.last_fx = 0
		if body.type=="place": app.audio.cue("place")
		if response.get("fx") is Dictionary:
			app.pending_fx = response.fx.duplicate(true)
			if origin!=null:
				app.pending_fx["from"] = origin
				app.pending_fx["confirmed_source"] = true
				if body.type=="move":
					app.pending_fx["motion_piece"] = moving_piece
					app.pending_fx["to"] = response.fx.cells[0] if not response.fx.cells.is_empty() else [body.r,body.c]
		app._clear_selection()
		app._message("상대가 생각 중입니다." if response.get("pending") else "")
	else: app._report(response)
	await app._poll()

func _promotion() -> void:
	var pair = app._window("폰 승격")
	app.promote_window = pair[0]
	var box: VBoxContainer = pair[1]
	for connection in app.promote_window.close_requested.get_connections():
		app.promote_window.close_requested.disconnect(connection.callable)
	for button in box.find_children("*","Button",true,false):
		if button.text=="×": button.hide()
	app._label(box,"승격할 기물을 선택하세요. 시간이 끝나면 전차로 자동 승격합니다.")
	for kind in ["R","N","B"]:
		var button = app._button(box,app.NAMES[kind],func(): await app._act({"type":"promote","choice":kind}))
		button.icon = load("res://pieces/Chess_%s%st45.svg" % [kind.to_lower(),"l" if app.view.get("yourColor")=="W" else "d"])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",38)
		button.custom_minimum_size.y = 52
		if kind=="R": button.grab_focus()

func _leave_prompt() -> void:
	if app.replay.active: app.replay.close(); return
	if app.room.is_empty(): app._navigation_home(); return
	if app.busy: return
	var committed: bool = not app.view.get("solo",false) and app.view.get("phase")!="over" and app.view.get("bothJoined",false) and (app.view.get("phase")=="play" or app.view.get("match",false)) and app.seat!="spectator"
	app._confirm("지금 나가면 기권 패배로 처리됩니다." if committed else "대국을 나가 홈으로 돌아갈까요?",func():
		if committed:
			await app._act({"type":"resign"})
			if app.view.get("phase")!="over": app._message("기권 결과를 확인할 수 없어 방에 남아 있습니다."); return
		elif app.view.get("phase")=="over" and app.seat!="spectator": await app._act({"type":"rematch_decline"})
		app._return_home())

func _return_home() -> void:
	app.spectating.leave()
	app.board.show()
	app.board.fx.clear()
	app.pending_fx = {}
	app.audio.music(false)
	app.generation += 1
	app.room = ""
	app.token = ""
	app.view = {}
	app._clear_selection()
	app.game.hide()
	app.subpage.hide()
	app.home.show()
	app._layout()
	app._message("")
	app.page_scroll.scroll_vertical = 0
	app._nav_active("플레이")
	app._load_home_ranks()
	app._save()
	app._refresh_profile()

func _open_invitation(code: String) -> void:
	app.code_field.text = code.strip_edges().to_upper().left(8)
	app._friend_menu()
	app._message("초대받은 방이에요. 닉네임을 확인하고 참가하세요.")
