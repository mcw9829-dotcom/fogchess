extends RefCounted
## Spectator entry, delayed viewing, and live audience presence.
var app
var flipped := false
var audience: Label
var waiting: Label
var flip_button: Button
var last_count := -1
var presence_row: HBoxContainer

func _init(context: Control) -> void:
	app = context

func build() -> void:
	presence_row = HBoxContainer.new()
	app.ui_shell.presence_slot.add_child(presence_row)
	var eye = TextureRect.new()
	eye.texture = load("res://audience(관전자 눈 아이콘).svg")
	eye.custom_minimum_size = Vector2(20,20)
	eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	presence_row.add_child(eye)
	audience = app._label(presence_row,"관전자 0명",13)
	audience.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	audience.autowrap_mode = TextServer.AUTOWRAP_OFF
	waiting = app._label(app.game_left,"",20)
	waiting.theme_type_variation = "MatchWaiting"
	waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	waiting.custom_minimum_size.y = 260
	waiting.hide()
	app.game_left.move_child(waiting,app.board.get_index()+1)
	flip_button = app._button(app.ui_shell.self_row,"보드 뒤집기",func():
		flipped = not flipped
		render())
	flip_button.hide()

func menu() -> void:
	var box: VBoxContainer = app._subscreen("대국 관전","방 코드로 입장 · 전체 보드를 3분 늦게 중계합니다.")
	var field: LineEdit = app._field(box,"관전할 방 코드")
	var enter = func():
		if app.busy: return
		var code = field.text.strip_edges().to_upper()
		if code.is_empty(): app._message("방 코드를 입력하세요."); return
		app.busy = true
		var data: Dictionary = await app.api.request("/watch/join",{"room":code})
		app.busy = false
		if not data.has("room"): app._report(data); return
		app._enter(data)
		await app._poll()
	app._button(box,"관전 시작",enter)
	field.text_submitted.connect(func(_text): enter.call())
	app._button(box,"← 뒤로",app._navigation_home)
	field.grab_focus()

func render() -> void:
	app.ui_shell.set_audience_visible(not app.replay.active)
	var count = int(app.view.get("spectatorCount",0))
	audience.text = "관전자 %d명" % count
	if count>last_count and last_count>=0 and app.seat!="spectator":
		if last_count==0: app._message("누군가 대국을 관전하기 시작했습니다.")
		if app.board.effects:
			audience.modulate = Color("#e6c56b")
			app.create_tween().tween_property(audience,"modulate",Color.WHITE,.6)
	last_count = count
	var watching: bool = app.seat=="spectator"
	var pending: bool = watching and app.view.get("spectatorWaiting",false)
	waiting.visible = pending
	flip_button.visible = watching and not pending
	app.board.visible = not pending
	if not watching: return
	app.board.set_view(app.view,flipped)
	app.state_label.text = "3분 지연 중계 · "+("공개 대기" if pending else ("대국 종료" if app.view.get("phase")=="over" else ("백 차례" if app.view.get("turn")=="W" else "흑 차례")))
	app.warning_label.hide()
	app.status_label.text = "관전 중 · 방 "+app.room
	var names: Dictionary = app.view.get("names",{})
	app.opponent_line.text = "흑 · "+str(names.get("B","공개 대기" if pending else "플레이어"))
	app.self_line.text = "백 · "+str(names.get("W","공개 대기" if pending else "플레이어"))
	if flipped:
		var top: String = app.opponent_line.text
		app.opponent_line.text = app.self_line.text
		app.self_line.text = top
	app.opponent_line.tooltip_text = app.opponent_line.text
	app.self_line.tooltip_text = app.self_line.text
	app.coach_label.text = "기물 클릭: 정보 확인 · 전체 화면과 기록은 3분 전 시점입니다."
	app.utility_actions.show()
	app.setup_controls.hide()
	app.resign_button.hide()
	app.over_controls.hide()
	var left = int(app.view.get("waitSeconds",180))
	waiting.text = "중계가 곧 시작됩니다\n\n%02d:%02d\n\n첫 화면 공개까지\n보드와 기록이 함께 공개됩니다." % [int(left/60),left%60]
	app.enemy_counts.show()
	app.enemy_icons.show()
	app.enemy_counts.text = "양쪽이 잡은 기물"
	# The player renderer rebuilds this container only when its feed signature changes.
	var trophies: Dictionary = app.view.get("capturedBy",{})
	var signature = str(trophies)
	if app.enemy_icons.get_meta("watch_signature","!")!=signature:
		app.enemy_icons.set_meta("watch_signature",signature)
		for child in app.enemy_icons.get_children():
			app.enemy_icons.remove_child(child)
			child.queue_free()
		for side in ["W","B"]:
			var column = VBoxContainer.new()
			app.enemy_icons.add_child(column)
			column.custom_minimum_size.x = 190
			app._label(column,("백" if side=="W" else "흑")+"이 잡음",12)
			var row = HFlowContainer.new()
			column.add_child(row)
			row.custom_minimum_size.x = 190
			var items: Array = trophies.get(side,[])
			if items.count("P")>0:
				var group = HBoxContainer.new()
				row.add_child(group)
				var pawn = app._feed_icon(group,"P","B" if side=="W" else "W")
				pawn.custom_minimum_size = Vector2(20,20)
				pawn.get_parent().custom_minimum_size = Vector2(24,24)
				var count_label = app._label(group,"×%d" % items.count("P"),12)
				count_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			for kind in ["N","B","R","Q","K"]:
				for n in range(items.count(kind)):
					var icon = app._feed_icon(row,kind,"B" if side=="W" else "W")
					icon.custom_minimum_size = Vector2(36,36)
			if items.is_empty(): app._label(row,"없음",12)
	if app.view.get("phase")=="over":
		app.result_label.text = "무승부" if app.view.get("winner")=="draw" else ("백 승리" if app.view.get("winner")=="W" else "흑 승리")
		app.result_sub.text = "마지막 장면까지 중계가 완료되었습니다."

func inspect(cell: Vector2i) -> void:
	var p: Variant = app.board.tile(cell).get("p")
	if p is Dictionary: app._message("%s · %s · 관전 중에는 조작할 수 없습니다." % ["백" if p.o=="W" else "흑",app.NAMES.get(p.t,"기물")])

func leave() -> void:
	if app.seat=="spectator" and not app.room.is_empty():
		await app.api.request("/watch/leave",{"room":app.room,"token":app.token})
