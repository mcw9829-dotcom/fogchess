extends Node
## Mobile section shortcuts. The board and existing cards retain their parents,
## game state and input paths; this only changes the page's scroll destination.
var app
var bar: PanelContainer
var board_button: Button
var history_button: Button
var chat_button: Button
var chat_badge: PanelContainer
var chat_count: Label
var buttons: Dictionary = {}
var selected := "board"
var palette_key := ""
var jump_serial := 0
var elapsed := 0.0
var unread := 0
var scroll_finger := -1
var scroll_origin := Vector2.ZERO
var scroll_initial := 0.0
var scroll_target: Range
var swiping := false
var suppress_mouse_until := 0
var transcript_touch := false
var scroll_room := ""
var navigation_destination := ""

func _init(context: Control) -> void: app=context

func build(page_root: VBoxContainer) -> void:
	bar=PanelContainer.new()
	bar.name="MobileMatchNavigation"
	bar.accessibility_name="대국 화면 이동"
	page_root.add_child(bar)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	bar.add_child(row)
	for item in [["board","보드"],["history","기록"],["chat","채팅"]]:
		var key:String=item[0]
		var button:Button=app._button(row,item[1],func(): jump_to(key),"tertiary")
		button.name="MobileJump"+key.capitalize()
		button.custom_minimum_size=Vector2(44,44)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size",15)
		button.toggle_mode=true
		button.accessibility_name={"board":"체스판과 현재 차례로 이동","history":"교전과 이동 기록 보기","chat":"대전 채팅 펼쳐서 보기"}[key]
		button.set_meta("mobile_section",key)
		buttons[key]=button
	board_button=buttons.board;history_button=buttons.history;chat_button=buttons.chat
	chat_badge=PanelContainer.new()
	chat_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chat_badge.offset_left=-29;chat_badge.offset_right=-2
	chat_badge.offset_top=1;chat_badge.offset_bottom=20
	chat_badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
	chat_button.add_child(chat_badge)
	chat_count=app._label(chat_badge,"",11)
	chat_count.autowrap_mode=TextServer.AUTOWRAP_OFF
	chat_count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	chat_count.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	chat_count.mouse_filter=Control.MOUSE_FILTER_IGNORE
	bar.hide()
	app.page_scroll.scroll_deadzone=12
	app.page_scroll.get_v_scroll_bar().value_changed.connect(func(_value): _sync_section.call_deferred())
	app.game.visibility_changed.connect(refresh)
	# The board owns a touch that begins on it. Prevent that same touch from
	# bubbling into the outer scroll container, without intercepting its existing
	# aim preview or touch-emulated mouse selection/drag behavior.
	app.board.gui_input.connect(_board_touch)
	refresh()

func eligible() -> bool:
	return app.game.visible and app.split.vertical and (not app.room.is_empty() or app.replay.active)

func refresh() -> void:
	if not is_instance_valid(bar): return
	var next:=eligible()
	if bar.visible!=next:
		bar.visible=next
		app._layout.call_deferred()
	if not next: return
	var chat_enabled:bool=bool(app.view.get("chatEnabled",false)) and app.seat!="spectator" and not app.replay.active
	var blocked:bool=app.ui_motion.is_transition_busy()
	board_button.disabled=blocked;history_button.disabled=blocked;chat_button.disabled=blocked or not chat_enabled
	chat_button.accessibility_name="대전 채팅 · 이 대국에서는 사용하지 않음" if not chat_enabled else ("읽지 않은 메시지 %d개 · 대전 채팅으로 이동" % unread if unread>0 else "대전 채팅 펼쳐서 보기")
	set_chat_unread(app.chat.unread if chat_enabled else 0)
	_apply_theme()

func set_chat_unread(value: int) -> void:
	unread=maxi(0,value)
	if not is_instance_valid(chat_badge): return
	chat_badge.visible=unread>0 and not chat_button.disabled
	chat_count.text="99+" if unread>99 else str(unread)

func jump_to(section: String) -> void:
	if not eligible() or not buttons.has(section) or buttons[section].disabled: return
	jump_serial+=1
	var request:=jump_serial
	selected=section
	navigation_destination=section
	# A section shortcut is navigation, never a confirmation of a pending shot.
	# Keep the piece selection, but discard any stale touch target confirmation.
	if section!="board": app.ui_shell.aim_assist.clear_pending()
	if section=="board":
		app.page_scroll.scroll_vertical=0
		app.game_ux.update_scroll_bar()
	elif section=="history":
		if not app.replay.active:
			app.match_ui.history_expanded=true
			app.match_ui.render_history()
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		if request!=jump_serial or not eligible(): return
		_scroll_to_card(_history_target())
	elif section=="chat":
		if not app.chat.body.visible:app.chat.toggle.pressed.emit()
		app.chat._scroll_to_bottom()
		await app.get_tree().process_frame
		await app.get_tree().process_frame
		if request!=jump_serial or not eligible(): return
		_scroll_to_card(app.chat.card.get_parent())
	# The existing sticky turn strip can appear once we pass the board. Repeat
	# after layout so the destination remains readable beneath that strip.
	await app.get_tree().process_frame
	await app.get_tree().process_frame
	if request!=jump_serial or not eligible(): return
	if section=="board": app.page_scroll.scroll_vertical=0
	elif section=="chat": app.page_scroll.ensure_control_visible(app.chat.body)
	else: _scroll_to_card(_history_target())
	selected=section
	_apply_theme()

func _history_target() -> Control:
	return app.replay.navigation_panel if app.replay.active else app.feed_box.get_parent().get_parent()

func _scroll_to_card(target: Control) -> void:
	if not is_instance_valid(target) or not target.is_visible_in_tree(): return
	var scroll:ScrollContainer=app.page_scroll
	# Align the card heading at the top. Large histories remain swipe-scrollable;
	# small cards also keep their lower controls within the page's visible area.
	var destination:=scroll.scroll_vertical+int(target.global_position.y-scroll.global_position.y)
	scroll.scroll_vertical=maxi(0,destination)

func _sync_section() -> void:
	if not is_instance_valid(bar) or not bar.visible: return
	# A shortcut remains selected even when the last card is too short to align
	# at the top. Manual scrolling releases this destination preference.
	if not navigation_destination.is_empty():return
	var page:Rect2=app.page_scroll.get_global_rect()
	var next:="board"
	var record:Control=_history_target()
	if record.is_visible_in_tree() and record.get_global_rect().position.y<page.position.y+page.size.y*.6: next="history"
	var card:Control=app.chat.card.get_parent()
	if card.is_visible_in_tree() and card.get_global_rect().position.y<page.position.y+page.size.y*.6: next="chat"
	if app.page_scroll.scroll_vertical==0: next="board"
	if next!=selected:selected=next;_apply_theme()

func _board_touch(event: InputEvent) -> void:
	if not eligible(): return
	# gui_input is emitted before the board's _gui_input override. Ability mode
	# must receive raw touches there; it already accepts them after previewing.
	if app.board.touch_aim_enabled:return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		app.board.accept_event()

func _input(event: InputEvent) -> void:
	# Native desktop touch injection and some embedded web canvases do not enable
	# ScrollContainer's touchscreen panning. Make page swipes explicit, while
	# leaving board gestures and text editing with their existing controls.
	if event is InputEventMouse and event.device==InputEvent.DEVICE_ID_EMULATION:
		if swiping or transcript_touch or Time.get_ticks_msec()<suppress_mouse_until:
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and eligible():
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] or app.page_scroll.get_v_scroll_bar().get_global_rect().has_point(event.position):
			navigation_destination=""
	if event is InputEventScreenTouch:
		if event.pressed:
			if scroll_finger!=-1 or not eligible() or _modal_open():return
			if not app.page_scroll.get_global_rect().has_point(event.position):return
			navigation_destination=""
			if app.board.get_global_rect().has_point(event.position):return
			for entry in app.page_scroll.find_children("*","LineEdit",true,false):
				if entry.is_visible_in_tree() and entry.get_global_rect().has_point(event.position):return
			scroll_finger=event.index;scroll_origin=event.position;scroll_room=app.room;swiping=false;transcript_touch=false
			scroll_target=app.page_scroll.get_v_scroll_bar()
			if app.chat.transcript.is_visible_in_tree() and app.chat.transcript.get_global_rect().has_point(event.position):
				# Finger movement reads messages; do not start RichText mouse text
				# selection through emulation and then leave its autoscroll running.
				transcript_touch=true
				var transcript_scroll:VScrollBar=app.chat.transcript.get_v_scroll_bar()
				if transcript_scroll.max_value>transcript_scroll.page:scroll_target=transcript_scroll
			scroll_initial=scroll_target.value
			if transcript_touch:get_viewport().set_input_as_handled()
		elif event.index==scroll_finger:
			if swiping or transcript_touch:
				suppress_mouse_until=Time.get_ticks_msec()+100
			if swiping:
				app.page_scroll.get_child(0).propagate_notification(Control.NOTIFICATION_SCROLL_END)
			scroll_finger=-1;swiping=false;scroll_target=null;transcript_touch=false
		return
	if event is InputEventScreenDrag and event.index==scroll_finger:
		if not eligible() or not is_instance_valid(scroll_target) or _modal_open():
			_cancel_swipe()
			return
		var delta:Vector2=event.position-scroll_origin
		if not swiping and absf(delta.y)>=12 and absf(delta.y)>absf(delta.x):
			swiping=true
			app.page_scroll.get_child(0).propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		if swiping:
			scroll_target.value=scroll_initial-delta.y
			get_viewport().set_input_as_handled()

func _modal_open() -> bool:
	for window in app.find_children("*","Window",true,false):
		if window.visible and window.exclusive:return true
	return false

func _cancel_swipe() -> void:
	if swiping or transcript_touch:suppress_mouse_until=Time.get_ticks_msec()+100
	if swiping:app.page_scroll.get_child(0).propagate_notification(Control.NOTIFICATION_SCROLL_END)
	scroll_finger=-1;swiping=false;scroll_target=null;transcript_touch=false;scroll_room=""

func _apply_theme() -> void:
	var colors:Dictionary=app.ui_components._palette()
	var key:=str([colors,selected,chat_button.disabled])
	if key==palette_key:return
	palette_key=key
	bar.add_theme_stylebox_override("panel",app.match_ui._surface(colors.surface,4,10))
	for section in buttons:
		var button:Button=buttons[section]
		button.set_pressed_no_signal(section==selected)
		app.ui_components._style_button(button,"secondary" if section==selected else "tertiary")
		button.add_theme_color_override("font_color",colors.accent if section==selected else colors.text)
	var style:StyleBoxFlat=app.match_ui._surface(colors.accent,1,10)
	chat_badge.add_theme_stylebox_override("panel",style)
	chat_count.add_theme_color_override("font_color",Color("#241e14") if not app.prefs.get_value("settings","light",false) else Color.WHITE)

func _process(delta: float) -> void:
	# An exclusive popup receives drag/release instead of this viewport. Poll
	# cancellation while a finger is held so it cannot survive a modal or room switch.
	if scroll_finger!=-1 and (not eligible() or scroll_room!=app.room or _modal_open()):_cancel_swipe()
	elapsed+=delta
	if elapsed<.12:return
	elapsed=0.0
	refresh()
