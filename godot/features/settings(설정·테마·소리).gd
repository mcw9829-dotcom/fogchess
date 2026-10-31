extends RefCounted
## Feature implementation. Shared scene state and cross-feature entry points live on app.
var app
var version_footer: Button

func _init(context: Control) -> void:
	app = context

func _save() -> void:
	if app.testing: return
	app.prefs.set_value(app.api.base_url,"session",app.session)
	app.prefs.set_value(app.api.base_url,"room",app.room)
	app.prefs.set_value(app.api.base_url,"token",app.token)
	if is_instance_valid(app.guest_field): app.prefs.set_value("settings","nickname",app.guest_field.text)
	app.prefs.save("user://client.cfg")

func _settings() -> void:
	var box = app._subscreen("설정")
	app._nav_active("설정")
	for item in [["sound","효과음","버튼·토글과 전투 효과음",true],["lobby_music","로비 배경음악","홈·메뉴에서만 재생 · 대국과 리플레이에서는 정지",true],["colorblind","색약 모드","빨강·초록 대신 파랑·주황 계열로 구분",false],["effects","파티클 이펙트","폭발·안개·물결 연출",true],["practice_tips","연습 학습 안내","컴퓨터 대국·혼자 연습에서 상황별 규칙 설명",true]]:
		var content = app._card(box,"")
		var row = HBoxContainer.new()
		content.add_child(row)
		var labels = VBoxContainer.new()
		labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(labels)
		app._label(labels,item[1],14)
		if not str(item[2]).is_empty(): app._label(labels,item[2],11)
		var status = app._label(row,"",11)
		status.custom_minimum_size.x = 30
		status.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var toggle = preload("res://material_switch(정돈된 설정 스위치).gd").new()
		toggle.name = "Setting_"+str(item[0])
		toggle.tooltip_text = str(item[1])+" 켜기 / 끄기"
		toggle.button_pressed = bool(app.prefs.get_value("settings",item[0],item[3]))
		row.add_child(toggle)
		status.text = "켜짐" if toggle.button_pressed else "꺼짐"
		var samples: Array = _colorblind_preview(content) if item[0]=="colorblind" else []
		toggle.toggled.connect(func(value):
			status.text = "켜짐" if value else "꺼짐"
			app.prefs.set_value("settings",item[0],value)
			app._save()
			app.audio.enabled = bool(app.prefs.get_value("settings","sound",true))
			app.board.effects = bool(app.prefs.get_value("settings","effects",true))
			app.board.colorblind = bool(app.prefs.get_value("settings","colorblind",false))
			for sample in samples: sample.queue_redraw())
	var volume_card = app._card(box,"")
	var volume_row = HBoxContainer.new()
	volume_card.add_child(volume_row)
	app._label(volume_row,"볼륨",14)
	var volume = HSlider.new()
	volume.custom_minimum_size = Vector2(180,44)
	volume.min_value = 0
	volume.max_value = 1
	volume.step = .05
	volume.value = app.audio.level
	volume_row.add_child(volume)
	volume.drag_ended.connect(func(_changed): app.audio.cue("ui_click"))
	volume.value_changed.connect(func(value): app.audio.set_level(value); app.prefs.set_value("settings","volume",value); app._save())
	var theme_card = app._card(box,"")
	var theme_row = HBoxContainer.new()
	theme_card.add_child(theme_row)
	app._label(theme_row,"테마",14)
	var group = ButtonGroup.new()
	for option in [[false,"다크"],[true,"화이트"]]:
		var button = app._button(theme_row,option[1],func():
			app.prefs.set_value("settings","light",option[0])
			app._save()
			app._apply_theme())
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.x = 100
		button.set_meta("theme_choice",option[0])
		button.tooltip_text = str(option[1])+" 화면 테마"
	_refresh_theme_choices()
	var theme_note = app._label(theme_card,"화면과 메뉴 색상에 적용됩니다.",11)
	theme_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.move_child(volume_card.get_parent(),2)
	box.move_child(theme_card.get_parent(),3)
	var preview_card = app._card(box,"")
	var preview_row = HBoxContainer.new()
	preview_card.add_child(preview_row)
	app._label(preview_row,"이펙트 미리보기",14)
	app._button(preview_row,"열기",app._effect_preview)
	var advanced = app._button(box,"서버 연결 · 개발 설정",app._connection_settings)
	advanced.visible = not OS.has_feature("web")
	advanced.flat = true
	advanced.add_theme_font_size_override("font_size",11)
	app._button(box,"← 뒤로",app._navigation_home)
	_version_footer(box)
	for child in box.get_children():
		if child is PanelContainer: child.set_meta("settings_card",true)
	_refresh_setting_cards()

func _version_footer(box: Control) -> void:
	# This only reveals the existing login dialog. Authorization remains server-side.
	var version := Button.new()
	version_footer = version
	version.name = "SettingsVersion"
	_refresh_version_footer()
	version.flat = true
	version.custom_minimum_size = Vector2(120,44)
	version.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	version.add_theme_font_size_override("font_size",12)
	version.modulate.a = .75
	for state in ["normal","hover","pressed","disabled"]:
		version.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	# Keyboard focus stays visible; ordinary pointer hover remains plain version text.
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#b18a4d")
	focus.set_border_width_all(1)
	focus.set_corner_radius_all(4)
	version.add_theme_stylebox_override("focus",focus)
	box.add_child(version)
	var taps := {"count":0,"deadline":0}
	version.visibility_changed.connect(func():
		if not version.is_visible_in_tree():
			taps.count = 0
			taps.deadline = 0)
	# BaseButton.pressed handles mouse, keyboard and emulated touch once per release.
	version.pressed.connect(func():
		if not version.is_visible_in_tree(): return
		var now := Time.get_ticks_msec()
		if taps.count==0 or now>int(taps.deadline):
			taps.count = 0
			taps.deadline = now+5000
		taps.count += 1
		if taps.count==5:
			taps.count = 0
			taps.deadline = 0
			version.release_focus()
			app._admin())

func _refresh_version_footer() -> void:
	if not is_instance_valid(version_footer): return
	version_footer.text = app.rail_version.text.get_slice(" · ",0)
	if not version_footer.text.begins_with("v"): version_footer.text = "버전 정보"
	version_footer.accessibility_name = "게임 버전 " + version_footer.text

func _refresh_setting_cards() -> void:
	for child in app.subpage.get_children():
		if not child.get_meta("settings_card",false): continue
		var style: StyleBoxFlat = app.theme.get_stylebox("panel","PanelContainer").duplicate()
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		child.add_theme_stylebox_override("panel",style)

func _refresh_theme_choices() -> void:
	var light: bool = app.prefs.get_value("settings","light",false)
	for button in app.find_children("*","Button",true,false):
		if not button.has_meta("theme_choice"): continue
		var choice: bool = button.get_meta("theme_choice")
		var active := choice==light
		button.set_pressed_no_signal(active)
		button.text = ("✓ " if active else "")+("화이트" if choice else "다크")
		app.ui_components._style_button(button,"primary" if active else "secondary")

func _colorblind_preview(parent: Node) -> Array:
	var previews: Array = []
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	for entry in [["move","이동 · 점"],["attack","공격 · 원"],["scan","스캔 · 조준"]]:
		var column = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var sample = Control.new()
		sample.custom_minimum_size = Vector2(50,30)
		sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(sample)
		sample.draw.connect(_draw_signal_sample.bind(sample,entry[0]))
		var label = app._label(column,entry[1],11)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		previews.append(sample)
	return previews

func _draw_signal_sample(sample: Control, kind: String) -> void:
	var at := sample.size/2
	var color: Color = app.board.signal_color(kind)
	match kind:
		"move": sample.draw_circle(at,8,color)
		"attack": sample.draw_arc(at,10,0,TAU,32,color,3,true)
		"scan":
			sample.draw_circle(at,9,Color(color,.15))
			for i in range(4):
				var angle := PI*.25+i*PI*.5
				sample.draw_arc(at,10,angle-.32,angle+.32,10,color,2,true)
			sample.draw_line(at-Vector2(4,0),at+Vector2(4,0),color,1.5,true)
			sample.draw_line(at-Vector2(0,4),at+Vector2(0,4),color,1.5,true)

func _apply_theme() -> void:
	var light = bool(app.prefs.get_value("settings","light",false))
	var design = Theme.new()
	design.default_font = app._original_font(400)
	design.default_font_size = 14
	var colors: Dictionary = app.ui_components._palette()
	_apply_range_control_theme(design,colors,light)
	design.set_color("default_color","RichTextLabel",colors.text)
	design.set_color("selection_color","RichTextLabel",Color(colors.accent,.28))
	for type in ["Label","RichTextLabel","CheckBox","Button","LineEdit","TextEdit","OptionButton"]:
		design.set_color("font_color",type,colors.text)
		design.set_color("font_disabled_color",type,colors.disabled)
		if type in ["Label","RichTextLabel","CheckBox"]: continue
		for state in ["normal","hover","pressed","focus","disabled"]:
			var style: StyleBoxFlat = app.ui_components._button_style("secondary",state)
			if type in ["LineEdit","TextEdit","OptionButton"] and state not in ["focus","disabled"]:
				style.bg_color = Color("#fffdf8") if light else Color("#1c1c19")
			design.set_stylebox(state,type,style)
		design.set_color("font_hover_color",type,colors.text)
		design.set_color("font_pressed_color",type,colors.text)
		design.set_color("font_focus_color",type,colors.text)
		design.set_color("font_placeholder_color",type,colors.muted)
		design.set_color("caret_color",type,colors.accent)
		design.set_color("selection_color",type,Color(colors.accent,.28))
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = colors.surface
	panel_style.set_border_width_all(1)
	panel_style.border_color = colors.border.darkened(.15)
	panel_style.set_corner_radius_all(10)
	for edge in ["left","right","top","bottom"]: panel_style.set("content_margin_"+edge,14.0)
	design.set_stylebox("panel","PanelContainer",panel_style)
	var grid_style: StyleBoxFlat = panel_style.duplicate()
	for edge in ["left","right","top","bottom"]: grid_style.set("content_margin_"+edge,0.0)
	design.set_type_variation("MatchGridPanel","PanelContainer")
	design.set_stylebox("panel","MatchGridPanel",grid_style)
	design.set_type_variation("MatchWaiting","Label")
	design.set_stylebox("normal","MatchWaiting",panel_style)
	for orientation in ["Horizontal","Vertical"]:
		var divider = StyleBoxLine.new()
		divider.color = colors.border.darkened(.15)
		divider.thickness = 1
		divider.vertical = orientation=="Vertical"
		var grid_type = "MatchGrid"+orientation
		design.set_type_variation(grid_type,"VSeparator" if divider.vertical else "HSeparator")
		design.set_stylebox("separator",grid_type,divider)
	for state in ["normal","hover","pressed","disabled"]: design.set_stylebox(state,"CheckButton",StyleBoxEmpty.new())
	design.set_icon("checked","CheckButton",load("res://ui/icons/switch_on.svg"))
	design.set_icon("unchecked","CheckButton",load("res://ui/icons/switch_off.svg"))
	design.set_constant("light_mode","FogMenuIcon",1 if light else 0)
	app.theme = design
	app.coach_label.add_theme_color_override("font_color",Color("#76521e") if light else Color("#eed29a"))
	app.ui_components._refresh_button_styles(app)
	if is_instance_valid(app.ui_shell.lobby_home): app.ui_shell.lobby_home.apply_theme()
	_refresh_theme_choices()
	_refresh_setting_cards()
	app._tint_button(app.ready_button,Color("#c69a5e"),true)
	RenderingServer.set_default_clear_color(Color("#eae6df") if light else Color("#171b1b"))
	var rail_style = panel_style.duplicate()
	rail_style.set_corner_radius_all(0)
	rail_style.set_border_width_all(0)
	rail_style.content_margin_left = 10
	rail_style.content_margin_right = 10
	app.rail_panel.add_theme_stylebox_override("panel",rail_style)
	for card in app.mode_cards:
		if is_instance_valid(card): app._style_mode_card(card)
	var overlay = StyleBoxFlat.new()
	overlay.bg_color = Color(.055,.07,.086,.88)
	overlay.set_corner_radius_all(4)
	app.result_panel.add_theme_stylebox_override("panel",overlay)
	# This surface stays dark in both themes, including dynamically added labels.
	var result_theme := Theme.new()
	result_theme.set_color("font_color","Label",Color("#f3f0e8"))
	result_theme.set_color("default_color","RichTextLabel",Color("#f3f0e8"))
	app.result_panel.theme = result_theme
	app.ui_shell._refresh_navigation()
	app.match_ui.apply_theme()
	app.replay.apply_theme()
	app.feed_signature = ""
	if not app.view.is_empty(): app._render()

func _control_svg(markup: String, width: int, height: int) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [width,height,width,height,markup])
	return ImageTexture.create_from_image(image)

func _range_track(color: Color, vertical: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	style.content_margin_left = 2 if vertical else 0
	style.content_margin_right = 2 if vertical else 0
	style.content_margin_top = 0 if vertical else 2
	style.content_margin_bottom = 0 if vertical else 2
	return style

func _scroll_thumb(color: Color, vertical: bool, highlighted: bool) -> StyleBoxTexture:
	# Narrow visible ink inside the unchanged 16px interaction width.
	var thickness := 8 if highlighted else 6
	var inset := (16-thickness)/2
	var rect := '<rect x="%d" y="2" width="%d" height="28" rx="%d" fill="#%s"/>' % [inset,thickness,thickness/2,color.to_html(false)] if vertical else '<rect x="2" y="%d" width="28" height="%d" rx="%d" fill="#%s"/>' % [inset,thickness,thickness/2,color.to_html(false)]
	var style := StyleBoxTexture.new()
	style.texture = _control_svg(rect,16 if vertical else 32,32 if vertical else 16)
	style.texture_margin_left = 8 if vertical else 6
	style.texture_margin_right = 8 if vertical else 6
	style.texture_margin_top = 6 if vertical else 8
	style.texture_margin_bottom = 6 if vertical else 8
	style.content_margin_left = 8 if vertical else 6
	style.content_margin_right = 8 if vertical else 6
	style.content_margin_top = 6 if vertical else 8
	style.content_margin_bottom = 6 if vertical else 8
	return style

func _apply_range_control_theme(design: Theme, colors: Dictionary, light: bool) -> void:
	var track := Color("#c9c8bf") if light else Color("#424e49")
	var thumb := Color("#7b847c") if light else Color("#87978e")
	var accent := Color("#9b722e") if light else Color("#e3bd78")
	for type in ["HSlider","VSlider"]:
		var vertical: bool = type=="VSlider"
		design.set_stylebox("slider",type,_range_track(track,vertical))
		design.set_stylebox("grabber_area",type,_range_track(accent,vertical))
		design.set_stylebox("grabber_area_highlight",type,_range_track(accent.lightened(.12),vertical))
		for state in ["grabber","grabber_highlight","grabber_disabled"]:
			var fill: Color = colors.surface if state=="grabber" else (accent if state=="grabber_highlight" else track)
			var edge: Color = thumb if state=="grabber_disabled" else accent
			var halo := '<circle cx="13" cy="13" r="11" fill="#%s" fill-opacity="0.16"/>' % accent.to_html(false) if state=="grabber_highlight" else ''
			# 14px handle, 26px texture footprint; the slider control keeps 44px height.
			design.set_icon(state,type,_control_svg(halo+'<circle cx="13" cy="13" r="7" fill="#%s" stroke="#%s" stroke-width="1.6"/>' % [fill.to_html(false),edge.to_html(false)],26,26))
	for type in ["HScrollBar","VScrollBar"]:
		var vertical: bool = type=="VScrollBar"
		var background := StyleBoxFlat.new()
		background.bg_color = Color.TRANSPARENT
		background.content_margin_left = 8 if vertical else 0
		background.content_margin_right = 8 if vertical else 0
		background.content_margin_top = 0 if vertical else 8
		background.content_margin_bottom = 0 if vertical else 8
		design.set_stylebox("scroll",type,background)
		var focus: StyleBoxFlat = background.duplicate()
		focus.set_border_width_all(1)
		focus.border_color = Color(accent,.55)
		focus.set_corner_radius_all(4)
		design.set_stylebox("scroll_focus",type,focus)
		design.set_stylebox("grabber",type,_scroll_thumb(thumb,vertical,false))
		design.set_stylebox("grabber_highlight",type,_scroll_thumb(accent,vertical,true))
		design.set_stylebox("grabber_pressed",type,_scroll_thumb(accent,vertical,true))

func _connection_settings() -> void:
	var pair = app._window("서버 연결")
	app._label(pair[1],"현재 개발 서버: "+app.api.base_url,13)
	var endpoint = app._field(pair[1],"http://127.0.0.1:7556",app.api.base_url)
	endpoint.editable = app.room.is_empty() and not app.matching and not OS.has_feature("web")
	var apply = app._button(pair[1],"적용",func():
		var value = endpoint.text.strip_edges().trim_suffix("/")
		if not endpoint.editable or app.busy: return
		if not (value.begins_with("http://") or value.begins_with("https://")): return
		app._save()
		app.api.base_url = value
		app.prefs.set_value("settings","server",value)
		app.session = str(app.prefs.get_value(value,"session",""))
		app.me = {}
		app._save()
		app._update_account()
		app._refresh_profile()
		app._load_home_ranks()
		pair[0].queue_free())
	apply.disabled = not endpoint.editable

func _toggle_sound() -> void:
	app.audio.enabled = not app.audio.enabled
	app.prefs.set_value("settings","sound",app.audio.enabled)
	app._save()
	app.sound_button.text = "소리 켜짐" if app.audio.enabled else "소리 꺼짐"
	if not app.view.is_empty(): app.match_ui.render()

