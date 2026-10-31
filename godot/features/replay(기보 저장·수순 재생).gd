extends RefCounted
var app
var data: Dictionary = {}
var index := 0
var active := false
var playing := false
var timer: Timer
var bar: VBoxContainer
var bar_panel: PanelContainer
var vision_panel: PanelContainer
var counter: Label
var play_button: Button
var previous_button: Button
var next_button: Button
var return_view: Dictionary = {}
var return_seat := ""
var vision_bar: HBoxContainer
var vision_buttons: Array[Button] = []
var vision := "all"
var transport: Control
var transport_center: HBoxContainer
var close_button: Button
var frame_picker: OptionButton
var previous_event: Button
var next_event: Button
var navigation_panel: PanelContainer
var tools_panel: PanelContainer
var tools_toggle: Button
var tools_box: VBoxContainer
var current_action: Label
var action_detail: Label
var frame_caption: Label
var vision_note: Label
var move_chips: Array[Button] = []
var full_history_button: Button
var history_panel: Control
var feed_panel: Control
var feed_title: Label
var tools_expanded := false

func _init(context: Control) -> void:
	app = context

func _heading(parent: Node, title: String, note: String="") -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = app._label(row,title,15)
	label.add_theme_font_override("font",app._original_font(700))
	var hint: Label = app._label(row,note,11)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.set_meta("match_muted",true)
	hint.size_flags_horizontal = Control.SIZE_SHRINK_END
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return hint

func build() -> void:
	bar_panel = app.ui_shell._grid_panel(app.game_left)
	app.game_left.move_child(bar_panel,app.ui_shell.self_panel.get_index()+1)
	bar = VBoxContainer.new()
	bar.add_theme_constant_override("separation",8)
	app.ui_shell._grid_cell(bar_panel).add_child(bar)
	bar.visibility_changed.connect(func(): bar_panel.visible = bar.visible)
	var status_row := HBoxContainer.new()
	bar.add_child(status_row)
	counter = app._label(status_row,"",18)
	counter.autowrap_mode = TextServer.AUTOWRAP_OFF
	frame_caption = app._label(status_row,"",12)
	frame_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	frame_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	frame_caption.set_meta("match_muted",true)
	transport = Control.new()
	bar.add_child(transport)
	transport_center = HBoxContainer.new()
	transport_center.add_theme_constant_override("separation",4)
	transport.add_child(transport_center)
	previous_event = _transport_button("주요 사건","previous-event",func(): jump_event(-1))
	previous_button = _transport_button("이전","previous",func(): step(-1))
	play_button = _transport_button("자동 재생","play",toggle,true)
	next_button = _transport_button("다음","next",func(): step(1))
	next_event = _transport_button("주요 사건","next-event",func(): jump_event(1))
	previous_event.accessibility_name = "이전 주요 사건"
	next_event.accessibility_name = "다음 주요 사건"
	transport.resized.connect(_transport_layout)

	var vision_box: VBoxContainer = app.match_ui.card(app.controls)
	vision_panel = vision_box.get_parent()
	vision_note = _heading(vision_box,"보드 시야","당시 화면")
	vision_bar = HBoxContainer.new()
	vision_bar.add_theme_constant_override("separation",4)
	vision_box.add_child(vision_bar)
	vision_bar.visibility_changed.connect(func(): vision_panel.visible = vision_bar.visible)
	for item in [["전체","all"],["백 시야","W"],["흑 시야","B"]]:
		var side: String = item[1]
		var button: Button = app._button(vision_bar,item[0],func(): vision=side; show_frame())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",13)
		vision_buttons.append(button)
	var navigation_box: VBoxContainer = app.match_ui.card(app.controls)
	navigation_panel = navigation_box.get_parent()
	_heading(navigation_box,"수순 기록","자동 재생 1.5초")
	frame_picker = OptionButton.new()
	frame_picker.custom_minimum_size.y = 44
	frame_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_picker.clip_text = true
	frame_picker.accessibility_name = "원하는 기보 수순으로 이동"
	frame_picker.add_theme_font_size_override("font_size",13)
	navigation_box.add_child(frame_picker)
	frame_picker.item_selected.connect(func(value): seek(value))
	current_action = app._label(navigation_box,"",16)
	action_detail = app._label(navigation_box,"",12)
	action_detail.set_meta("match_muted",true)
	navigation_box.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",4)
	grid.add_theme_constant_override("v_separation",4)
	navigation_box.add_child(grid)
	for i in range(6):
		var button: Button = preload("res://features/move_record_chip.gd").build(app,grid,func(): pass)
		button.pressed.connect(func(): seek(int(button.get_meta("frame",0))))
		move_chips.append(button)
	full_history_button = app._button(navigation_box,"전체 이동 기록",app.match_ui._history_window,"tertiary")
	full_history_button.add_theme_font_size_override("font_size",12)
	var tools_content: VBoxContainer = app.match_ui.card(app.controls)
	tools_panel = tools_content.get_parent()
	tools_toggle = app._button(tools_content,"제보 도구  ▾",func():
		tools_expanded = not tools_expanded
		_refresh_tools(),"tertiary")
	tools_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tools_box = VBoxContainer.new()
	tools_box.add_theme_constant_override("separation",8)
	tools_content.add_child(tools_box)
	app._label(tools_box,"현재 리플레이·수순·시야를 제보에 포함합니다.",12).set_meta("match_muted",true)
	app._button(tools_box,"제보 정보 복사",func():
		DisplayServer.clipboard_set(report_context())
		app._message("리플레이 ID·수순·시야를 복사했습니다. 제보 내용에 붙여넣으세요."))
	app._button(tools_box,"이 대국 신고",func(): preload("res://support(공지·제보·이의제기).gd").new(app).report(str(data.get("id","")),index))
	close_button = app._button(app.match_ui.chrome,"리플레이 닫기",close)
	close_button.add_theme_font_size_override("font_size",12)
	history_panel = app.history_label.get_parent().get_parent()
	feed_panel = app.feed_box.get_parent().get_parent()
	feed_title = app.feed_box.get_parent().get_child(0)
	navigation_panel.hide()
	tools_panel.hide()
	close_button.hide()
	_refresh_tools()
	vision_bar.hide()
	bar.hide()
	timer = Timer.new()
	timer.wait_time = 1.5
	timer.timeout.connect(_tick)
	app.add_child(timer)

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func _transport_button(caption: String, icon_name: String, callback: Callable, primary: bool=false) -> Button:
	var button: Button = app._button(transport_center,"",callback,"primary" if primary else "secondary")
	button.custom_minimum_size = Vector2(44,48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = caption
	var content := BoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation",4)
	button.add_child(content)
	var art := TextureRect.new()
	art.texture = load("res://ui/icons/replay-"+icon_name+".svg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(16,16)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(art)
	var label: Label = app._label(content,caption,13)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if icon_name in ["next","next-event"]: content.move_child(art,1)
	button.set_meta("content",content)
	button.set_meta("caption",label)
	button.set_meta("art",art)
	_ignore_pointer(content)
	return button

func _transport_layout() -> void:
	if not is_instance_valid(transport): return
	# A wide but short viewport can have a narrow board. Size the five-button
	# row from its actual space instead of the outer window width.
	var compact: bool = transport.size.x<440
	var height := 56 if compact else 48
	transport.custom_minimum_size.y = height
	transport_center.position = Vector2.ZERO
	transport_center.size = Vector2(transport.size.x,height)
	for button in transport_center.get_children():
		button.custom_minimum_size.y = height
		var content: BoxContainer = button.get_meta("content")
		content.vertical = compact
		content.move_child(button.get_meta("art"),0 if compact or button not in [next_button,next_event] else 1)
		button.get_meta("caption").add_theme_font_size_override("font_size",11 if compact else 13)

func _refresh_tools() -> void:
	tools_box.visible = tools_expanded
	tools_toggle.text = "제보 도구  "+("▴" if tools_expanded else "▾")
	tools_toggle.accessibility_name = "제보 도구 접기" if tools_expanded else "제보 도구 펼치기"

func layout_controls(_desktop: bool) -> void:
	if not is_instance_valid(vision_panel): return
	app.match_ui.turn_panel.visible = not active
	navigation_panel.visible = active
	tools_panel.visible = active
	close_button.visible = active
	history_panel.visible = not active
	for button in app.match_ui.chrome.get_children():
		if button.get_meta("match_tool",false): button.visible = not active
	if active:
		for i in range(4): app.controls.move_child([vision_panel,navigation_panel,feed_panel,tools_panel][i],i)
	feed_title.text = "교전 기록" if active else "대국 기록 · 킬로그"
	feed_title.add_theme_font_size_override("font_size",15)
	_transport_layout()

func apply_theme() -> void:
	if not is_instance_valid(play_button): return
	var colors: Dictionary = app.ui_components._palette()
	var blue := Color("#275f87") if app.prefs.get_value("settings","light",false) else Color("#a3ccef")
	for button in transport_center.get_children():
		var ink: Color = Color("#241e14") if button==play_button else (blue if button in [previous_event,next_event] else colors.text)
		button.get_meta("caption").add_theme_color_override("font_color",ink)
		button.get_meta("art").modulate = ink
		button.get_meta("content").modulate.a = .42 if button.disabled else 1.0
	for button in vision_buttons:
		var style: StyleBoxFlat = app.ui_components._button_style("secondary","normal")
		if button.button_pressed: style.border_color = colors.accent
		button.add_theme_stylebox_override("normal",style)
		button.add_theme_color_override("font_color",blue if button.button_pressed else colors.text)
	for button in move_chips:
		var selected: bool = int(button.get_meta("frame",-1))==index
		preload("res://features/move_record_chip.gd").style(app,button,selected)

func _refresh_record() -> void:
	var frame: Dictionary = data.frames[index]
	current_action.text = str(frame.get("label","대국 시작"))
	action_detail.text = _frame_title(index)
	var start := maxi(1,mini(index-2,data.frames.size()-6))
	for i in range(move_chips.size()):
		var button := move_chips[i]
		var value := start+i
		button.visible = value<data.frames.size()
		if not button.visible: continue
		var item: Dictionary = data.frames[value]
		var info: Variant = item.get("action")
		var side := ""
		var notation := str(item.get("label","장면"))
		var piece_icon: TextureRect = button.get_meta("piece_icon")
		piece_icon.hide()
		if info is Dictionary:
			side = "백" if info.get("actor")=="W" else "흑" if info.get("actor")=="B" else ""
			notation = preload("res://features/move_record_chip.gd").display_notation(str(info.get("compact",notation)))
			var piece: Dictionary = data.frames[value-1].get("pieces",{}).get(str(info.get("pid","")),{})
			if piece.get("t") in ["K","Q","R","B","N","P"] and piece.get("o") in ["W","B"]:
				piece_icon.texture = load("res://pieces/Chess_%s%st45.svg" % [str(piece.t).to_lower(),"l" if piece.o=="W" else "d"])
				piece_icon.show()
		button.set_meta("frame",value)
		button.get_meta("caption").text = "%d · %s" % [value,side]
		button.get_meta("notation").text = notation
		button.accessibility_name = _frame_title(value)
	full_history_button.disabled = app.view.get("moveHistory",[]).is_empty()
	apply_theme()

func _tick() -> void:
	if not active: timer.stop(); return
	var advanced: bool = index<data.frames.size()-1
	if advanced: index+=1
	if index==data.frames.size()-1: playing=false; timer.stop()
	show_frame(advanced)

func open(id: String, token: String="") -> void:
	if app.busy or active: return
	app.busy = true
	var response: Dictionary = await app.api.request("/replay?id=%s&token=%s&session=%s" % [id.uri_encode(),token.uri_encode(),app.session.uri_encode()])
	app.busy = false
	if not response.get("ok"): app._report(response); return
	open_data(response.replay)

func open_data(payload: Dictionary) -> void:
	data = payload
	if data.get("frames",[]).is_empty(): app._message("재생할 기보가 없습니다."); return
	return_view = app.view.duplicate(true)
	return_seat = app.seat
	active = true
	playing = false
	index = 0
	tools_expanded = false
	_refresh_tools()
	app.page_scroll.scroll_vertical = 0
	frame_picker.clear()
	for i in range(data.frames.size()): frame_picker.add_item(_frame_title(i),i)
	vision = "all"
	app.generation += 1
	app.seat = "spectator"
	app.home.hide()
	app.subpage.hide()
	app.game.show()
	app._clear_selection()
	bar.show()
	vision_bar.show()
	app._layout()
	show_frame()

func remember() -> void:
	var id: String = app.view.get("replayId","") if app.view.get("replayId")!=null else ""
	if id.is_empty() or active: return
	var saved: Array = app.prefs.get_value(app.api.base_url,"replays",[])
	for item in saved:
		if item.id==id: return
	saved.push_front({"id":id,"token":app.token,"title":"방 "+app.room+" · "+Time.get_datetime_string_from_system()})
	if saved.size()>100: saved.resize(100)
	app.prefs.set_value(app.api.base_url,"replays",saved)
	app._save()

func menu() -> void:
	var box: VBoxContainer = app._subscreen("저장된 리플레이","이 기기에서 확인한 종료 대국 · 서버에 기보가 저장됩니다.")
	var saved: Array = app.prefs.get_value(app.api.base_url,"replays",[])
	if saved.is_empty(): app._label(box,"대국 종료 후 리플레이가 여기에 표시됩니다.")
	for item in saved:
		app._button(box,str(item.title),func(): await open(str(item.id),str(item.token)))
	app._button(box,"← 뒤로",app._navigation_home)

func step(amount: int, animate: bool=true) -> void:
	playing = false
	timer.stop()
	var previous := index
	index = clampi(index+amount,0,data.frames.size()-1)
	show_frame(animate and index==previous+1)

func seek(value: int, animate: bool=false) -> void:
	playing = false
	timer.stop()
	index = clampi(value,0,data.frames.size()-1)
	show_frame(animate)

func _is_event(value: int) -> bool:
	if value<=0 or value>=data.frames.size(): return false
	var frame: Dictionary = data.frames[value]
	var action: Variant = frame.get("action")
	if action is Dictionary and action.get("action") in ["fire","barrage","scan","promote","resign"]: return true
	var previous: Dictionary = data.frames[value-1].get("pieces",{})
	for pid in frame.get("pieces",{}):
		if previous.get(pid,{}).get("alive",false) and not frame.pieces[pid].get("alive",false): return true
	return frame.view.get("phase")=="over"

func _event_index(direction: int) -> int:
	var target := index+direction
	while target>=0 and target<data.frames.size():
		if _is_event(target): return target
		target+=direction
	return -1

func jump_event(direction: int) -> void:
	var target := _event_index(direction)
	if target>=0: seek(target,true)

func _square(rc: Variant) -> String:
	if not rc is Array or rc.size()!=2 or rc[0]==null or rc[1]==null: return ""
	return String.chr(97+int(rc[1]))+str(int(rc[0])+1)

func _frame_title(value: int) -> String:
	var frame: Dictionary = data.frames[value]
	var text := "%d · %s" % [value,str(frame.label)]
	var action: Variant = frame.get("action")
	if action is Dictionary and action.has("compact"):
		return "%d. %s %s" % [int(action.get("turn",value))+1,"백" if action.get("actor")=="W" else "흑",preload("res://features/move_record_chip.gd").display_notation(str(action.compact))]
	if action is Dictionary:
		var destination: Variant = action.get("target") if action.get("target")!=null else action.get("to")
		var origin := _square(action.get("from"))
		if not origin.is_empty(): text += " · "+origin+" → "+_square(destination)
	return text

func report_context() -> String:
	return "리플레이: %s\n수순: %s\n시야: %s\n기대 동작: \n실제 동작: " % [str(data.get("id","")),_frame_title(index),{"all":"전체","W":"백","B":"흑"}[vision]]

func toggle() -> void:
	playing = not playing
	if playing:
		if index==data.frames.size()-1: index=0
		timer.start()
	else: timer.stop()
	show_frame()

func _clear_frame_effects() -> void:
	app.board.fx.clear()
	app.board.piece_motion.clear()
	app.board.recoil.clear()
	app.board.brush_reactions.clear()
	app.board.remote_motion_cells.clear()
	app.board.bursts.clear()
	app.board.targeting.clear_decal()

func _frame_effect(value: int, perspective: String) -> Dictionary:
	# Reuse the server-filtered effect stored for this exact action. Never derive
	# enemy trajectories from the omniscient notation while a side view is active.
	if value<=0 or value>=data.frames.size(): return {}
	var frame: Dictionary = data.frames[value]
	var action: Variant = frame.get("action")
	if not action is Dictionary or action.get("action") not in ["move","fire","barrage","scan"]: return {}
	var actor: String = str(action.get("actor",""))
	if actor not in ["W","B"]: return {}
	var side: String = actor if perspective=="all" else perspective
	var recorded: Variant = frame.get("perspectives",{}).get(side,{}).get("fx")
	if not recorded is Dictionary or recorded.get("actor")!=actor or recorded.get("cells",[]).is_empty(): return {}
	var previous: Dictionary = data.frames[value-1]
	var old: Variant = previous.get("perspectives",{}).get(side,{}).get("fx")
	if old is Dictionary and int(old.get("seq",-1))==int(recorded.get("seq",-1)): return {}
	var result: Dictionary = recorded.duplicate(true)
	if perspective=="all" or perspective==actor:
		var origin: Variant = action.get("from")
		if origin is Array and origin.size()==2 and origin[0]!=null and origin[1]!=null:
			result["from"] = origin.duplicate()
			result["confirmed_source"] = true
			if action.action=="move" and action.get("to") is Array:
				var piece: Dictionary = previous.get("pieces",{}).get(str(action.get("pid","")),{})
				if not piece.is_empty():
					result["motion_piece"] = piece.duplicate(true)
					result["to"] = action.to.duplicate()
	return result

func show_frame(animate: bool=false) -> void:
	var frame: Dictionary = data.frames[index]
	_clear_frame_effects()
	app.pending_fx = {}
	app.view = frame.view.duplicate(true)
	app.view["fx"] = null
	app.feed_signature = ""
	app.result_signature = ""
	app._render()
	var has_vision: bool = frame.has("perspectives")
	if not has_vision: vision = "all"
	for i in range(vision_buttons.size()):
		vision_buttons[i].set_pressed_no_signal(vision==["all","W","B"][i])
		vision_buttons[i].disabled = i>0 and not has_vision
		vision_buttons[i].tooltip_text = "이전 기보에는 당시 시야가 저장되어 있지 않습니다." if not has_vision else ""
	var board_view: Dictionary = app.view.duplicate(true)
	if vision!="all":
		var perspective: Dictionary = frame.perspectives[vision]
		for key in ["grid","scanTiles","scanZones","exposed","yourColor"]: board_view[key] = perspective.get(key)
		board_view["reloading"] = perspective.get("reloading",[])
	app.board.fog_alpha.clear()
	app.board.set_view(board_view,app.spectating.flipped)
	layout_controls(not app.split.vertical)
	app.room_label.get_parent().get_parent().hide()
	# Keep the final position inspectable; result is shown in the title.
	app.result_panel.hide()
	app.spectating.presence_row.hide()
	app.ui_shell.set_audience_visible(false)
	app.state_label.text = "리플레이 · "+str(frame.label)
	if app.view.get("phase")=="over":
		app.state_label.text += " · "+("무승부" if app.view.get("winner")=="draw" else ("백 승리" if app.view.get("winner")=="W" else "흑 승리"))
	app.status_label.text = "저장된 기보 재생"
	app.coach_label.get_parent().get_parent().hide()
	app.coach_label.text = "보드 시야 전환 · 자동 재생 1.5초 간격" if has_vision else "이전 기보: 전체 시야만 제공됩니다."
	counter.text = "%d / %d수" % [index,data.frames.size()-1]
	frame_caption.text = str(frame.label)
	vision_note.text = "당시 화면" if has_vision else "전체 시야만 지원"
	frame_picker.select(index)
	previous_event.disabled = _event_index(-1)<0
	next_event.disabled = _event_index(1)<0
	previous_button.disabled = index==0
	next_button.disabled = index==data.frames.size()-1
	play_button.get_meta("caption").text = "일시 정지" if playing else "자동 재생"
	play_button.accessibility_name = "일시 정지" if playing else "자동 재생"
	play_button.get_meta("art").texture = load("res://ui/icons/replay-%s.svg" % ("pause" if playing else "play"))
	_refresh_record()
	if animate:
		var effect := _frame_effect(index,vision)
		if effect.get("type")=="scan" and (vision=="all" or vision==effect.get("actor")):
			effect["extra"] = []
			for rc in effect.get("cells",[]):
				var piece: Variant = app.board.tile(Vector2i(rc[0],rc[1])).get("p")
				if piece is Dictionary and piece.get("o")!=effect.get("actor"): effect.extra.append(rc)
		app.board.play_fx(effect)

func close() -> void:
	if not active: return
	_clear_frame_effects()
	timer.stop()
	playing = false
	active = false
	bar.hide()
	vision_bar.hide()
	app.spectating.presence_row.show()
	app.ui_shell.set_audience_visible(true)
	app.seat = return_seat
	app.view = return_view
	app.feed_signature = ""
	app.result_signature = ""
	app._layout()
	if app.room.is_empty(): app._return_home()
	else:
		app.board.set_view(app.view,app.seat=="B")
		app._render()
