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

func _init(context: Control) -> void:
	app = context

func build() -> void:
	card = app.match_ui.card(app.side_panel)
	card.get_parent().set_meta("match_compact",true)
	toggle = app._button(card,"대전 채팅 ▾",func():
		body.visible = not body.visible
		if body.visible: unread = 0
		_title(),"tertiary")
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size",12)
	toggle.icon = load("res://ui/icons/match-chat.svg")
	toggle.expand_icon = true
	toggle.add_theme_constant_override("icon_max_width",16)
	toggle.set_meta("match_disclosure",true)
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
	hint = app._label(body,"두 참가자에게만 표시 · 최대 200자",11)
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
	toggle.text = "대전 채팅 %s%s" % ["▾" if body.visible else "▸", " · 새 메시지 %d" % unread if unread>0 else ""]

func render() -> void:
	card.visible = bool(app.view.get("chatEnabled",false)) and app.seat!="spectator" and not app.replay.active
	card.get_parent().visible = card.visible
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
		if int(message.id)>last_id and not mine and not body.visible: unread += 1
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
