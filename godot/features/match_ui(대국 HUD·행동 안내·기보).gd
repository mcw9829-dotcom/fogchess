extends RefCounted
## Board-first match presentation. Reads the existing server view; owns no rules.
var app
var chrome: HBoxContainer
var mode_label: Label
var turn_strip: ProgressBar
var turn_panel: PanelContainer
var top_sound: Button
var opponent_icon: TextureRect
var self_icon: TextureRect
var selection_position: Label
var hourglass: Control
var history_expanded := false
var history_room := ""
var history_toggle: Button
var history_summary: Label
var mobile_actions: PanelContainer
var mobile_title: Label
var mobile_instruction: Label
var mobile_status: Label
var mobile_help: Button
var mobile_cancel: Button
var exposure_summary: Label
var footer_meta: HBoxContainer

func _init(context: Control) -> void:
	app = context

func _surface(color: Color, padding: int=16, radius: int=12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,float(padding))
	return style

func card(parent: Node, title: String="") -> VBoxContainer:
	var content: VBoxContainer = app._card(parent,title)
	content.get_parent().set_meta("match_card",true)
	content.add_theme_constant_override("separation",10)
	return content

func _tool(parent: Node, icon_name: String, caption: String, callback: Callable) -> Button:
	var button: Button = app._button(parent,"",callback,"tertiary")
	button.icon = load("res://ui/icons/match-"+icon_name+".svg")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",18)
	button.custom_minimum_size = Vector2(44,44)
	button.tooltip_text = caption
	button.accessibility_name = caption
	button.set_meta("match_tool",true)
	return button

func _portrait(parent: Node) -> TextureRect:
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.custom_minimum_size = Vector2(28,30)
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func build_header() -> void:
	chrome = HBoxContainer.new()
	chrome.name = "MatchChrome"
	chrome.add_theme_constant_override("separation",14)
	chrome.custom_minimum_size.y = 42
	app.game.add_child(chrome)
	app.game.move_child(chrome,0)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation",0)
	brand.alignment = BoxContainer.ALIGNMENT_CENTER
	chrome.add_child(brand)
	app._label(brand,"안개전장",18).autowrap_mode = TextServer.AUTOWRAP_OFF
	var subtitle: Label = app._label(brand,"F O G  C H E S S",10)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.set_meta("match_muted",true)
	mode_label = app._label(chrome,"",12)
	mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mode_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	mode_label.set_meta("match_muted",true)
	_tool(chrome,"help","보드 표시의 뜻을 확인합니다.",app._board_help)
	top_sound = _tool(chrome,"volume","효과음 켜기 / 끄기",app._toggle_sound)
	_tool(chrome,"menu","대국 메뉴",app._game_menu)
	turn_panel = PanelContainer.new()
	turn_panel.name = "MatchHeader"
	app.game_left.add_child(turn_panel)
	app.ui_shell.match_header = turn_panel
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",0)
	turn_panel.add_child(stack)
	var padding := MarginContainer.new()
	for edge in ["left","right"]: padding.add_theme_constant_override("margin_"+edge,16)
	for edge in ["top","bottom"]: padding.add_theme_constant_override("margin_"+edge,6)
	stack.add_child(padding)
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation",12)
	padding.add_child(hud)
	app.ui_shell.state_group = VBoxContainer.new()
	app.ui_shell.state_group.alignment = BoxContainer.ALIGNMENT_CENTER
	app.ui_shell.state_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.ui_shell.state_group.add_theme_constant_override("separation",3)
	hud.add_child(app.ui_shell.state_group)
	app.state_label = app._label(app.ui_shell.state_group,"",16)
	app.state_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.state_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Warning and move count share one reserved subtitle row.
	var subtitle_slot := Control.new()
	subtitle_slot.custom_minimum_size.y = 17
	app.ui_shell.state_group.add_child(subtitle_slot)
	app.turn_meta = app._label(subtitle_slot,"",11)
	app.turn_meta.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.turn_meta.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.turn_meta.set_meta("match_muted",true)
	app.warning_label = app._label(subtitle_slot,"",12)
	app.warning_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.warning_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.warning_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app.warning_label.hide()
	app.ui_shell.clock_cell = MarginContainer.new()
	app.ui_shell.clock_cell.custom_minimum_size.x = 76
	hud.add_child(app.ui_shell.clock_cell)
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation",6)
	app.ui_shell.clock_cell.add_child(clock_row)
	hourglass = preload("res://hourglass(턴 타이머 모래시계).gd").new()
	hourglass.name = "TurnHourglass"
	clock_row.add_child(hourglass)
	app.clock_label = app._label(clock_row,"",30)
	app.clock_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.clock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app.clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	turn_strip = ProgressBar.new()
	turn_strip.show_percentage = false
	turn_strip.custom_minimum_size.y = 3
	turn_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(turn_strip)
	var opponent := HBoxContainer.new()
	opponent.name = "OpponentIdentity"
	opponent.custom_minimum_size.y = 30
	opponent.add_theme_constant_override("separation",8)
	app.game_left.add_child(opponent)
	opponent_icon = _portrait(opponent)
	app.opponent_line = app._label(opponent,"",13)
	app.opponent_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app.opponent_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.opponent_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app.ui_shell.opponent_rating = app._label(opponent,"",12)
	app.ui_shell.opponent_rating.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.ui_shell.opponent_rating.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app.ui_shell.opponent_rating.size_flags_horizontal = Control.SIZE_SHRINK_END
	app.ui_shell.opponent_rating.set_meta("match_muted",true)
	app.series_label = app._label(opponent,"",12)
	app.series_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.series_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	app.series_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	app.series_label.hide()

func build_footer() -> void:
	app.ui_shell.self_panel = PanelContainer.new()
	app.ui_shell.self_panel.name = "PlayerIdentity"
	app.ui_shell.self_panel.add_theme_stylebox_override("panel",_surface(Color.TRANSPARENT,0,0))
	app.game_left.add_child(app.ui_shell.self_panel)
	app.ui_shell.self_row = HBoxContainer.new()
	app.ui_shell.self_row.add_theme_constant_override("separation",8)
	app.ui_shell.self_row.custom_minimum_size.y = 30
	var footer_stack := VBoxContainer.new()
	footer_stack.add_theme_constant_override("separation",0)
	app.ui_shell.self_panel.add_child(footer_stack)
	footer_stack.add_child(app.ui_shell.self_row)
	footer_meta = HBoxContainer.new()
	footer_meta.custom_minimum_size.y = 30
	footer_stack.add_child(footer_meta)
	footer_meta.hide()
	self_icon = _portrait(app.ui_shell.self_row)
	app.self_line = app._label(app.ui_shell.self_row,"",13)
	app.self_line.autowrap_mode = TextServer.AUTOWRAP_OFF
	app.self_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app.self_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	exposure_summary = app._label(app.ui_shell.self_row,"",13)
	exposure_summary.autowrap_mode = TextServer.AUTOWRAP_OFF
	exposure_summary.size_flags_horizontal = Control.SIZE_SHRINK_END
	exposure_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	exposure_summary.hide()
	app.ui_shell.presence_cell = MarginContainer.new()
	app.ui_shell.self_row.add_child(app.ui_shell.presence_cell)
	app.ui_shell.presence_slot = HBoxContainer.new()
	app.ui_shell.presence_cell.add_child(app.ui_shell.presence_slot)

func build_selection(parent: Node) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	parent.add_child(header)
	app.selection_icon = TextureRect.new()
	app.selection_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.selection_icon.offset_left = 5
	app.selection_icon.offset_right = -5
	app.selection_icon.offset_top = 5
	app.selection_icon.offset_bottom = -5
	app.selection_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	app.selection_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	app.selection_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(app.selection_icon)
	app.selection_icon.custom_minimum_size = Vector2(28,32)
	app.selection_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_theme_constant_override("separation",1)
	header.add_child(names)
	app.selection_label = app._label(names,"",14)
	app.selection_label.add_theme_font_override("font",app._original_font(700))
	selection_position = app._label(names,"",13)
	selection_position.set_meta("match_muted",true)
	app.action_details_button = _tool(header,"help","기물 능력과 주의사항을 확인합니다.",_mobile_details)
	app.action_details_button.custom_minimum_size = Vector2(44,44)
	app.action_details_button.add_theme_constant_override("icon_max_width",15)
	app.cancel_selection_button = _tool(header,"close","선택 취소 · Esc / 우클릭",app._clear_selection)
	app.cancel_selection_button.custom_minimum_size = Vector2(44,44)
	app.cancel_selection_button.hide()
	selection_position.autowrap_mode = TextServer.AUTOWRAP_OFF
	selection_position.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	app.selection_label.autowrap_mode = TextServer.AUTOWRAP_OFF

func render_selection() -> void:
	var selected: bool = not app.selection.is_empty()
	app.selection_icon.get_parent().visible = selected
	render_mobile_actions()
	if selected:
		var cell: Vector2i = app.selection.cell
		app.selection_label.text = app.NAMES.get(app.selection.t,"기물")
		selection_position.text = "%s%d · %s" % [String.chr(97+cell.y),cell.x+1,app.game_ux.action_name(app.mode)]

func build_mobile_actions() -> void:
	mobile_actions = PanelContainer.new()
	mobile_actions.name = "MobileActions"
	mobile_actions.set_meta("match_card",true)
	# A reserved footprint keeps the board steady when selection/status changes.
	mobile_actions.custom_minimum_size.y = 126
	app.game_left.add_child(mobile_actions)
	app.game_left.move_child(mobile_actions,app.board.get_index()+1)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",3)
	mobile_actions.add_child(content)
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 44
	content.add_child(header)
	mobile_title = app._label(header,"",14)
	mobile_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mobile_help = _tool(header,"help","선택 기물의 행동·상태 자세히 보기",_mobile_details)
	mobile_cancel = _tool(header,"close","기물 선택 취소",app._clear_selection)
	for button in [mobile_help,mobile_cancel]: button.custom_minimum_size = Vector2(44,44)
	mobile_instruction = app._label(content,"",13)
	mobile_status = app._label(content,"",13)
	for label in [mobile_title,mobile_instruction,mobile_status]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 1
	mobile_actions.hide()

func mobile_actions_active() -> bool:
	return app.split.vertical and app.view.get("phase")=="play" and app.seat!="spectator" and not app.replay.active

func layout_mobile_actions() -> void:
	if not is_instance_valid(mobile_actions): return
	mobile_actions.visible = mobile_actions_active()
	_refresh_footer_summary()
	app.coach_label.get_parent().get_parent().visible = app.view.get("phase")!="over" and not mobile_actions.visible
	render_mobile_actions()

func _refresh_footer_summary() -> void:
	if not is_instance_valid(exposure_summary): return
	var view: Dictionary = app.view
	var meta_parent: Node = footer_meta if app.split.vertical else app.ui_shell.self_row
	if exposure_summary.get_parent()!=meta_parent:
		exposure_summary.reparent(meta_parent)
		app.ui_shell.presence_cell.reparent(meta_parent)
	footer_meta.visible = app.split.vertical
	exposure_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL if app.split.vertical else Control.SIZE_SHRINK_END
	app.ui_shell.presence_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app.ui_shell.presence_slot.alignment = BoxContainer.ALIGNMENT_END
	var exposed: Array = view.get("exposed",[])
	var active: bool = view.get("phase")=="play" and not exposed.is_empty() and app.seat!="spectator" and not app.replay.active
	exposure_summary.visible = app.split.vertical and active
	if app.seat=="spectator" or app.replay.active: return
	var identity: String = "%s · 나   %s" % [str(view.get("myName","나")),app._rating(view.get("myRating"))]
	var full_status: String = " · ! 적 시야에 노출 %d개" % exposed.size() if active else ""
	app.self_line.text = identity + ("" if exposure_summary.visible else full_status)
	app.self_line.tooltip_text = identity + full_status
	if exposure_summary.visible:
		exposure_summary.text = "내 노출 기물 %d" % exposed.size()
		exposure_summary.tooltip_text = "상대에게 위치가 보이는 내 기물 %d개" % exposed.size()
		exposure_summary.add_theme_color_override("font_color",Color("#76521e") if app.prefs.get_value("settings","light",false) else Color("#e3bd78"))

func render_mobile_actions() -> void:
	if not is_instance_valid(mobile_actions): return
	mobile_actions.visible = mobile_actions_active()
	var selected: bool = not app.selection.is_empty()
	var palette: Dictionary = app.ui_components._palette()
	var status: Array[String] = []
	mobile_title.text = "기물을 선택하세요"
	mobile_instruction.text = app.coach_label.text
	mobile_help.disabled = not selected
	mobile_cancel.disabled = not selected
	if selected:
		var cell: Vector2i = app.selection.cell
		mobile_title.text = "%s %s%d · %s" % [app.NAMES.get(app.selection.t,"기물"),String.chr(97+cell.y),cell.x+1,app.game_ux.action_name(app.mode)]
		if app.mode=="choose" and app.piece_input.preview_mode.is_empty(): mobile_instruction.text = ""
		if app.moves.get("reloading",false): status.append("재장전 중")
		for exposure in app.view.get("exposed",[]):
			if exposure.get("pid")==app.selection.get("id"):
				status.append("이 기물 위치 노출")
				break
		if status.is_empty() and int(app.board.tile(cell).get("t",0))==3: status.append("부쉬 안 · 연결 시야 공유")
		if status.is_empty(): status.append(app.action_hint.text.split("\n")[0])
	else:
		status.append("선택한 기물의 행동과 상태가 여기에 표시됩니다")
	if not app.game_session.request_status.is_empty(): mobile_instruction.text = app.game_session.request_status
	mobile_status.text = " · ".join(status)
	mobile_status.add_theme_color_override("font_color",palette.text if selected else palette.muted)
	for label in [mobile_title,mobile_instruction,mobile_status]:
		label.tooltip_text = label.text
		label.visible = not label.text.is_empty()

func _mobile_details() -> void:
	if app.selection.is_empty(): return
	var pair: Array = app._small_window(app.selection_label.text+" · 행동과 규칙",440,560)
	app._label(pair[1],app.coach_label.text,16)
	app._label(pair[1],app.action_hint.text,14)
	app._label(pair[1],app.action_details.text,14)
	app._label(pair[1],"행동 선택 → 대상 선택\n공격은 적 기물을 잡는 포획입니다.\n터치: 행동을 누른 뒤 대상 선택 · ×로 취소\n키보드: Tab으로 버튼 이동 · Enter로 선택 · Esc로 취소",14)
	var choices := HFlowContainer.new()
	pair[1].add_child(choices)
	for action in ["attack",app.game_ux.ability_mode(),"move"]:
		if action=="none": continue
		var choice: Button = app._button(choices,app.game_ux.action_name(action),func(): pair[0].queue_free(); app._choose_action(action))
		choice.disabled = app.busy or app.game_session.awaiting_state or app.view.get("turn")!=app.view.get("yourColor") or not app.game_ux.action_available(action)
	app._button(pair[1],"선택 취소",func(): pair[0].queue_free(); app._clear_selection())

func build_history(parent: Node) -> void:
	var content := card(parent)
	content.name = "MoveHistory"
	content.get_parent().set_meta("match_compact",true)
	history_toggle = app._button(content,"이동 기록",func():
		history_expanded = not history_expanded
		render_history(),"tertiary")
	history_toggle.icon = load("res://ui/icons/match-history.svg")
	history_toggle.expand_icon = true
	history_toggle.add_theme_constant_override("icon_max_width",15)
	history_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	history_toggle.add_theme_font_size_override("font_size",12)
	history_toggle.set_meta("match_disclosure",true)
	history_toggle.custom_minimum_size.y = 34
	var policy: Label = app._label(content,"",11)
	policy.name = "HistoryPolicy"
	policy.hide()
	policy.set_meta("match_muted",true)
	app.history_label = app._label(content,"",14)
	app.history_label.add_theme_constant_override("line_spacing",6)
	app.history_button = app._button(content,"전체 이동 기록",_history_window,"tertiary")
	app.history_button.add_theme_font_size_override("font_size",12)
	app.history_button.hide()

func render_history() -> void:
	if not is_instance_valid(history_toggle): return
	if history_room!=app.room:
		history_room = app.room
		history_expanded = false
	var lines: Array[String] = []
	for line in app.view.get("moveHistory",[]): lines.append(app.game_display._compact_history(str(line)))
	var count := 10 if history_expanded else 3
	var tail := lines.slice(maxi(0,lines.size()-count))
	app.history_label.text = ("\n" if history_expanded else "   ").join(tail) if not lines.is_empty() else "아직 이동 기록이 없습니다."
	history_toggle.text = "이동 기록    %s %s" % ["양쪽 기보" if app.seat=="spectator" or app.replay.active else "내 기보","▴" if history_expanded else "▾"]
	history_toggle.tooltip_text = "최근 10수 펼치기 / 접기"
	app.history_label.get_parent().get_node("HistoryPolicy").visible = history_expanded
	app.history_button.visible = history_expanded and lines.size()>10
	app.history_button.text = "전체 %d수 보기" % lines.size()
	app.history_label.tooltip_text = "K 킹 · Q 퀸 · R 전차 · B 비숍 · N 나이트\nx 포획 · ! 저격 · >> 돌파 · ? 스캔 · = 승격\n숫자는 대국의 행동 순서입니다."

func _history_window() -> void:
	var pair: Array = app._window("이동 기록")
	app._label(pair[1],"현재 공개 시점까지의 기록" if app.seat=="spectator" or app.replay.active else "내 행동만 표시됩니다.",12)
	var lines: Array[String] = []
	for line in app.view.get("moveHistory",[]): lines.append(app.game_display._compact_history(str(line)))
	app._label(pair[1],"\n".join(lines),15)

func render() -> void:
	var view: Dictionary = app.view
	var phase: String = view.get("phase","")
	var light: bool = app.prefs.get_value("settings","light",false)
	var palette: Dictionary = app.ui_components._palette()
	var mine: bool = view.get("turn")==view.get("yourColor") and app.seat!="spectator"
	var seconds: Variant = view.get("secondsLeft") if phase=="setup" else view.get("turnSecondsLeft")
	var low: bool = mine and phase=="play" and seconds!=null and int(seconds)<=10
	var fill: Color = (Color("#f4e5c9") if light else Color("#383329")) if mine and phase=="play" else palette.surface
	if low: fill = Color("#fbe5dc") if light else Color("#412d26")
	turn_panel.add_theme_stylebox_override("panel",_surface(fill,0,10))
	turn_strip.modulate.a = 1.0 if seconds!=null and phase!="over" and not app.replay.active else 0.0
	app.turn_meta.visible = not app.warning_label.visible
	app.warning_label.tooltip_text = app.warning_label.text
	app.state_label.tooltip_text = app.state_label.text
	app.notice.tooltip_text = app.notice.text
	turn_strip.max_value = maxi(1,int(view.get("setupSeconds",70) if phase=="setup" else view.get("turnSeconds",30)))
	turn_strip.value = float(seconds) if seconds!=null else 0.0
	turn_strip.add_theme_stylebox_override("background",StyleBoxEmpty.new())
	turn_strip.add_theme_stylebox_override("fill",_surface(palette.danger if low else (palette.accent if mine else palette.muted),0,0))
	app.ui_shell.state_group.custom_minimum_size.y = 42
	if not app.replay.active:
		mode_label.text = "관전 · 3분 지연" if app.seat=="spectator" else ("혼자 연습" if view.get("solo") else ("컴퓨터 대국" if view.get("bot") else ("랭크 대전" if view.get("rated") else "친구 대전")))
	else: mode_label.text = "리플레이"
	var side: String = str(view.get("yourColor","W"))
	var top_side := ("B" if side=="W" else "W") if app.seat!="spectator" else ("W" if app.spectating.flipped else "B")
	opponent_icon.texture = load("res://pieces/Chess_k%st45.svg" % ("l" if top_side=="W" else "d"))
	self_icon.texture = load("res://pieces/Chess_k%st45.svg" % ("d" if top_side=="W" else "l"))
	opponent_icon.visible = not view.get("spectatorWaiting",false)
	self_icon.visible = opponent_icon.visible
	top_sound.icon = load("res://ui/icons/match-%s.svg" % ("volume" if app.audio.enabled else "muted"))
	top_sound.tooltip_text = "효과음 끄기" if app.audio.enabled else "효과음 켜기"
	top_sound.accessibility_name = top_sound.tooltip_text
	app.coach_label.add_theme_color_override("font_color",palette.text)
	layout_mobile_actions()
	render_selection()
	render_history()
	app.game_ux.render()
	if app.ui_shell.setup_ui!=null: app.ui_shell.setup_ui.render()

func apply_theme() -> void:
	var palette: Dictionary = app.ui_components._palette()
	for panel in app.game.find_children("*","PanelContainer",true,false):
		if panel.get_meta("match_card",false):
			var surface := _surface(palette.surface)
			if panel.get_meta("match_compact",false):
				surface.content_margin_top = 8
				surface.content_margin_bottom = 8
			panel.add_theme_stylebox_override("panel",surface)
	for label in app.game.find_children("*","Label",true,false):
		if label.get_meta("match_muted",false): label.add_theme_color_override("font_color",palette.muted)
	for button in app.game.find_children("*","Button",true,false):
		if button.get_meta("match_tool",false) or button.get_meta("match_disclosure",false):
			for state in ["normal","hover","pressed","focus","disabled"]:
				var style: StyleBoxFlat = app.ui_components._button_style("tertiary",state)
				style.content_margin_left = 6
				style.content_margin_right = 6
				button.add_theme_stylebox_override(state,style)
		for name in ["icon_normal_color","icon_hover_color","icon_focus_color","icon_pressed_color"]: button.add_theme_color_override(name,palette.muted)
	app.coach_label.add_theme_color_override("font_color",palette.text)
