extends VBoxContainer
## Home presentation only. Existing session, matching, tutorial and replay actions own behavior.
var computer_note: Label
var app
var columns: HBoxContainer
var utility_row: VBoxContainer
var brand: HBoxContainer
var brand_mark: TextureRect
var menu_column: VBoxContainer
var preview_column: VBoxContainer
var preview_board: Control
var headline: Label
var subtitle: Label
var headers: Dictionary = {}
var captions: Dictionary = {}
var section_icons: Dictionary = {}
var backdrop: Control
var account_note: Label
var account_action: Button
var panes: Dictionary = {}
var actions: Dictionary = {}
var selected := "computer"
var level_buttons: Array[Button] = []
var room_code: LineEdit
var rank_action: Button
var rank_note: Label
var local_note: Label
var signature := ""
var compact := false
const ORDER = ["rank","computer","friends","practice","records","options","account"]
const MAIN_ORDER = ["rank","computer","friends","practice"]
const UTILITY_ORDER = ["records","options","account"]
const HEADLINE_FONT = preload("res://fonts/lobby_title.tres")
const BRAND_DARK = preload("res://ui/brand/open-sight-dark.svg")
const BRAND_LIGHT = preload("res://ui/brand/open-sight-light.svg")
const TITLES = {"rank":"랭크 매칭","computer":"컴퓨터와 대국","friends":"친구와 대국","practice":"연습 · 기물 설명","records":"기록 · 관전","options":"설정 · 소식","account":"내 계정"}

class Reveal extends Control:
	var body := VBoxContainer.new()
	var expanded := false
	var motion: Tween
	var revision := 0
	var measuring := false
	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_theme_constant_override("separation",6)
		add_child(body)
		resized.connect(_width)
		body.minimum_size_changed.connect(_content_changed.call_deferred)
	func _width() -> void:
		body.size = Vector2(size.x,0)
	func _content_changed() -> void:
		_width()
		if expanded and not measuring and (not is_instance_valid(motion) or not motion.is_running()):
			custom_minimum_size.y = body.get_combined_minimum_size().y+8
	func reveal(value: bool, animate: bool) -> void:
		revision += 1
		expanded = value
		if is_instance_valid(motion): motion.kill()
		body.show()
		_width()
		measuring = value
		if value:
			_measure_and_open.call_deferred(revision,animate)
		else:
			_transition(0.0,false,animate)
	func _measure_and_open(request: int, animate: bool) -> void:
		# Wrapped labels need a layout frame at the real column width before we
		# measure the opening height. A later selection cancels this request.
		await get_tree().process_frame
		if request!=revision or not expanded: return
		_width()
		measuring = false
		_transition(body.get_combined_minimum_size().y+8,true,animate)
	func _transition(height: float, value: bool, animate: bool) -> void:
		if not animate:
			custom_minimum_size.y = height
			body.modulate.a = 1.0 if value else 0.0
			body.visible = value
			return
		motion = create_tween().set_parallel(true)
		motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		motion.tween_property(self,"custom_minimum_size:y",height,.28 if value else .20)
		motion.tween_property(body,"modulate:a",1.0 if value else 0.0,.22 if value else .12)
		motion.chain().tween_callback(func():
			body.visible = expanded
			_content_changed.call_deferred())

func _init(context: Control) -> void: app = context

func _ready() -> void:
	name = "LobbyHome"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",20)
	backdrop = preload("res://features/lobby_backdrop(로비의 가벼운 배경).gd").new()
	app.add_child(backdrop)
	app.move_child(backdrop,0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.home.visibility_changed.connect(func(): backdrop.set_lobby_visible(app.home.visible))
	brand = HBoxContainer.new()
	brand.add_theme_constant_override("separation",8)
	add_child(brand)
	brand_mark = TextureRect.new()
	brand_mark.texture = BRAND_DARK
	brand_mark.custom_minimum_size = Vector2(32,32)
	brand_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	brand_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	brand_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand.add_child(brand_mark)
	var brand_name: Label = app._label(brand,"안개전장",16)
	brand_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	headline = app._label(self,"Make Your Move",44)
	headline.add_theme_font_override("font",HEADLINE_FONT)
	subtitle = app._label(self,"전장을 읽고, 한 수 앞서 나가세요.",13)
	columns = HBoxContainer.new()
	columns.add_theme_constant_override("separation",40)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(columns)
	menu_column = VBoxContainer.new()
	menu_column.name = "LobbyMenu"
	menu_column.add_theme_constant_override("separation",2)
	menu_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	columns.add_child(menu_column)
	for key in MAIN_ORDER: _section(key)
	var utility_space := Control.new()
	utility_space.custom_minimum_size.y = 8
	menu_column.add_child(utility_space)
	utility_row = VBoxContainer.new()
	utility_row.name = "LobbyUtilities"
	utility_row.add_theme_constant_override("separation",6)
	menu_column.add_child(utility_row)
	for key in UTILITY_ORDER: _section(key,true)
	preview_column = VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_column.add_theme_constant_override("separation",12)
	columns.add_child(preview_column)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	preview_column.add_child(center)
	preview_board = app.Board.new()
	center.add_child(preview_board)
	preview_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_board.effects = false
	preview_board.set_view(_illustration(),false)
	preview_board.fog_display_strength = 0.0
	preview_board.set_process(false)
	preview_board.fx.set_process(false)
	preview_board.targeting.set_process(false)
	var caption: Label = app._label(preview_column,"안개 너머를 읽는 한 수",16)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint: Label = app._label(preview_column,"보드 미리보기",11)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = .65
	_build_actions()
	local_note = app._label(panes.friends.body,"",12)
	local_note.accessibility_live = AccessibilityServer.LIVE_POLITE
	local_note.hide()
	for key in ORDER: panes[key].reveal(key==selected,false)
	apply_theme()
	_sync_state()

func _section(key: String, utility: bool=false) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation",4)
	(utility_row if utility else menu_column).add_child(group)
	var button_parent: Node = group
	var button: Button = app._button(button_parent,"",func(): select_section("" if selected==key else key),"tertiary")
	button.name = "LobbySection_"+key
	button.custom_minimum_size.y = 44 if utility else 64
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_stretch_ratio = 1.0
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed:
			if event.keycode in [KEY_UP,KEY_DOWN]:
				var i: int = ORDER.find(key)
				headers[ORDER[posmod(i+(-1 if event.keycode==KEY_UP else 1),ORDER.size())]].grab_focus()
				button.accept_event()
			elif event.keycode==KEY_ESCAPE and selected==key: select_section(""); button.accept_event())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14; row.offset_right = -12
	row.add_theme_constant_override("separation",12)
	var icon: Control = app._icon(row,{"rank":"play","computer":"computer","friends":"people","practice":"book","records":"replay","options":"settings","account":"user"}[key],24 if utility else 34)
	icon.visible = true
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var label: Label = app._label(row,TITLES[key],18 if utility else 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var pane := Reveal.new()
	group.add_child(pane)
	headers[key] = button
	captions[key] = label
	section_icons[key] = icon
	panes[key] = pane
	actions[key] = []

func _action(key: String, text: String, callback: Callable, role: String="secondary", parent: Node=null) -> Button:
	var button: Button = app._button(panes[key].body if parent==null else parent,text,callback,role)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions[key].append(button)
	return button

func _note(key: String, text: String) -> Label:
	var label: Label = app._label(panes[key].body,text,13)
	label.modulate.a = .78
	return label

func _build_actions() -> void:
	rank_note = _note("rank","비슷한 레이팅의 상대와 대국")
	rank_action = _action("rank","",func(): await app._match_command("join"),"primary")
	_action("rank","리더보드 · 레이팅 규칙",app._leaderboard)
	_note("computer","난이도를 고르세요")
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation",6)
	panes.computer.body.add_child(levels)
	for i in range(3):
		var button := _action("computer",["쉬움","보통","어려움"][i],func(): app.level.selected=i; _style_levels(),"secondary",levels)
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size",13)
		level_buttons.append(button)
	_action("computer","대국 시작",func(): await app._join({"vs_bot":true,"level":["easy","normal","hard"][app.level.selected]}),"primary")
	computer_note = _note("computer","승리 시 레이팅 상승 · 패배 시 하락 없음")
	_note("friends","방을 만들거나 친구의 코드를 입력하세요")
	_action("friends","방 만들기",func(): await app._join({}),"primary")
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation",6)
	panes.friends.body.add_child(join_row)
	room_code = app._field(join_row,"방 코드",app.code_field.text)
	room_code.max_length = 8
	room_code.custom_minimum_size.x = 0
	room_code.expand_to_text_length = false
	room_code.accessibility_name = "친구 방 코드"
	room_code.text_changed.connect(func(value): app.code_field.text=value)
	room_code.text_submitted.connect(func(_value): join_friend())
	var join_button := _action("friends","참가",join_friend,"secondary",join_row)
	join_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_note("friends","친구 대국은 레이팅에 반영되지 않습니다")
	# Keep the existing learning progression and callback, instead of duplicating its state.
	app.game_ux.learn_note.reparent(panes.practice.body)
	app.game_ux.learn_button.reparent(panes.practice.body)
	actions.practice.append(app.game_ux.learn_button)
	var learning_row := HBoxContainer.new()
	learning_row.add_theme_constant_override("separation",6)
	panes.practice.body.add_child(learning_row)
	_action("practice","혼자 연습",func(): await app._join({"solo":true}),"secondary",learning_row)
	_action("practice","처음 안내 · 1분",app._intro)
	_action("practice","기물 설명",app._help,"secondary",learning_row)
	_action("records","리플레이",app.replay.menu)
	_action("records","대국 관전",app.spectating.menu)
	_action("options","게임 설정",app._settings)
	_action("options","공지 · 점검 안내",func(): preload("res://support(공지·제보·이의제기).gd").new(app).announcements())
	var news_row = HBoxContainer.new()
	news_row.add_theme_constant_override("separation",6)
	panes.options.body.add_child(news_row)
	_action("options","피드백 보내기",app._feedback,"secondary",news_row)
	_action("options","패치노트",app._patchnotes,"secondary",news_row)
	account_note = _note("account","")
	account_action = _action("account","로그인 · 회원가입",app._account,"primary")
	_action("account","제재 안내 · 이의제기",func(): preload("res://support(공지·제보·이의제기).gd").new(app).show_support())

func join_friend() -> void:
	if app.busy or app.matching or selected!="friends": return
	var code := room_code.text.strip_edges().to_upper()
	if code.is_empty():
		local_note.text = "방 코드를 입력하세요."
		local_note.show()
		room_code.grab_focus()
		return
	local_note.hide()
	app.code_field.text = code
	await app._join({"room":code})

func select_section(key: String, animate: bool=true) -> void:
	if app.busy: return
	selected = key
	local_note.hide()
	for section in ORDER:
		var focus: Control = get_viewport().gui_get_focus_owner()
		if section!=key and is_instance_valid(focus) and panes[section].is_ancestor_of(focus): headers[section].grab_focus()
		panes[section].reveal(section==key,animate)
	apply_theme()
	signature = ""
	_sync_state()

func _process(_delta: float) -> void:
	if is_visible_in_tree(): _sync_state()

func _sync_state() -> void:
	var next = str([app.busy,app.matching,app.session.is_empty(),app.me.get("rating"),app.me.get("name"),selected])
	if next==signature: return
	signature = next
	var blocked: bool = app.busy
	for key in ORDER:
		headers[key].disabled = blocked
		for button in actions[key]: button.disabled = blocked or key!=selected or (app.matching and key in ["friends","records","account"])
	room_code.editable = not blocked and not app.matching and selected=="friends"
	room_code.focus_mode = Control.FOCUS_ALL if selected=="friends" else Control.FOCUS_NONE
	account_note.text = "게스트로 플레이 중" if app.session.is_empty() else "%s · %d점" % [str(app.me.get("name","플레이어")),int(app.me.get("rating",1000))]
	account_action.text = "로그인 · 회원가입" if app.session.is_empty() else "내 프로필 · 전적"
	rank_action.disabled = blocked or app.matching or selected!="rank"
	computer_note.text = "매칭 대기용 연습 · 레이팅·전적 미반영" if app.matching else "승리 시 레이팅 상승 · 패배 시 하락 없음"
	rank_action.text = "로그인하고 매칭" if app.session.is_empty() else "랭크 매칭 시작"
	rank_note.text = "로그인 후 비슷한 레이팅의 상대를 찾습니다" if app.session.is_empty() else "내 레이팅 %d점 · 비슷한 상대와 대국" % int(app.me.get("rating",1000))

func _style_levels() -> void:
	for i in range(level_buttons.size()):
		level_buttons[i].set_pressed_no_signal(i==app.level.selected)
		app.ui_components._style_button(level_buttons[i],"primary" if i==app.level.selected else "secondary")
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBoxFlat = level_buttons[i].get_theme_stylebox(state)
			style.content_margin_left = 8
			style.content_margin_right = 8

func apply_theme() -> void:
	if not is_instance_valid(subtitle): return
	var colors: Dictionary = app.ui_components._palette()
	var gold := Color("#946921") if app.prefs.get_value("settings","light",false) else Color("#e4bf78")
	backdrop.set_light(bool(app.prefs.get_value("settings","light",false)))
	brand_mark.texture = BRAND_LIGHT if app.prefs.get_value("settings","light",false) else BRAND_DARK
	subtitle.add_theme_color_override("font_color",colors.muted)
	for key in ORDER:
		var active: bool = selected==key
		var button: Button = headers[key]
		button.set_pressed_no_signal(active)
		button.accessibility_name = TITLES[key]+(" · 펼쳐짐, 접기" if active else " · 하위 메뉴 펼치기")
		captions[key].add_theme_color_override("font_color",gold if active else colors.text)
		for state in ["normal","hover","pressed","disabled","focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT
			style.border_color = gold if active else Color(colors.border,.65)
			style.border_width_left = 3 if active else 0
			style.border_width_bottom = 0 if active else 1
			style.set_corner_radius_all(3)
			if state=="hover": style.bg_color = Color(gold,.065)
			if state=="pressed": style.bg_color = Color(gold,.11)
			if state=="focus":
				style.set_border_width_all(1)
				style.border_color = gold
			button.add_theme_stylebox_override(state,style)
	_style_levels()

func layout(available: float) -> void:
	if not is_instance_valid(columns): return
	compact = available < 730
	# Queue/resume cards consume scroll space, not the physical viewport.
	# Keep typography and preview scale stable when these cards appear.
	var usable_height: float = app.get_viewport_rect().size.y
	var short_window: bool = not compact and usable_height < 800
	var very_short: bool = not compact and usable_height < 660
	brand.visible = not very_short
	subtitle.visible = not very_short
	utility_row.add_theme_constant_override("separation",2 if very_short else 6)
	menu_column.add_theme_constant_override("separation",0 if very_short else 2)
	for pane in panes.values(): pane.body.add_theme_constant_override("separation",4 if very_short else 6)
	preview_column.visible = not compact
	menu_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	menu_column.custom_minimum_size.x = 0 if compact else (370 if available>940 else 320)
	columns.add_theme_constant_override("separation",60 if available>940 else 32)
	headline.add_theme_font_size_override("font_size",32 if compact else (26 if very_short else (36 if short_window else 44)))
	# Leave a small fit margin at ordinary 760px desktop heights; a single
	# wrapped line must not create a near-empty scrollbar for the whole lobby.
	add_theme_constant_override("separation",6 if short_window else (10 if compact else 14))
	for key in ORDER:
		var utility: bool = key in UTILITY_ORDER
		# Preserve the primary/utility hierarchy even in short, scroll-free windows.
		headers[key].custom_minimum_size.y = 44 if utility else (48 if very_short else (52 if short_window else (60 if compact else 64)))
		captions[key].add_theme_font_size_override("font_size",(16 if short_window else 18) if utility else (22 if compact or very_short else (24 if short_window else 28)))
		var icon_side := (24 if not short_window else 22) if utility else (30 if compact or short_window else 34)
		section_icons[key].custom_minimum_size = Vector2.ONE*icon_side
		section_icons[key].queue_redraw()
		for button in actions[key]:
			button.custom_minimum_size.y = 40 if short_window else 44
		panes[key]._content_changed.call_deferred()
	if not compact:
		# The bounded, scroll-free menu keeps every section visible. The preview
		# remains top-aligned and independent of the accordion's animated height.
		var side := minf(available-menu_column.custom_minimum_size.x-columns.get_theme_constant("separation")-24,maxf(180,usable_height-280))
		side = minf(520.0,side*.84)
		preview_board.custom_minimum_size = Vector2.ONE*side
		preview_board.size = Vector2.ONE*side

func _illustration() -> Dictionary:
	# Authored illustration, independent from any live room or hidden opponent state.
	var grid: Array = []
	for r in range(12):
		var row: Array = []
		for c in range(12): row.append({"f":1 if r<7 and (c<7 or r<3) else 0,"t":0})
		grid.append(row)
	for rc in [[2,1],[2,2],[2,6],[3,6],[5,3],[6,9],[7,4],[8,7]]: grid[rc[0]][rc[1]].t=1
	for rc in [[3,3],[4,8],[5,1],[5,2],[6,5],[7,8],[8,4],[8,5],[8,6],[9,1],[9,9]]: grid[rc[0]][rc[1]].t=3
	for c in [1,2,4,5,7,8,10]: grid[10][c].p={"t":"P","o":"W"}
	for unit in [[11,2,"R"],[11,4,"Q"],[11,5,"K"],[11,6,"B"],[11,8,"N"],[11,9,"R"],[7,5,"B"],[5,8,"N"]]: grid[unit[0]][unit[1]].p={"t":unit[2],"o":"W"}
	# Balance the authored lobby scene with a visible opposing formation.
	for c in [1,3,4,6,7,9,10]: grid[1][c].p={"t":"P","o":"B"}
	for unit in [[0,2,"R"],[0,3,"N"],[0,5,"B"],[0,6,"K"],[0,7,"Q"],[0,9,"R"],[4,6,"B"]]: grid[unit[0]][unit[1]].p={"t":unit[2],"o":"B"}
	grid[4][8].p={"t":"N","o":"B"}
	return {"room":"lobby-art","phase":"preview","grid":grid,"yourColor":"W"}
