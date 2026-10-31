extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app
var polling := false
var command_busy := false
var epoch := 0
var entering := false
var deferred_data: Dictionary = {}
var interrupted_windows: Array = []

func _init(context: Control) -> void:
	app = context

func poll() -> void:
	if not app.matching: return
	if app.session.is_empty():
		app.matching = false
		app.lobby_status.set_queue({})
		_close_popup(true)
		return
	if not deferred_data.is_empty() and not app.busy and not app.ui_motion.is_transition_busy():
		var pending := deferred_data
		deferred_data = {}
		await _match_update(pending)
	if not app.matching or polling or command_busy: return
	polling = true
	var stamp := epoch
	var session: String = app.session
	var data: Dictionary = await app.api.request("/match/status",{"session":session})
	polling = false
	if stamp==epoch and session==app.session: await _match_update(data)

func _close_popup(restore: bool) -> void:
	if is_instance_valid(app.match_window):
		app.match_window.hide()
		app.match_window.queue_free()
	app.match_window = null
	for saved in interrupted_windows:
		var window = saved.get_ref()
		if is_instance_valid(window) and not window.is_queued_for_deletion():
			if restore: window.show.call_deferred()
			else: window.queue_free()
	interrupted_windows.clear()

func _match_command(command: String) -> void:
	if command_busy or entering: return
	if command=="join" and (app.busy or app.matching): return
	if app.session.is_empty(): app._account(); app._message("랭크 매칭은 로그인 후 이용할 수 있어요."); return
	command_busy = true
	epoch += 1
	deferred_data = {}
	var session: String = app.session
	if command=="join": app.matching = true
	var data: Dictionary = await app.api.request("/match/"+command,{"session":session})
	command_busy = false
	if session!=app.session: return
	await _match_update(data)

func _match_update(data: Dictionary) -> void:
	if entering: return
	if not app._report(data):
		if not data.get("network_error",false):
			app.matching = false
			deferred_data = {}
			app.lobby_status.set_queue({})
			_close_popup(true)
		return
	var state: String = data.get("state","idle")
	if state in ["found","matched"] and (app.busy or app.ui_motion.is_transition_busy()):
		deferred_data = data
		return
	deferred_data = {}
	var previous: String = app.match_data.get("state","")
	app.match_data = data
	app.lobby_status.set_queue(data)
	if state=="waiting":
		app.matching = true
		_close_popup(true)
		if previous=="found": app._message("상대가 응답하지 않아 다시 찾는 중이에요. 연습은 계속할 수 있습니다.")
		return
	if state=="idle":
		app.matching = false
		_close_popup(true)
		if previous=="found": app._message("매칭이 종료됐어요. 하던 활동을 계속할 수 있습니다.")
		return
	if state=="matched":
		entering = true
		epoch += 1
		app.matching = false
		_close_popup(false)
		if app.replay.active: app.replay.close()
		app._enter(data)
		await app._poll()
		entering = false
		return
	app.matching = true
	if not is_instance_valid(app.match_window) or app.match_window.is_queued_for_deletion():
		for child in app.get_children():
			if child is Window and child.visible and not child.is_queued_for_deletion(): interrupted_windows.append(weakref(child))
		var pair = app._small_window("랭크 매칭",380,500)
		app.match_window = pair[0]
		app.match_box = pair[1]
		# Dismissal also leaves the queue; no invisible active matching.
		for connection in app.match_window.close_requested.get_connections(): app.match_window.close_requested.disconnect(connection.callable)
		app.match_window.close_requested.connect(func(): await app._match_command("cancel"))
		for button in app.match_box.find_children("*","Button",true,false):
			if button.text=="×":
				for connection in button.pressed.get_connections(): button.pressed.disconnect(connection.callable)
				button.pressed.connect(func(): await app._match_command("cancel"))
		app.match_body = VBoxContainer.new()
		app.match_box.add_child(app.match_body)
	var stable_data = data.duplicate(true)
	for key in ["secondsLeft","waited","window","queue"]: stable_data.erase(key)
	stable_data["botSuggested"] = int(data.get("waited",0))>=30
	var signature = str(stable_data)
	if app.match_body.get_meta("signature","")==signature:
		var counter = app.match_body.get_node_or_null("MatchCountdown")
		if is_instance_valid(counter):
			counter.text = ("상대 수락 대기 중… %d초" if data.get("accepted",false) else "%d초 안에 수락하세요") % int(data.get("secondsLeft",0)) if state=="found" else "대기 %d초 · 대기열 %d명" % [int(data.get("waited",0)),int(data.get("queue",0))]
		return
	app.match_body.set_meta("signature",signature)
	if previous!=state: app.ui_motion.pulse(app.match_body)
	app._clear_form(app.match_body)
	app._label(app.match_body,"상대를 찾았어요!" if state=="found" else ("매칭 성사!" if state=="matched" else "상대를 찾는 중…"),20).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	app._label(app.match_body,"%s · %d (%s)" % [app.me.get("name",""),int(app.me.get("rating",1000)),app.NAMES.get(app.me.get("tier","N"),"나이트")],14).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if state=="found":
		if previous!="found": app.audio.cue("yourturn")
		var versus = HBoxContainer.new()
		app.match_body.add_child(versus)
		for player in [app.me,data.opp]:
			if versus.get_child_count()>0:
				var vs_label = app._label(versus,"VS",16)
				vs_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				vs_label.custom_minimum_size.x = 30
				vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var card = VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			versus.add_child(card)
			var tier = app._tier(int(player.rating))
			var icon = TextureRect.new()
			icon.texture = load("res://pieces/Chess_%slt45.svg" % tier.to_lower())
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(46,46)
			card.add_child(icon)
			app._label(card,str(player.name),15).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			app._label(card,"%d · %s" % [int(player.rating),app.NAMES[tier]],12).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		app._label(app.match_body,"양쪽이 수락하면 현재 연습을 끝내고 랭크 대국으로 이동합니다." if app.view.get("queuePractice",false) else "양쪽이 수락하면 랭크 대국을 시작합니다.",13)
		var accepted: bool = data.get("accepted",false)
		app._label(app.match_body,("상대 수락 대기 중… %d초" if accepted else "%d초 안에 수락하세요") % int(data.get("secondsLeft",0))+(" · 상대는 수락했어요" if data.get("oppAccepted",false) else ""),13).name = "MatchCountdown"
		var row = HBoxContainer.new()
		app.match_body.add_child(row)
		var accept = app._form_action(row,"수락함" if accepted else "수락","레이팅전 시작","accept",true)
		accept.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		accept.disabled = accepted
		accept.pressed.connect(func(): await app._match_command("accept"))
		var decline = app._form_action(row,"거절","매칭 취소","decline")
		decline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		decline.pressed.connect(func(): await app._match_command("cancel"))

func _bot_menu() -> void:
	var box = app._subscreen("컴퓨터와 대국","매칭 대기용 연습 · 레이팅·전적 미반영" if app.matching else "난이도를 고르세요")
	for index in range(3):
		app._mode_card(box,["쉬움","보통","어려움"][index],["짧게 탐색하며 능력도 사용하는 상대","정찰하고 기억하며 위협을 피하는 표준 상대","몇 수 앞을 읽고 왕을 끈질기게 추적하는 강한 상대"][index],["easy","normal","hard"][index],func():
			app.level.selected = index
			await app._join({"vs_bot":true,"level":["easy","normal","hard"][index]}))
	app._button(box,"← 뒤로",app._navigation_home)

func _friend_menu() -> void:
	var box = app._subscreen("친구에게 도전","친구가 준 방 코드를 입력하세요")
	var field = app._field(box,"예: AB12",app.code_field.text)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.max_length = 8
	var join_room = func():
		app.code_field.text = field.text.strip_edges().to_upper()
		if app.code_field.text.is_empty(): app._message("방 코드를 입력하세요."); return
		await app._join({"room":app.code_field.text})
	app._mode_card(box,"방 참가","","join",join_room)
	app._button(box,"← 뒤로",app._navigation_home)
	field.text_submitted.connect(func(_value): join_room.call())
	field.grab_focus()
