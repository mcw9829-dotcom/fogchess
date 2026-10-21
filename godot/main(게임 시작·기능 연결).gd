extends "res://app_state(공통 상태·변수).gd"
## Scene entry point and compatibility facade. Implement behavior in features/, not here.
var ui_shell = preload("res://features/ui_shell(화면 구성·배치·전환).gd").new(self)
var match_ui = preload("res://features/match_ui(대국 HUD·행동 안내·기보).gd").new(self)
var ui_components = preload("res://features/ui_components(공통 버튼·입력·팝업).gd").new(self)
var game_session = preload("res://features/game_session(입장·재접속·서버 통신).gd").new(self)
var piece_input = preload("res://features/piece_input(기물 선택·이동·공격·능력).gd").new(self)
var game_display = preload("res://features/game_display(타이머·킬로그·기물·결과).gd").new(self)
var matchmaking = preload("res://features/matchmaking(매칭·컴퓨터 대국·친구 초대).gd").new(self)
var account = preload("res://features/account(로그인·복구·프로필·전적).gd").new(self)
var community = preload("res://features/community(순위·패치노트·피드백).gd").new(self)
var help_screens = preload("res://features/help_screens(기물 설명·튜토리얼·인트로).gd").new(self)
var settings = preload("res://features/settings(설정·테마·소리).gd").new(self)

var spectating = preload("res://features/spectating(관전·지연 중계·관전자 수).gd").new(self)

var chat = preload("res://features/chat(대전 채팅).gd").new(self)

var replay = preload("res://features/replay(기보 저장·수순 재생).gd").new(self)

func _ready() -> void:
	prefs.load("user://client.cfg")
	if testing: prefs = ConfigFile.new()
	api = Net.new()
	add_child(api)
	api.base_url = str(prefs.get_value("settings","server","http://127.0.0.1:7556"))
	if testing and not OS.get_environment("FOG_TEST_URL").is_empty(): api.base_url = OS.get_environment("FOG_TEST_URL")
	if OS.has_feature("web"):
		api.base_url = str(JavaScriptBridge.eval("window.location.origin"))
	audio = Audio.new()
	add_child(audio)
	audio.enabled = bool(prefs.get_value("settings","sound",true))
	audio.level = float(prefs.get_value("settings","volume",1.0))
	session = str(prefs.get_value(api.base_url,"session",""))
	_build()
	_apply_theme()
	var timer := Timer.new()
	timer.wait_time = .7
	timer.timeout.connect(_poll)
	add_child(timer)
	timer.start()
	resized.connect(_layout)
	_layout()
	get_tree().auto_accept_quit = false
	if testing: return
	if not session.is_empty():
		var response: Dictionary = await api.request("/me",{"session":session})
		if response.get("ok"): me = response.user
		elif not response.get("network_error"): session = ""; _save()
	_update_account()
	var saved_room := str(prefs.get_value(api.base_url,"room",""))
	var saved_token := str(prefs.get_value(api.base_url,"token",""))
	var invitation := ""
	if OS.has_feature("web"):
		if bool(JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('admin') === '1'")):
			_admin(); return
		invitation = str(JavaScriptBridge.eval("window.location.hash.slice(1)"))
	if not invitation.is_empty() and (invitation.to_upper()!=saved_room.to_upper() or saved_token.is_empty()):
		_open_invitation(invitation); return
	if not saved_room.is_empty() and not saved_token.is_empty():
		await _join({"room":saved_room,"token":saved_token})
	else: _message("")
	if room.is_empty() and not prefs.get_value("settings","intro_seen",false): _intro()

func _message(text: String) -> void:
	if is_instance_valid(notice):
		notice.text = text
		notice.visible = not text.is_empty()

func _report(data: Dictionary) -> bool:
	if data.get("msg"): _message(str(data.msg))
	return bool(data.get("ok",not data.get("network_error",false)))

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		_confirm("종료할까요? 진행 중인 대국은 재접속하지 않으면 자동 기권될 수 있습니다.",func(): _save(); get_tree().quit())

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not selection.is_empty():
		_clear_selection()
		get_viewport().set_input_as_handled()

## Forwarders keep signals, callbacks and existing integration tests stable.
func _build() -> void:
	await ui_shell._build()

func _label(parent: Node,text: String,font_size: int=14) -> Label:
	return ui_components._label(parent,text,font_size)

func _button(parent: Node,text: String,callback: Callable,role: String="secondary") -> Button:
	return ui_components._button(parent,text,callback,role)

func _field(parent: Node,placeholder: String,text: String="",secret: bool=false) -> LineEdit:
	return ui_components._field(parent,placeholder,text,secret)

func _layout() -> void:
	ui_shell._layout()

func _save() -> void:
	settings._save()

func _update_account() -> void:
	account._update_account()

func _join(data: Dictionary) -> void:
	await game_session._join(data)

func _enter(data: Dictionary) -> void:
	game_session._enter(data)

func _poll() -> void:
	await game_session._poll()

func _apply_state(data: Dictionary) -> void:
	game_session._apply_state(data)

func _effect(data: Dictionary) -> void:
	game_display._effect(data)

func _render() -> void:
	game_display._render()

func _rating(value: Variant) -> String:
	return game_display._rating(value)

func _piece_names(items: Array) -> String:
	return game_display._piece_names(items)

func _clear_selection() -> void:
	piece_input._clear_selection()

func _update_selection_ui() -> void:
	piece_input._update_selection_ui()

func _set_mode(value: String) -> void:
	piece_input._set_mode(value)

func _move_targets(captures: bool) -> Array:
	return piece_input._move_targets(captures)

func _choose_action(value: String) -> void:
	piece_input._choose_action(value)

func _show_actions() -> void:
	piece_input._show_actions()

func _select(cell: Vector2i) -> void:
	await piece_input._select(cell)

func _tap(cell: Vector2i) -> void:
	await piece_input._tap(cell)

func _drag(origin: Vector2i,target: Vector2i) -> void:
	await piece_input._drag(origin,target)

func _act(body: Dictionary) -> void:
	await game_session._act(body)

func _promotion() -> void:
	await game_session._promotion()

func _leave_prompt() -> void:
	await game_session._leave_prompt()

func _return_home() -> void:
	game_session._return_home()

func _refresh_profile() -> void:
	await account._refresh_profile()

func _match_command(command: String) -> void:
	await matchmaking._match_command(command)

func _match_update(data: Dictionary) -> void:
	await matchmaking._match_update(data)

func _window(title: String) -> Array:
	return ui_components._window(title)

func _confirm(text: String,callback: Callable) -> void:
	ui_components._confirm(text,callback)

func _form(title: String,definitions: Array,submit: Callable) -> void:
	await ui_components._form(title,definitions,submit)

func _account() -> void:
	await account._account()

func _authenticated(data: Dictionary) -> void:
	account._authenticated(data)

func _recovery(code: String,subtitle: String="가입 완료! 이 코드는 지금 한 번만 보여요.",back: bool=false) -> void:
	account._recovery(code,subtitle,back)

func _leaderboard() -> void:
	await community._leaderboard()

func _history() -> void:
	community._history()

func _patchnotes() -> void:
	await community._patchnotes()

func _feedback() -> void:
	await community._feedback()

func _help() -> void:
	help_screens._help()

func _tutorial() -> void:
	await help_screens._tutorial()

func _settings() -> void:
	settings._settings()

func _apply_theme() -> void:
	settings._apply_theme()

func _card(parent: Node, title: String) -> VBoxContainer:
	return ui_components._card(parent,title)

func _tint_button(button: Button, color: Color, dark_text: bool=false) -> void:
	ui_components._tint_button(button,color,dark_text)

func _mode_card(parent: Node,title: String,description: String,icon: String,callback: Callable,primary: bool=false) -> void:
	ui_components._mode_card(parent,title,description,icon,callback,primary)

func _ignore_mouse(node: Control) -> void:
	ui_components._ignore_mouse(node)

func _bot_menu() -> void:
	await matchmaking._bot_menu()

func _friend_menu() -> void:
	await matchmaking._friend_menu()

func _load_home_ranks() -> void:
	await community._load_home_ranks()

func _navigation_home() -> void:
	ui_shell._navigation_home()

func _subscreen(title: String, description: String="") -> VBoxContainer:
	return ui_shell._subscreen(title,description)

func _icon(parent: Node,key: String,dimension: int=24) -> Control:
	return ui_components._icon(parent,key,dimension)

func _nav(parent: Node,text: String,icon: String,callback: Callable) -> Button:
	return ui_components._nav(parent,text,icon,callback)

func _nav_active(text: String) -> void:
	ui_shell._nav_active(text)

func _style_mode_card(button: Button) -> void:
	ui_components._style_mode_card(button)

func _connection_settings() -> void:
	settings._connection_settings()

func _toggle_sound() -> void:
	settings._toggle_sound()

func _intro(step: int=0) -> void:
	await help_screens._intro(step)

func _effect_preview() -> void:
	help_screens._effect_preview()

func _render_feed() -> void:
	game_display._render_feed()

func _feed_icon(parent: Node, kind: String, color: String) -> TextureRect:
	return game_display._feed_icon(parent,kind,color)

func _auth_form(signup: bool=false) -> void:
	await account._auth_form(signup)

func _rank_row(parent: Node, player: Dictionary, index: int) -> void:
	community._rank_row(parent,player,index)

func _small_window(title: String,width: int=380,height: int=560) -> Array:
	return ui_components._small_window(title,width,height)

func _matches(pattern: String,value: String) -> bool:
	return account._matches(pattern,value)

func _password_problem(value: String) -> String:
	return account._password_problem(value)

func _password_checks(parent: Node,field: LineEdit) -> void:
	account._password_checks(parent,field)

func _find_account() -> void:
	await account._find_account()

func _clear_form(parent: Node) -> void:
	ui_components._clear_form(parent)

func _profile_form(parent: Node,section: String,status: Label,display_name: Label) -> void:
	await account._profile_form(parent,section,status,display_name)

func _profile_history(parent: Node) -> void:
	await account._profile_history(parent)

func _fx_origin(_kind: String,_cells: Array) -> Variant:
	return game_display._fx_origin(_kind,_cells)

func _form_action(parent: Node,title: String,subtitle: String,icon: String,primary: bool=false) -> Button:
	return ui_components._form_action(parent,title,subtitle,icon,primary)

func _rich(parent: Node,text: String,font_size: int=13) -> RichTextLabel:
	return ui_components._rich(parent,text,font_size)

func _tier(rating: int) -> String:
	return community._tier(rating)

func _render_result() -> void:
	await game_display._render_result()

func _original_font(weight: int=400) -> Font:
	return ui_components._original_font(weight)

func _open_invitation(code: String) -> void:
	game_session._open_invitation(code)

func _admin() -> void:
	community._admin()

func _game_menu() -> void:
	await game_display._game_menu()

func _board_help() -> void:
	game_display._board_help()
