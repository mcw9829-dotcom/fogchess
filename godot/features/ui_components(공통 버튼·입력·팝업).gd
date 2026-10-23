extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app

class DismissibleWindow extends Window:
	func _unhandled_key_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			set_input_as_handled()
			close_requested.emit()

func _init(context: Control) -> void:
	app = context

func _label(parent: Node,text: String,font_size: int=14) -> Label:
	var label = Label.new()
	label.text = text
	if font_size>=16: label.add_theme_font_override("font",app._original_font(700))
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

func _button(parent: Node,text: String,callback: Callable,role: String="secondary") -> Button:
	var button = Button.new()
	button.text = text
	button.accessibility_name = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size",14)
	button.pressed.connect(callback)
	if text.begins_with("← 뒤로"):
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		role = "tertiary"
	_style_button(button,role)
	parent.add_child(button)
	app.ui_motion.attach(button)
	return button

func _field(parent: Node,placeholder: String,text: String="",secret: bool=false) -> LineEdit:
	var field = LineEdit.new()
	field.placeholder_text = placeholder
	field.text = text
	field.secret = secret
	field.custom_minimum_size.y = 42
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field

func _window(title: String) -> Array:
	# Hide the preceding dialog before opening another exclusive window.
	# queue_free() alone runs at frame end and otherwise leaves two active modals.
	for child in app.get_children():
		if child is Window and child.visible: child.hide()
	var return_focus: Control = app.get_viewport().gui_get_focus_owner()
	var window = DismissibleWindow.new()
	window.title = title
	window.borderless = true
	window.transparent = true
	window.transparent_bg = true
	window.transient = true
	window.exclusive = true
	window.wrap_controls = false
	window.min_size = Vector2i(320,280)
	var shade = ColorRect.new()
	shade.color = Color(0,0,0,.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(shade)
	window.visibility_changed.connect(func(): if is_instance_valid(shade): shade.visible = window.visible)
	window.tree_exiting.connect(func():
		if is_instance_valid(shade): shade.queue_free()
		_restore_focus.call_deferred(return_focus))
	app.add_child(window)
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	window.add_child(panel)
	window.close_requested.connect(func(): app.ui_motion.close_window(window,panel,shade))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",12)
	scroll.add_child(box)
	var head = HBoxContainer.new()
	box.add_child(head)
	app._label(head,title,20)
	var close := _button(head,"×",window.close_requested.emit,"tertiary")
	close.custom_minimum_size = Vector2(44,44)
	close.accessibility_name = title+" 닫기"
	close.tooltip_text = close.accessibility_name
	window.popup_centered(Vector2i(mini(int(app.size.x)-24,560),mini(int(app.size.y)-30,600)))
	close.grab_focus()
	app.ui_motion.enter_window.call_deferred(panel,shade)
	return [window,box]

func _restore_focus(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return
	for child in app.get_children():
		if child is Window and child.visible and not child.is_queued_for_deletion() and control.get_window()!=child: return
	control.grab_focus()

func _confirm(text: String,callback: Callable) -> void:
	confirm_action("확인",text,"확인",callback)

func confirm_action(title: String,text: String,action: String,callback: Callable) -> void:
	var return_focus: Control = app.get_viewport().gui_get_focus_owner()
	var previous_window: Window
	for child in app.get_children():
		if child is Window and child.visible and not child.is_queued_for_deletion():
			previous_window = child
			return_focus = child.gui_get_focus_owner()
			child.hide()
	var dialog = preload("res://confirmation_dialog(게임 확인창).gd").new()
	app.add_child(dialog)
	var previous_ref: WeakRef = weakref(previous_window) if is_instance_valid(previous_window) else null
	var focus_ref: WeakRef = weakref(return_focus) if is_instance_valid(return_focus) else null
	dialog.confirmed.connect(func():
		var previous: Window = previous_ref.get_ref() if previous_ref!=null else null
		if is_instance_valid(previous): previous.queue_free()
		callback.call())
	dialog.canceled.connect(func():
		dialog.queue_free()
		var previous: Window = previous_ref.get_ref() if previous_ref!=null else null
		if is_instance_valid(previous) and not previous.is_queued_for_deletion(): previous.show())
	dialog.tree_exiting.connect(func():
		var control: Control = focus_ref.get_ref() if focus_ref!=null else null
		_restore_focus.call_deferred(control))
	dialog.build(app,title,text,action)

func _form(title: String,definitions: Array,submit: Callable) -> void:
	var pair = app._window(title)
	var box: VBoxContainer = pair[1]
	var fields: Dictionary = {}
	for definition in definitions:
		app._label(box,definition[1],15)
		fields[definition[0]] = app._field(box,definition[1],"",bool(definition[2]))
	var feedback = app._label(box,"",15)
	var button = Button.new()
	button.text = "확인"
	button.custom_minimum_size.y = 44
	box.add_child(button)
	_style_button(button,"primary")
	app.ui_motion.attach(button)
	button.pressed.connect(func():
		button.disabled = true
		var values: Dictionary = {}
		for key in fields: values[key] = fields[key].text
		var data: Dictionary = await submit.call(values)
		if is_instance_valid(button): button.disabled = false
		if data.get("ok"):
			if is_instance_valid(pair[0]): pair[0].queue_free()
		else:
			if is_instance_valid(feedback): feedback.text = str(data.get("msg","처리하지 못했습니다.")))

func _card(parent: Node, title: String) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	panel.add_child(box)
	if not title.is_empty():
		app._label(box,title,14)
	return box

# Shared tokens keep normal controls, role buttons and theme changes consistent.
func _palette() -> Dictionary:
	var light: bool = app.prefs.get_value("settings","light",false)
	return {
		"text":Color("#242b29") if light else Color("#f1f0e9"),
		"muted":Color("#606761") if light else Color("#a5b0a8"),
		"surface":Color("#f8f5f0") if light else Color("#222827"),
		"button":Color("#ebe7df") if light else Color("#2d3432"),
		"border":Color("#d3d1c8") if light else Color("#39413b"),
		"accent":Color("#e3bd78"),
		"danger":Color("#943f3c") if light else Color("#efaaa0"),
		"danger_bg":Color("#f7e7e2") if light else Color("#422b28"),
		"disabled":Color("#aaa295") if light else Color("#817c72")
	}

func _button_style(role: String,state: String,tint: Variant=null) -> StyleBoxFlat:
	var colors := _palette()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(9)
	style.set_border_width_all(1)
	style.bg_color = colors.button
	style.border_color = colors.border
	if role=="primary":
		style.bg_color = colors.accent
		style.border_color = colors.accent
	elif role=="tertiary":
		style.bg_color = Color(0,0,0,0)
		style.border_color = Color(0,0,0,0)
	elif role=="danger":
		style.bg_color = colors.danger_bg
		style.border_color = colors.danger_bg.lightened(.16)
	if tint is Color:
		style.bg_color = tint
		style.border_color = tint
	if state=="hover":
		style.bg_color = colors.button.lightened(.08) if role=="tertiary" else style.bg_color.lightened(.09)
		style.border_color = colors.border.lightened(.20) if role in ["secondary","tertiary"] else style.bg_color
	elif state=="pressed":
		style.bg_color = colors.button.darkened(.12) if role=="tertiary" else style.bg_color.darkened(.12)
	elif state=="disabled":
		style.bg_color = colors.surface
		style.border_color = colors.border.darkened(.15)
	elif state=="focus":
		# Focus is an overlay in Godot; transparent fill preserves the role beneath it.
		style.bg_color = Color(0,0,0,0)
		style.border_color = colors.accent.lightened(.18)
		style.set_border_width_all(2)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _style_button(button: Button,role: String="secondary") -> void:
	if role not in ["primary","secondary","tertiary","danger"]: role = "secondary"
	button.set_meta("ui_role",role)
	var colors := _palette()
	var tint: Variant = button.get_meta("ui_tint") if button.has_meta("ui_tint") else null
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,_button_style(role,state,tint))
	var foreground: Color = Color("#241e14") if role=="primary" else (colors.danger if role=="danger" else colors.text)
	if tint is Color: foreground = Color("#241e14") if button.get_meta("ui_tint_dark_text",false) else Color.WHITE
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:
		button.add_theme_color_override(key,foreground)
	button.add_theme_color_override("font_disabled_color",colors.disabled)

func _refresh_button_styles(node: Node) -> void:
	if node is Button and node.has_meta("ui_role"):
		_style_button(node,str(node.get_meta("ui_role")))
		if node.has_meta("mode_card"): _style_mode_card(node)
	for child in node.get_children(): _refresh_button_styles(child)

func _tint_button(button: Button,color: Color,dark_text: bool=false) -> void:
	button.set_meta("ui_tint",color)
	button.set_meta("ui_tint_dark_text",dark_text)
	_style_button(button,str(button.get_meta("ui_role","secondary")))

func _mode_card(parent: Node,title: String,description: String,icon: String,callback: Callable,primary: bool=false) -> void:
	var button = app._button(parent,"",callback)
	button.custom_minimum_size.y = 68
	button.set_meta("action_title",title)
	button.set_meta("primary",primary)
	button.set_meta("mode_card",true)
	app.mode_cards.append(button)
	button.tooltip_text = description
	var margin = MarginContainer.new()
	margin.name = "ModeCardContent"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,14)
	button.add_child(margin)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	margin.add_child(row)
	app._icon(row,icon,40)
	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	app._label(box,title,16)
	if not description.is_empty():
		var sub = app._label(box,description,12)
		sub.set_meta("ui_muted",true)
		sub.add_theme_color_override("font_color",_palette().muted)
	margin.minimum_size_changed.connect(func(): button.custom_minimum_size.y = maxf(76,margin.get_combined_minimum_size().y))
	app._ignore_mouse(margin)
	app._style_mode_card(button)

func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control: app._ignore_mouse(child)

func _icon(parent: Node,key: String,dimension: int=24) -> Control:
	var icon: Control
	if key=="king":
		var piece = TextureRect.new()
		piece.texture = load("res://pieces/Chess_klt45.svg")
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon = piece
	else:
		icon = preload("res://original_icon(원본 스타일 아이콘).gd").new()
		icon.key = key
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.custom_minimum_size = Vector2(dimension,dimension)
	parent.add_child(icon)
	return icon

func _nav(parent: Node,text: String,icon: String,callback: Callable) -> Button:
	var button = _button(parent,text,callback,"tertiary")
	button.set_meta("nav_label",text)
	button.tooltip_text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if icon=="king":
		button.icon = load("res://ui/icons/brand.svg")
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width",26)
	else:
		var art = app._icon(button,icon,26)
		button.set_meta("original_icon",art)
		button.text = "       "+text.replace("\n","\n       ")
	app.nav_buttons.append(button)
	return button

func _style_mode_card(button: Button) -> void:
	var colors := _palette()
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style := _button_style("secondary",state)
		if state=="normal": style.bg_color = colors.surface
		if state!="focus" and button.get_meta("primary",false): style.border_color = colors.accent
		button.add_theme_stylebox_override(state,style)
	_refresh_muted_labels(button)

func _refresh_muted_labels(node: Node) -> void:
	if node is Label and node.has_meta("ui_muted"):
		node.add_theme_color_override("font_color",_palette().muted)
	for child in node.get_children(): _refresh_muted_labels(child)

func _small_window(title: String,width: int=380,height: int=560) -> Array:
	var pair = app._window(title)
	pair[0].set_meta("preferred_size",Vector2i(width,height))
	pair[0].size = Vector2i(mini(int(app.size.x)-24,width),mini(int(app.size.y)-24,height))
	pair[0].position = (app.get_viewport_rect().size-Vector2(pair[0].size))/2
	return pair

func _clear_form(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()

func _form_action(parent: Node,title: String,subtitle: String,icon: String,primary: bool=false) -> Button:
	app._mode_card(parent,title,subtitle,icon,func(): pass,primary)
	var button: Button = parent.get_child(parent.get_child_count()-1)
	# Metadata carries the action name for accessibility/testing; children render text.
	button.accessibility_name = title
	return button

func _rich(parent: Node,text: String,font_size: int=13) -> RichTextLabel:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.scroll_active = false
	label.custom_minimum_size.x = 1
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("normal_font_size",font_size)
	label.add_theme_font_size_override("bold_font_size",font_size)
	label.add_theme_font_override("normal_font",app._original_font(400))
	label.add_theme_font_override("bold_font",app._original_font(700))
	label.text = text.replace("<b>","[b]").replace("</b>","[/b]")
	parent.add_child(label)
	return label

func _original_font(weight: int=400) -> Font:
	if app.original_fonts.has(weight): return app.original_fonts[weight]
	var file: FontFile = load("res://fonts/Roboto.ttf").duplicate()
	var fallback: Font
	if OS.has_feature("web"):
		var korean = FontVariation.new()
		korean.base_font = load("res://fonts/NotoSansKR.ttf")
		korean.variation_opentype = {2003265652:weight}
		fallback = korean
	else:
		var system = SystemFont.new()
		system.font_names = PackedStringArray(["Segoe UI","Malgun Gothic","Apple SD Gothic Neo","Noto Sans CJK KR"])
		system.font_weight = weight
		fallback = system
	file.fallbacks = [fallback]
	var font = FontVariation.new()
	font.base_font = file
	font.variation_opentype = {2003265652:weight}
	app.original_fonts[weight] = font
	return font
