extends Node
## Presentation and touch confirmation only. The existing action path owns legality.
const Badge = preload("res://status_badge(공통 상태 배지).gd")
var app
var footer: PanelContainer
var footer_label: Label
var ready_action: Button
var confirm: Button
var cancel: Button
var desktop_hint: Label
var mobile_hint: Label
var status_icons: Array = []
var pending := Vector2i(-1,-1)
var pending_context := ""
var palette_key := ""

func _init(context: Control) -> void:
	app = context

func build(root: VBoxContainer) -> void:
	footer = PanelContainer.new()
	footer.name = "MobilePrimaryAction"
	root.add_child(footer)
	root.move_child(footer,app.page_scroll.get_index()+1)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	footer.add_child(column)
	footer_label = app._label(column,"",12)
	footer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	footer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	ready_action = app._button(row,"준비 완료",_ready_pressed,"primary")
	ready_action.name = "MobileReady"
	cancel = app._button(row,"취소",clear_pending)
	cancel.name = "CancelTouchAim"
	confirm = app._button(row,"대상 선택",commit,"primary")
	confirm.name = "ConfirmTouchAim"
	for button in [ready_action,cancel,confirm]:
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.hide()
	desktop_hint = app._label(app.action_hint.get_parent(),"",12)
	desktop_hint.name = "TacticalReadout"
	desktop_hint.get_parent().move_child(desktop_hint,app.action_hint.get_index()+1)
	mobile_hint = app._label(app.match_ui.mobile_status.get_parent(),"",12)
	mobile_hint.name = "MobileTacticalReadout"
	for label in [desktop_hint,mobile_hint]:
		label.hide()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 1
	for header in [app.selection_icon.get_parent(),app.match_ui.mobile_title.get_parent()]:
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation",2)
		header.add_child(icons)
		header.move_child(icons,header.get_child_count()-3)
		for kind in ["exposure","reload"]:
			var glyph := Control.new()
			glyph.custom_minimum_size = Vector2(20,24)
			glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glyph.set_meta("status_kind",kind)
			glyph.draw.connect(_draw_status.bind(glyph,kind))
			icons.add_child(glyph)
			status_icons.append(glyph)
	app.board.aim_previewed.connect(preview)
	app.board.aim_preview_cancelled.connect(clear_pending)
	app.game.visibility_changed.connect(clear_pending)
	refresh()

func _draw_status(glyph: Control, kind: String) -> void:
	if kind=="exposure": Badge.exposure(glyph,glyph.size*.5,48)
	else: Badge.draw_reload(glyph,glyph.size*.5,48)

func eligible() -> bool:
	return app.game.visible and app.split.vertical and app.seat!="spectator" and not app.replay.active

func can_aim() -> bool:
	return eligible() and app.view.get("phase")=="play" and app.view.get("turn")==app.view.get("yourColor") and not app.selection.is_empty() and app.mode in ["scan","fire","barrage"] and not app.busy and not app.game_session.awaiting_state and not app.view.get("promote")

func context_key() -> String:
	return str([app.room,app.generation,app.view.get("turnCount"),app.view.get("turn"),app.view.get("yourColor"),app.selection.get("id"),app.mode,app.board.flip])

func preview(cell: Vector2i) -> void:
	if not can_aim() or cell.x<0:
		clear_pending()
		return
	pending = cell
	pending_context = context_key()
	app.board.hover = cell
	app.board.touch_aim_locked = true
	refresh()

func clear_pending() -> void:
	pending = Vector2i(-1,-1)
	pending_context = ""
	if is_instance_valid(app.board):
		if app.board.touch_aim_locked: app.board.hover = Vector2i(-1,-1)
		app.board.touch_aim_locked = false
		app.board.aim_finger = -1

func commit() -> void:
	if not can_aim() or pending_context!=context_key() or not app.board.contains(app.board.targets,pending):
		clear_pending()
		return
	var cell := pending
	clear_pending()
	app.board.hover = cell
	# Only this explicit button sends the existing action; raw invalid cells never clamp into a shot.
	app.board.targeting._on_target_pressed(cell)
	await app._tap(cell)

func _ready_pressed() -> void:
	if not eligible() or app.view.get("phase")!="setup" or app.busy or app.game_session.awaiting_state: return
	await app._act({"type":"ready","value":not app.view.get("ready",false)})

func coordinate(cell: Vector2i) -> String:
	return "%s%d" % [String.chr(97+cell.y),cell.x+1]

func tactical_text() -> String:
	if app.selection.is_empty() or app.mode not in ["scan","barrage"] or app.board.hover.x<0 or app.board.hover==app.board.selected: return ""
	var target = app.board.targeting
	if app.mode=="barrage":
		var count: int = target.friendly_in_lane(app.board.hover).size()
		return "△ 아군 %d기 · 사격선 안" % count if count>0 else ""
	# Never label a clamped preview as the committed scan location.
	if not app.board.contains(app.board.targets,app.board.hover): return ""
	var cells: Dictionary = target.scan_area(app.board.hover)
	var end: Vector2i = app.board.hover
	for cell: Vector2i in cells:
		end.x = maxi(end.x,cell.x)
		end.y = maxi(end.y,cell.y)
	return "%s%s · %d칸 감시" % [coordinate(app.board.hover),"–"+coordinate(end) if end!=app.board.hover else "",cells.size()]

func refresh() -> void:
	if not is_instance_valid(footer): return
	var setup: bool = eligible() and app.view.get("phase")=="setup"
	var aiming := can_aim()
	app.board.touch_aim_enabled = aiming
	if not aiming or (not pending_context.is_empty() and pending_context!=context_key()): clear_pending()
	var show_aim: bool = aiming and pending.x>=0
	footer.visible = setup or show_aim
	ready_action.visible = setup
	cancel.visible = show_aim
	confirm.visible = show_aim
	if setup:
		var prepared: bool = app.view.get("ready",false)
		ready_action.text = "준비 취소" if prepared else "준비 완료"
		ready_action.disabled = app.ready_button.disabled or app.busy or app.game_session.awaiting_state
		footer_label.text = ("상대 준비를 기다려요" if app.view.get("bothJoined",false) else "상대 접속을 기다려요") if prepared else "배치를 마쳤다면 준비 완료"
		app.ready_button.hide()
	elif app.view.get("phase")=="setup" and not eligible() and app.seat!="spectator":
		app.ready_button.show()
	if show_aim:
		var valid: bool = app.board.contains(app.board.targets,pending)
		confirm.disabled = not valid
		confirm.text = app.game_ux.action_name(app.mode)+" 실행" if valid else "대상 선택"
		footer_label.text = "%s · %s" % [coordinate(pending),"미리보기" if valid else "범위 표시 확인"]
	var text := tactical_text() if app.game.visible and app.view.get("phase")=="play" else ""
	for label in [desktop_hint,mobile_hint]:
		if label.text!=text: label.text = text
		label.visible = not text.is_empty()
	var exposed := false
	for entry in app.view.get("exposed",[]):
		if entry.get("pid")==app.selection.get("id") and not app.selection.is_empty(): exposed = true
	for glyph in status_icons:
		glyph.visible = exposed if glyph.get_meta("status_kind")=="exposure" else (not app.selection.is_empty() and app.moves.get("reloading",false))
	var colors: Dictionary = app.ui_components._palette()
	var key := str(colors)
	if key!=palette_key:
		palette_key = key
		footer.add_theme_stylebox_override("panel",app.match_ui._surface(colors.surface,10,12))
		for label in [footer_label,desktop_hint,mobile_hint]: label.add_theme_color_override("font_color",colors.text)

func _process(_delta: float) -> void:
	refresh()

