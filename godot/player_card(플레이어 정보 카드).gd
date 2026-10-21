extends PanelContainer
var name_label: Label
var detail: Label
var timer_label: Label
var captures: HFlowContainer
var avatar: TextureRect
var last_captures := ""

func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	add_child(row)
	avatar = TextureRect.new()
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.custom_minimum_size = Vector2(28,30)
	row.add_child(avatar)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size",14)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(name_label)
	detail = Label.new()
	detail.add_theme_font_size_override("font_size",11)
	info.add_child(detail)
	captures = HFlowContainer.new()
	info.add_child(captures)
	timer_label = Label.new()
	timer_label.add_theme_font_size_override("font_size",22)
	timer_label.custom_minimum_size.x = 44
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(timer_label)

func update_player(data: Dictionary, is_me: bool, light: bool) -> void:
	var color: String = data.get("yourColor","W")
	if not is_me: color = "B" if color=="W" else "W"
	var own: String = "my" if is_me else "opp"
	var rating: Variant = null if data.get("solo") else data.get(own+"Rating")
	var piece := "p" if rating==null or int(rating)<1000 else ("n" if int(rating)<1200 else ("r" if int(rating)<1500 else ("b" if int(rating)<1700 else ("q" if int(rating)<1900 else "k"))))
	avatar.texture = load("res://pieces/Chess_%slt45.svg" % piece)
	name_label.text = ("백" if color=="W" else "흑") if data.get("solo") else str(data.get(own+"Name","나" if is_me else "상대"))
	if rating!=null: name_label.text += "  %d" % int(rating)
	detail.text = "%s%s   병력 %d" % ["백" if color=="W" else "흑"," · 나" if is_me else "",int(data.get("aliveMe" if is_me else "aliveOpp",0))]
	var active: bool = data.get("phase")=="play" and data.get("turn")==color
	var seconds: Variant = data.get("turnSecondsLeft") if active else data.get("turnSeconds",30)
	timer_label.text = "%ds" % int(seconds) if data.get("phase")=="play" and seconds!=null else "—"
	timer_label.add_theme_color_override("font_color",Color("#d6302c") if active and seconds!=null and int(seconds)<=6 else (Color("#d4a34a") if active else Color("#9a938a")))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#eee6da") if light else Color("#1c1a18")
	style.border_color = Color("#c69a5e") if active else (Color("#d3c7b7") if light else Color("#3a352f"))
	style.set_border_width_all(2 if active else 1)
	style.set_corner_radius_all(12)
	for edge in ["left","right","top","bottom"]: style.set("content_margin_"+edge,10.0)
	add_theme_stylebox_override("panel",style)
	var taken: Array = data.get("deadOpp" if is_me else "deadMe",[])
	var key := str(taken)+color
	if key==last_captures: return
	last_captures = key
	for child in captures.get_children():
		captures.remove_child(child)
		child.queue_free()
	if taken.is_empty():
		var empty := Label.new()
		empty.text = "잡은 기물 없음"
		empty.add_theme_font_size_override("font_size",11)
		captures.add_child(empty)
	else:
		var groups: Dictionary = {}
		for kind in taken: groups[kind] = int(groups.get(kind,0))+1
		for kind in groups:
			var row := HBoxContainer.new()
			captures.add_child(row)
			var icon := TextureRect.new()
			icon.texture = load("res://pieces/Chess_%s%st45.svg" % [str(kind).to_lower(),"d" if color=="W" else "l"])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(22,22)
			row.add_child(icon)
			if groups[kind]>1:
				var count := Label.new()
				count.text = "×%d" % int(groups[kind])
				count.add_theme_font_size_override("font_size",11)
				row.add_child(count)
