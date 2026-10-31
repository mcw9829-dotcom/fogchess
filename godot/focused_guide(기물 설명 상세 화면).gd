extends VBoxContainer
## Focused learning view. Rule copy and animation frames come from the existing guide data.
const Demo = preload("res://focused_guide_demo(단계별 기물 시연).gd")
const SceneData = preload("res://original_demo(원본 시연 재현).gd")
const KINDS = ["P","N","B","R","Q","K"]
const NAMES = {"P":"폰","N":"나이트","B":"비숍","R":"전차","Q":"퀸","K":"킹"}
const STAGE_NAMES = {"move":"행마","attack":"공격","ability":"능력"}
const RULE_KEYS = {"move":"move","attack":"atk","ability":"abil"}
var app
var dialog: Window
var kind := "P"
var stage := "move"
var spec: Dictionary = {}
var demo: Control
var piece_tabs: GridContainer
var stage_tabs: HBoxContainer
var piece_buttons: Dictionary = {}
var stage_buttons: Dictionary = {}
var body_scroll: ScrollContainer
var columns: BoxContainer
var scene_column: VBoxContainer
var demo_center: CenterContainer
var detail: VBoxContainer
var piece_name: Label
var role: Label
var rule_heading: Label
var rule_body: RichTextLabel
var playback: Label
var replay: Button
var stop_button: Button
var secondary_note: Label
var rule_surface: PanelContainer
var built := false
var compact := false
var palette_key := ""

func _init(context: Control, window: Window) -> void:
	app = context
	dialog = window

func _ready() -> void:
	name = "FocusedPieceGuide"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	piece_tabs = GridContainer.new()
	piece_tabs.name = "GuidePieceTabs"
	piece_tabs.columns = 6
	piece_tabs.add_theme_constant_override("h_separation",8)
	piece_tabs.add_theme_constant_override("v_separation",8)
	add_child(piece_tabs)
	for piece_kind in KINDS:
		var button: Button = app._button(piece_tabs,NAMES[piece_kind],select_piece.bind(piece_kind))
		button.name = "GuidePiece_"+piece_kind
		button.icon = load("res://pieces/Chess_%slt45.svg" % str(piece_kind).to_lower())
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",22)
		button.add_theme_constant_override("h_separation",6)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.accessibility_name = NAMES[piece_kind]+" 설명"
		piece_buttons[piece_kind] = button
	body_scroll = ScrollContainer.new()
	body_scroll.name = "GuideContentScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body_scroll)
	columns = BoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation",28)
	body_scroll.add_child(columns)
	scene_column = VBoxContainer.new()
	scene_column.add_theme_constant_override("separation",8)
	columns.add_child(scene_column)
	playback = app._label(scene_column,"",12)
	playback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playback.autowrap_mode = TextServer.AUTOWRAP_OFF
	demo_center = CenterContainer.new()
	demo_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_column.add_child(demo_center)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation",12)
	columns.add_child(detail)
	piece_name = app._label(detail,"",28)
	role = app._label(detail,"",13)
	stage_tabs = HBoxContainer.new()
	stage_tabs.name = "GuideStageTabs"
	stage_tabs.add_theme_constant_override("separation",8)
	detail.add_child(stage_tabs)
	for phase in ["move","attack","ability"]:
		var button: Button = app._button(stage_tabs,STAGE_NAMES[phase],select_stage.bind(phase))
		button.name = "GuideStage_"+phase
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_buttons[phase] = button
	rule_surface = PanelContainer.new()
	detail.add_child(rule_surface)
	var rule_column := VBoxContainer.new()
	rule_column.add_theme_constant_override("separation",10)
	rule_surface.add_child(rule_column)
	rule_heading = app._label(rule_column,"",18)
	rule_body = app._rich(rule_column,"",16)
	rule_body.name = "GuideRuleText"
	rule_body.add_theme_constant_override("line_separation",5)
	secondary_note = app._label(detail,"",12)
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation",8)
	detail.add_child(links)
	app._button(links,"1분 안내",func(): dialog.hide(); dialog.queue_free(); app._intro(),"tertiary")
	app._button(links,"왕 찾기 미션",func(): dialog.hide(); dialog.queue_free(); app._tutorial(),"tertiary")
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",8)
	add_child(footer)
	replay = app._button(footer,"시연 재생",func(): demo.restart(),"primary")
	replay.name = "GuideReplay"
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_button = app._button(footer,"정지",func(): demo.stop())
	stop_button.name = "GuideStop"
	stop_button.custom_minimum_size.x = 76
	built = true
	resized.connect(_layout.call_deferred)
	select_piece("P",false)
	_layout.call_deferred()

func select_piece(value: String, autoplay: bool=true) -> void:
	if not value in KINDS: return
	kind = value
	for entry in SceneData.scenes().guide:
		if str(entry.t)==kind: spec = entry; break
	if is_instance_valid(demo):
		demo.stop()
		demo_center.remove_child(demo)
		demo.queue_free()
	demo = Demo.new()
	demo.name = "FocusedGuideDemo"
	demo.kind = kind
	demo.effects = app.board.effects
	demo.sound = app.audio.cue
	demo_center.add_child(demo)
	demo.playback_changed.connect(_update_playback)
	demo.caption_changed.connect(func(_caption): _update_playback(demo.running))
	if not demo.has_stage(stage): stage = "move"
	demo.set_stage(stage,autoplay)
	piece_name.text = NAMES[kind]
	role.text = str(spec.nm)
	for phase in stage_buttons:
		stage_buttons[phase].disabled = not demo.has_stage(phase)
	secondary_note.text = "행마·공격을 선택해 동작을 확인하세요." if not spec.has("abil") else "행마·공격·능력을 선택해 동작을 확인하세요."
	body_scroll.scroll_vertical = 0
	_update_rule()
	_update_playback(demo.running)
	_style()
	_layout.call_deferred()

func select_stage(value: String) -> void:
	if not is_instance_valid(demo) or not demo.has_stage(value): return
	stage = value
	demo.set_stage(stage,true)
	_update_rule()
	_style()

func _update_rule() -> void:
	var ability_name: String = {"B":"저격","R":"돌파 사격","Q":"스캔"}.get(kind,"능력")
	rule_heading.text = ability_name if stage=="ability" else STAGE_NAMES[stage]
	# Preserve every original rule phrase; normalize existing emphasis for RichTextLabel.
	var text: String = str(spec.get(RULE_KEYS[stage],""))
	rule_body.text = text.replace("<b>","[b]").replace("</b>","[/b]").replace(". ",".\n\n")

func _update_playback(_playing: bool=false) -> void:
	if not is_instance_valid(demo): return
	var label: String = {"move":"행마","attack":"공격","ability":{ "B":"저격","R":"돌파 사격","Q":"스캔"}.get(kind,"능력")}.get(stage,"시연")
	playback.text = ("재생 중 · " if demo.running else "시연 대기 · ")+label
	replay.text = "처음부터 다시 보기" if demo.running else "시연 재생"
	stop_button.disabled = not demo.running

func _layout() -> void:
	if not built or size.x<=0: return
	# Window width is authoritative: minimum child widths must not feed back into layout.
	compact = dialog.size.x<720
	piece_tabs.columns = 3 if compact else 6
	columns.vertical = compact
	columns.add_theme_constant_override("separation",16 if compact else 28)
	var stage_parent: Node = self if compact else detail
	if stage_tabs.get_parent()!=stage_parent:
		stage_tabs.reparent(stage_parent)
		stage_parent.move_child(stage_tabs,1 if compact else 2)
	var board_side := clampf(float(dialog.size.x)-44,200,284) if compact else minf(400,maxf(280,size.x*.42))
	scene_column.custom_minimum_size.x = 0 if compact else board_side
	detail.custom_minimum_size.x = 0
	if is_instance_valid(demo): demo.custom_minimum_size = Vector2.ONE*board_side
	piece_name.add_theme_font_size_override("font_size",22 if compact else 28)
	role.visible = not compact
	_style()

func _style() -> void:
	if not built: return
	var colors: Dictionary = app.ui_components._palette()
	var light: bool = app.prefs.get_value("settings","light",false)
	var blue := Color("#35618b") if light else Color("#9dcceb")
	for piece_kind in piece_buttons:
		var button: Button = piece_buttons[piece_kind]
		var active: bool = piece_kind==kind
		button.set_pressed_no_signal(active)
		app.ui_components._style_button(button,"primary" if active else "secondary")
		button.add_theme_font_size_override("font_size",13 if compact else 14)
		button.add_theme_constant_override("icon_max_width",18 if compact else 22)
		button.add_theme_constant_override("h_separation",4 if compact else 6)
		# Three labelled piece tabs must fit even in a 296px dialog (320px viewport).
		for state in ["normal","hover","pressed","focus","disabled"]:
			var tab_style: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
			tab_style.content_margin_left = 6 if compact else 12
			tab_style.content_margin_right = 6 if compact else 12
			button.add_theme_stylebox_override(state,tab_style)
	for phase in stage_buttons:
		var button: Button = stage_buttons[phase]
		var active: bool = phase==stage
		button.set_pressed_no_signal(active)
		app.ui_components._style_button(button,"secondary")
		if active:
			var selected: StyleBoxFlat = app.ui_components._button_style("secondary","normal")
			selected.bg_color = colors.surface.lerp(blue,.12)
			selected.border_color = blue
			button.add_theme_stylebox_override("normal",selected)
			button.add_theme_stylebox_override("pressed",selected)
			button.add_theme_color_override("font_color",blue)
			button.add_theme_color_override("font_pressed_color",blue)
	var panel := StyleBoxFlat.new()
	panel.bg_color = colors.button
	panel.border_color = colors.border
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	for edge in ["left","right","top","bottom"]: panel.set("content_margin_"+edge,16.0)
	rule_surface.add_theme_stylebox_override("panel",panel)
	rule_body.add_theme_color_override("default_color",colors.text)
	rule_heading.add_theme_color_override("font_color",blue)
	for label in [role,playback,secondary_note]: label.add_theme_color_override("font_color",colors.muted)
	palette_key = str(light)

func _process(_delta: float) -> void:
	if built and palette_key!=str(bool(app.prefs.get_value("settings","light",false))): _style()
