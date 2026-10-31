extends RefCounted
## Shared notation presentation for live history and replay navigation.
static func display_notation(value: String) -> String:
	# Translate terminal action tokens only at display time. Keep chess notation
	# and stored replay payloads untouched.
	for event in ["resign","timeout","disconnect"]:
		if value==event or value.ends_with(" "+event):
			return value.trim_suffix(event)+{"resign":"기권","timeout":"시간 초과","disconnect":"접속 종료"}[event]
	return value

static func build(app, parent: Node, callback: Callable) -> Button:
	var button: Button = app._button(parent,"",callback,"tertiary")
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(44,56)
	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 4
	content.offset_right = -4
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation",2)
	button.add_child(content)
	var caption: Label = app._label(content,"",12)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation",2)
	content.add_child(row)
	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(18,20)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(art)
	var notation: Label = app._label(row,"",14)
	notation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notation.custom_minimum_size.x = 40
	notation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notation.autowrap_mode = TextServer.AUTOWRAP_OFF
	notation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ignore_pointer(content)
	button.set_meta("caption",caption)
	button.set_meta("notation",notation)
	button.set_meta("piece_icon",art)
	return button

static func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

static func style(app, button: Button, selected: bool) -> void:
	var palette: Dictionary = app.ui_components._palette()
	var light: bool = app.prefs.get_value("settings","light",false)
	var base: StyleBoxFlat = app.ui_components._button_style("secondary" if selected else "tertiary","normal")
	button.add_theme_stylebox_override("normal",base)
	button.get_meta("caption").add_theme_color_override("font_color",Color("#525d63") if light else Color("#bbc4c9"))
	button.get_meta("notation").add_theme_color_override("font_color",(Color("#275f87") if light else Color("#a3ccef")) if selected else palette.text)

static func show_piece(button: Button, kind: String, side: String) -> void:
	var art: TextureRect = button.get_meta("piece_icon")
	art.visible = kind in ["K","Q","R","B","N","P"] and side in ["W","B"]
	if art.visible: art.texture = load("res://pieces/Chess_%s%st45.svg" % [kind.to_lower(),"l" if side=="W" else "d"])
