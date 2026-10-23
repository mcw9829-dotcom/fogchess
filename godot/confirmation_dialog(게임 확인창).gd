extends Window
## Reusable game confirmation. Presentation only; callers own the command.
signal confirmed
signal canceled
var app: Control
var panel: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var actions: BoxContainer
var ok_button: Button
var cancel_button: Button
var shade: ColorRect
var finished := false

class Crest extends Control:
	var ink: Color
	var fill: Color
	var resignation := false
	func _draw() -> void:
		draw_circle(Vector2(26,26),25,fill)
		draw_arc(Vector2(26,26),24,0,TAU,64,Color(ink,.45),1,true)
		if resignation:
			draw_line(Vector2(18,38),Vector2(18,13),ink,2,true)
			draw_polyline(PackedVector2Array([Vector2(18,15),Vector2(25,13),Vector2(34,17),Vector2(34,28),Vector2(25,24),Vector2(18,26)]),ink,2,true)
			draw_line(Vector2(13,38),Vector2(28,38),ink,2,true)
		else:
			draw_arc(Vector2(26,26),12,0,TAU,40,ink,2,true)
			draw_line(Vector2(26,24),Vector2(26,33),ink,2,true)
			draw_circle(Vector2(26,19),1.5,ink)

func build(context: Control, heading: String, message: String, action: String) -> void:
	app = context
	name = "GameConfirmation"
	title = heading
	borderless = true
	transparent = true
	transparent_bg = true
	transient = true
	exclusive = true
	unresizable = true
	set_meta("suppress_hover_tooltips",true)
	var colors: Dictionary = app.ui_components._palette()
	var light: bool = app.prefs.get_value("settings","light",false)
	var gold := Color("#9b780a") if light else Color("#dfbc7e")
	var destructive := heading.contains("기권")
	shade = ColorRect.new()
	shade.name = "ConfirmationDim"
	shade.color = Color(Color("#080e0d"),.70)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(shade)
	visibility_changed.connect(func(): if is_instance_valid(shade): shade.visible = visible)
	tree_exiting.connect(func(): if is_instance_valid(shade): shade.queue_free())
	panel = PanelContainer.new()
	panel.name = "ConfirmationPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := StyleBoxFlat.new()
	frame.bg_color = colors.surface
	frame.border_color = Color(gold,.62)
	frame.set_border_width_all(1)
	frame.border_width_top = 2
	frame.set_corner_radius_all(18)
	frame.content_margin_left = 24
	frame.content_margin_right = 24
	frame.content_margin_top = 20
	frame.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel",frame)
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",20)
	panel.add_child(layout)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation",14)
	layout.add_child(head)
	var crest := Crest.new()
	crest.custom_minimum_size = Vector2(52,52)
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.ink = gold
	crest.fill = Color(gold,.10)
	crest.resignation = destructive
	head.add_child(crest)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation",4)
	head.add_child(titles)
	var eyebrow: Label = app._label(titles,"대국 종료" if destructive else "안개전장",12)
	eyebrow.add_theme_color_override("font_color",gold)
	var title_label: Label = app._label(titles,heading,22)
	title_label.name = "ConfirmationTitle"
	title_label.add_theme_color_override("font_color",colors.text)
	var close: Button = app._button(head,"×",func(): _finish(false),"tertiary")
	close.name = "ConfirmationClose"
	close.custom_minimum_size = Vector2(44,44)
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.add_theme_font_size_override("font_size",24)
	close.accessibility_name = "취소하고 닫기"
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var notice := PanelContainer.new()
	var inset := StyleBoxFlat.new()
	inset.bg_color = colors.button
	inset.set_corner_radius_all(10)
	inset.border_color = Color(gold,.6)
	inset.border_width_left = 2
	inset.content_margin_left = 16
	inset.content_margin_right = 16
	inset.content_margin_top = 16
	inset.content_margin_bottom = 16
	notice.add_theme_stylebox_override("panel",inset)
	content.add_child(notice)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	notice.add_child(body)
	if destructive:
		var outcome: Label = app._label(body,"기권하면 패배로 기록됩니다",16)
		outcome.add_theme_color_override("font_color",colors.text)
	var description: Label = app._label(body,message.replace("기권 패배로 종료한 뒤 홈으로 돌아갑니다.","종료 후 홈으로 돌아갑니다."),14)
	description.name = "ConfirmationDescription"
	description.add_theme_color_override("font_color",colors.muted)
	actions = BoxContainer.new()
	actions.add_theme_constant_override("separation",10)
	layout.add_child(actions)
	ok_button = app._button(actions,action,func(): _finish(true),"danger" if destructive else "secondary")
	ok_button.name = "ConfirmationAccept"
	cancel_button = app._button(actions,"계속하기" if destructive else "취소",func(): _finish(false),"primary")
	cancel_button.name = "ConfirmationCancel"
	for button in [ok_button,cancel_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
	close_requested.connect(func(): _finish(false))
	app.resized.connect(_fit)
	_fit()
	popup_centered(size)
	cancel_button.grab_focus()
	app.ui_motion.enter_window.call_deferred(panel,shade)
	_fit.call_deferred()

func _fit() -> void:
	if not is_instance_valid(panel): return
	var width := mini(480,maxi(240,int(app.size.x)-24))
	actions.vertical = width<420
	var narrow := width<420
	var frame: StyleBoxFlat = panel.get_theme_stylebox("panel")
	frame.content_margin_left = 20 if narrow else 24
	frame.content_margin_right = 20 if narrow else 24
	panel.get_child(0).get_child(0).add_theme_constant_override("separation",10 if narrow else 14)
	find_child("ConfirmationTitle",true,false).add_theme_font_size_override("font_size",18 if narrow else 22)
	# First assign width so wrapped copy participates in the next layout pass.
	size.x = width
	var body_height := content.get_combined_minimum_size().y
	var header_height: float = panel.get_child(0).get_child(0).get_combined_minimum_size().y
	var wanted := ceili(44+40+header_height+body_height+actions.get_combined_minimum_size().y)
	size.y = mini(maxi(260,wanted),maxi(180,int(app.size.y)-24))
	position = Vector2i((app.size-Vector2(size))/2)

func _finish(accept: bool) -> void:
	if finished: return
	finished = true
	set_meta("motion_closing",true)
	set_disable_input(true)
	# Dispatch the actual action immediately; only its visual dismissal takes time.
	if accept: confirmed.emit()
	app.ui_motion.exit_window(panel,shade,func():
		hide()
		if not accept: canceled.emit()
		queue_free())

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		_finish(false)

func get_ok_button() -> Button: return ok_button
func get_cancel_button() -> Button: return cancel_button
