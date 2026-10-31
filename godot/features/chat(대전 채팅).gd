extends RefCounted
## Plain-text participant chat. Room-scoped, bounded, and independent of game actions.
var app
var card: Control
var transcript: RichTextLabel
var entry: LineEdit
var send_button: Button
var hint: Label
var body: VBoxContainer
var toggle: Button
var sending := false
var signature := ""
var current_room := ""
var unread := 0
var last_id := 0
var pending_text := ""
var pending_nonce := ""
var native_thread: Thread
var native_button: Button
var native_open := false
var title_label: Label
var arrow_label: Label
var badge: PanelContainer
var badge_label: Label
var title_icon: TextureRect
var notice: Button
var notice_badge: PanelContainer
var notice_count: Label
var read_timer: Timer

func _init(context: Control) -> void:
	app = context

func build() -> void:
	card = app.match_ui.card(app.side_panel)
	card.get_parent().set_meta("match_compact",true)
	toggle = app._button(card,"대전 채팅 ▾",func():
		body.visible = not body.visible
		if body.visible:
			_scroll_to_bottom.call_deferred()
		_title(),"tertiary")
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.custom_minimum_size.y = 44
	toggle.set_meta("match_disclosure",true)
	var header := HBoxContainer.new()
	header.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	header.offset_left = 6
	header.offset_right = -6
	header.add_theme_constant_override("separation",8)
	toggle.add_child(header)
	title_icon = TextureRect.new()
	title_icon.texture = load("res://ui/icons/match-chat.svg")
	title_icon.custom_minimum_size = Vector2(20,20)
	title_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_icon)
	title_label = app._label(header,"대전 채팅",15)
	title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge = PanelContainer.new()
	badge.custom_minimum_size = Vector2(28,26)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(badge)
	badge_label = app._label(badge,"",13)
	badge_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.add_theme_font_override("font",app._original_font(700))
	arrow_label = app._label(header,"▸",14)
	arrow_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	arrow_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	arrow_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ignore_pointer(header)
	body = VBoxContainer.new()
	body.hide()
	card.add_child(body)
	transcript = RichTextLabel.new()
	transcript.bbcode_enabled = false
	transcript.selection_enabled = true
	transcript.custom_minimum_size.y = 80
	transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript.add_theme_font_size_override("normal_font_size",14)
	body.add_child(transcript)
	var row := HBoxContainer.new()
	body.add_child(row)
	entry = app._field(row,"메시지 입력")
	entry.max_length = 200
	entry.keep_editing_on_text_submit = true
	entry.caret_blink = true
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.custom_minimum_size.x = 0
	entry.text_submitted.connect(func(_text): await send())
	send_button = app._button(row,"전송",send,"primary")
	native_button = app._button(body,"한글 입력창",open_native_editor)
	# Godot 4.7.2 / Microsoft IME regression: godotengine/godot#123269.
	# Project launcher selects 4.7.1; keep fallback only for old Steam launches.
	var engine := Engine.get_version_info()
	native_button.visible = OS.get_name()=="Windows" and engine.major==4 and engine.minor==7 and engine.patch==2 and DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_INPUT)
	native_button.tooltip_text = "한글 앞 음절이 사라질 때 Windows 입력창으로 작성하세요. 확인 후 전송 버튼을 누르세요."
	hint = app._label(body,"두 참가자에게만 표시 · 최대 200자",13)
	_build_notice()
	# A disclosure may be open below the viewport or behind a dialog. Poll its
	# actual clipped geometry after layout, including when no new network data arrives.
	read_timer = Timer.new()
	read_timer.name = "ChatReadVisibility"
	read_timer.wait_time = 0.12
	read_timer.timeout.connect(_sync_read_state)
	app.add_child(read_timer)
	read_timer.start()
	_title()
	card.hide()
	card.get_parent().hide()

func reset() -> void:
	current_room = app.room
	body.hide()
	signature = ""
	last_id = 0
	unread = 0
	entry.clear()
	transcript.text = ""
	pending_text = ""
	pending_nonce = ""
	hint.text = "두 참가자에게만 표시 · 최대 200자"
	_title()

func _title() -> void:
	toggle.text = ""
	arrow_label.text = "▾" if body.visible else "▸"
	badge.visible = unread>0
	badge_label.text = "99+" if unread>99 else str(unread)
	toggle.accessibility_name = "대전 채팅 · "+("읽지 않은 메시지 %d개 · " % unread if unread>0 else "")+("접기" if body.visible else "펼치기")
	_sync_notice()
	apply_theme()

func _build_notice() -> void:
	notice = app.match_ui._tool(app.match_ui.chrome,"chat","읽지 않은 대전 채팅 보기",_jump_to_chat)
	# Replay's static tools are restored during every layout pass. This dynamic
	# disclosure owns its own visibility, while sharing their visual treatment.
	notice.set_meta("match_tool",false)
	notice.set_meta("match_disclosure",true)
	app.match_ui.chrome.move_child(notice,app.match_ui.chrome.get_child_count()-2)
	notice.hide()
	notice_badge = PanelContainer.new()
	notice_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	notice_badge.offset_left = -27
	notice_badge.offset_right = 2
	notice_badge.offset_top = -2
	notice_badge.offset_bottom = 17
	notice.add_child(notice_badge)
	notice_count = app._label(notice_badge,"",10)
	notice_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	notice_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice_count.add_theme_font_override("font",app._original_font(700))
	_ignore_pointer(notice_badge)

func _sync_notice() -> void:
	if not is_instance_valid(notice): return
	var mobile_navigation = app.ui_shell.mobile_navigation
	var footer_active: bool = is_instance_valid(mobile_navigation) and is_instance_valid(mobile_navigation.bar) and mobile_navigation.bar.is_visible_in_tree()
	if is_instance_valid(mobile_navigation):
		mobile_navigation.set_chat_unread(unread if card.is_visible_in_tree() and not app.replay.active else 0)
	var show_notice: bool = unread>0 and card.is_visible_in_tree() and app.game.visible and not app.replay.active and app.split.vertical and not footer_active
	var changed := notice.visible!=show_notice
	notice.visible = show_notice
	notice_count.text = "99+" if unread>99 else str(unread)
	notice.accessibility_name = "읽지 않은 대전 채팅 %d개 · 메시지로 이동" % unread
	# Keep four 44px targets inside a 320px phone header.
	var gap := 4 if show_notice and app.size.x<600 else 14
	if app.match_ui.chrome.get_theme_constant("separation")!=gap:
		app.match_ui.chrome.add_theme_constant_override("separation",gap)
		changed = true
	if changed: app._layout.call_deferred()

func _jump_to_chat() -> void:
	body.show()
	_title()
	await app.get_tree().process_frame
	_scroll_to_bottom()
	await app.get_tree().process_frame
	if app.controls_scroll.is_ancestor_of(body): app.controls_scroll.ensure_control_visible(body)
	app.page_scroll.ensure_control_visible(body)
	await app.get_tree().process_frame
	_sync_read_state.call_deferred()
	# Do not focus the entry: reading a message should not open the phone keyboard.

func _can_read_latest() -> bool:
	if not body.is_visible_in_tree() or not app.game.visible or native_open or app.replay.active: return false
	for window in app.find_children("*","Window",true,false):
		if window.visible and window.exclusive: return false
	var scroll := transcript.get_v_scroll_bar()
	if scroll.value+scroll.page<scroll.max_value-4: return false
	var area := transcript.get_global_rect()
	if area.size.x<=0 or area.size.y<=0: return false
	var visible_area := area.intersection(app.get_viewport_rect())
	var ancestor := transcript.get_parent()
	while ancestor is Control:
		if ancestor.clip_contents:
			visible_area = visible_area.intersection(ancestor.get_global_rect())
		ancestor = ancestor.get_parent()
	# Conservatively require the message viewport to be fully visible. This also
	# protects an expanded card whose header alone is at the bottom of the page.
	return visible_area.size.x>=area.size.x-1 and visible_area.size.y>=area.size.y-1

func _sync_read_state() -> void:
	_sync_notice()
	if unread>0 and _can_read_latest():
		unread = 0
		_title()

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func apply_theme() -> void:
	if not is_instance_valid(badge): return
	var light: bool = app.prefs.get_value("settings","light",false)
	var palette: Dictionary = app.ui_components._palette()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#76521e") if light else Color("#e5bf79")
	style.set_corner_radius_all(13)
	style.content_margin_left = 7
	style.content_margin_right = 7
	badge.add_theme_stylebox_override("panel",style)
	badge_label.add_theme_color_override("font_color",Color.WHITE if light else Color("#241e14"))
	if is_instance_valid(notice_badge):
		var small_style := style.duplicate() as StyleBoxFlat
		small_style.set_corner_radius_all(9)
		small_style.content_margin_left = 3
		small_style.content_margin_right = 3
		notice_badge.add_theme_stylebox_override("panel",small_style)
		notice_count.add_theme_color_override("font_color",Color.WHITE if light else Color("#241e14"))
	title_label.add_theme_color_override("font_color",palette.text)
	title_icon.modulate = style.bg_color if unread>0 else (Color("#525d63") if light else Color("#bbc4c9"))
	arrow_label.add_theme_color_override("font_color",palette.text)

func render() -> void:
	card.visible = bool(app.view.get("chatEnabled",false)) and app.seat!="spectator" and not app.replay.active
	card.get_parent().visible = card.visible
	_sync_notice()
	if not card.visible: return
	if current_room!=app.room: reset()
	var messages: Array = app.view.get("chat",[])
	var next_signature := JSON.stringify(messages)
	if signature==next_signature: return
	var scroll := transcript.get_v_scroll_bar()
	var at_bottom := scroll.value+scroll.page>=scroll.max_value-4
	var old_scroll := scroll.value
	var lines: Array[String] = []
	for message in messages:
		var mine: bool = message.side==app.view.get("yourColor")
		lines.append("%s: %s" % ["나" if mine else str(message.name),str(message.text)])
		if int(message.id)>last_id and not mine: unread += 1
		last_id = maxi(last_id,int(message.id))
	transcript.text = "\n".join(lines) if not lines.is_empty() else "상대에게 인사를 건네보세요."
	signature = next_signature
	if at_bottom: _scroll_to_bottom.call_deferred()
	else: scroll.set_value.call_deferred(old_scroll)
	_title()

func _scroll_to_bottom() -> void:
	transcript.scroll_to_line(maxi(0,transcript.get_line_count()-1))

func send() -> void:
	if sending or app.room.is_empty() or app.seat=="spectator" or app.replay.active or not app.view.get("chatEnabled",false): return
	var text := entry.text.strip_edges()
	if text.is_empty(): return
	if pending_text!=text or pending_nonce.is_empty():
		pending_text = text
		pending_nonce = str(Time.get_ticks_usec())+"-"+str(randi())
	var room_id: String = app.room
	var seat_token: String = app.token
	sending = true
	send_button.disabled = true
	var response: Dictionary = await app.api.request("/chat",{"room":room_id,"token":seat_token,"text":text,"nonce":pending_nonce})
	sending = false
	send_button.disabled = false
	if app.room!=room_id or app.token!=seat_token or app.replay.active: return
	if response.get("ok",false):
		if entry.text.strip_edges()==text: entry.clear()
		pending_text = ""
		pending_nonce = ""
		hint.text = "두 참가자에게만 표시 · 최대 200자"
		await app._poll()
	else: hint.text = str(response.get("msg","전송 실패 · 다시 시도하세요."))

# Workaround for Windows IME syllable loss in the engine's LineEdit path.
# The OS dialog is blocking: run it on its own thread so game polling continues.
# Never touch scene controls from that thread; callbacks are deferred to main.
func open_native_editor() -> void:
	if native_open or sending or app.room.is_empty() or app.replay.active or not app.view.get("chatEnabled",false): return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_INPUT): return
	if entry.has_ime_text(): entry.apply_ime()
	entry.release_focus()
	native_open = true
	native_button.disabled = true
	native_thread = Thread.new()
	var error := native_thread.start(_native_worker.bind(entry.text,str(app.room),str(app.token)))
	if error!=OK:
		native_open = false
		native_button.disabled = false
		native_thread = null
		hint.text = "한글 입력창을 열지 못했습니다."

func _native_worker(draft: String, room_id: String, seat_token: String) -> void:
	var result := DisplayServer.dialog_input_text("Fog Chess · 한글 채팅 입력","최대 200자 · 확인 후 게임에서 전송하세요. 대국 시간은 계속 흐릅니다.",draft,func(value: String):
		_native_result.call_deferred(value,room_id,seat_token))
	_native_finished.call_deferred(result)

func _native_result(value: String, room_id: String, seat_token: String) -> void:
	if app.room!=room_id or app.token!=seat_token or app.replay.active or not app.view.get("chatEnabled",false): return
	entry.text = value.left(200)
	entry.caret_column = entry.text.length()
	hint.text = "내용을 확인한 뒤 전송을 누르세요." if value.length()<=200 else "200자 제한으로 앞 200자만 입력했습니다. 내용을 확인하세요."

func _native_finished(result: int) -> void:
	if native_thread!=null:
		native_thread.wait_to_finish()
		native_thread = null
	native_open = false
	native_button.disabled = false
	if result!=OK: hint.text = "한글 입력창을 열지 못했습니다."
