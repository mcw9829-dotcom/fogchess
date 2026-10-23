extends RefCounted
## Visual preparation guide. The server still owns placement, readiness and start time.
var app
var guide: HBoxContainer
var art: Control
var title: Label
var subtitle: Label
var divider: HSeparator
var textures: Dictionary = {}
var placement_buttons: Array[Button] = []

class PlacementArt extends Control:
	var prepared := false
	var accent := Color("e3bd78")
	func _draw() -> void:
		var surface := StyleBoxFlat.new()
		surface.bg_color = Color(accent,.10)
		surface.set_corner_radius_all(12)
		draw_style_box(surface,Rect2(Vector2.ZERO,size))
		if prepared:
			draw_arc(size*.5,15,0,TAU,48,Color(accent,.4),1.5,true)
			draw_polyline(PackedVector2Array([Vector2(15,25),Vector2(22,31),Vector2(34,18)]),accent,2.5,true)
		else:
			# Three placement rows; a schematic, never a second playable board.
			for row in range(3):
				for column in range(4):
					var cell := StyleBoxFlat.new()
					cell.bg_color = Color(accent,.85 if row==1 and column==2 else .30)
					cell.set_corner_radius_all(2)
					draw_style_box(cell,Rect2(Vector2(8+column*9,12+row*9),Vector2(7,7)))

func _init(context: Control) -> void:
	app = context

func icon(key: String) -> Texture2D:
	if textures.has(key): return textures[key]
	var paths: String = {
		"layout":'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M3 15h18M9 4v16M15 4v16"/>',
		"shuffle":'<path d="M3 6h3c5 0 7 12 12 12h3M17 14l4 4-4 4M3 18h3c2 0 4-3 6-6s4-6 6-6h3M17 2l4 4-4 4"/>',
		"check":'<path d="m5 12 4 4L19 6"/>',
		"undo":'<path d="M9 4 4 9l5 5M4 9h9a6 6 0 0 1 0 12"/>',
		"flag":'<path d="M5 22V3c5-4 9 4 14 0v11c-5 4-9-4-14 0"/>',
		"exit":'<path d="M10 3H4v18h6M9 12h12m-5-5 5 5-5 5"/>'
	}.get(key,"")
	var image := Image.new()
	image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">'+paths+'</svg>')
	var texture := ImageTexture.create_from_image(image)
	textures[key] = texture
	return texture

func decorate(button: Button, key: String) -> void:
	button.icon = icon(key)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",19)
	button.add_theme_constant_override("h_separation",7)

func build(parent: VBoxContainer) -> void:
	guide = HBoxContainer.new()
	guide.name = "SetupVisualGuide"
	guide.add_theme_constant_override("separation",12)
	parent.add_child(guide)
	parent.move_child(guide,0)
	art = PlacementArt.new()
	art.custom_minimum_size = Vector2(50,50)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.add_child(art)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation",3)
	guide.add_child(words)
	title = app._label(words,"내 진영 3줄",16)
	subtitle = app._label(words,"기물 선택 → 놓을 칸 선택",12)
	app.setup_controls.add_theme_constant_override("separation",8)
	for i in range(app.setup_controls.get_child_count()):
		var button: Button = app.setup_controls.get_child(i)
		placement_buttons.append(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		decorate(button,"layout" if i==0 else "shuffle")
		button.tooltip_text = "기본 배치로 되돌리기" if i==0 else "내 진영 안에서 무작위로 배치하기"
	decorate(app.ready_button,"check")
	decorate(app.resign_button,"flag")
	decorate(app.utility_actions.get_node("LeaveMatch"),"exit")
	for button in [app.resign_button,app.utility_actions.get_node("LeaveMatch")]:
		button.custom_minimum_size.x = button.get_combined_minimum_size().x+26
	app.sound_button.custom_minimum_size = Vector2(44,44)
	app.sound_button.expand_icon = true
	app.sound_button.add_theme_constant_override("icon_max_width",20)
	app.sound_button.set_meta("match_tool",true)
	app.sound_button.text = ""
	divider = HSeparator.new()
	parent.add_child(divider)
	parent.move_child(divider,app.action_details.get_index()+1)
	parent.move_child(app.utility_actions,divider.get_index()+1)
	app.utility_actions.add_theme_constant_override("h_separation",6)
	render()

func render() -> void:
	if not is_instance_valid(guide): return
	var setup: bool = app.view.get("phase")=="setup" and app.seat!="spectator" and not app.replay.active
	var ready: bool = bool(app.view.get("ready",false))
	var palette: Dictionary = app.ui_components._palette()
	guide.visible = setup
	divider.visible = setup
	if setup:
		title.text = "준비 완료" if ready else "내 진영 3줄"
		subtitle.text = ("상대 준비를 기다려요" if app.view.get("bothJoined",false) else "상대 접속을 기다려요") if ready else ("놓을 칸을 선택하세요" if not app.selection.is_empty() else "기물 선택 → 놓을 칸 선택")
		guide.tooltip_text = "내 진영 3줄 안에서 배치할 수 있습니다. 기물과 놓을 칸을 차례로 선택하세요."
		art.prepared = ready
		art.accent = Color("8b651e") if app.prefs.get_value("settings","light",false) else palette.accent
		art.queue_redraw()
		title.add_theme_color_override("font_color",palette.text)
		subtitle.add_theme_color_override("font_color",palette.muted)
		decorate(app.ready_button,"undo" if ready else "check")
		app.ready_button.accessibility_name = "준비 취소" if ready else "준비 완료"
		app.ready_button.tooltip_text = "준비를 취소하고 배치를 바꿉니다" if ready else "현재 배치로 준비 완료"
		app.coach_label.visible = not app.game_session.request_status.is_empty()
		app.action_hint.text = "모두 준비하거나 시간이 끝나면 시작"
		app.action_hint.tooltip_text = "양쪽 준비 완료 또는 배치 시간 종료 시 대국이 시작됩니다."
	else:
		app.coach_label.visible = not app.coach_label.text.is_empty()
	app.sound_button.text = ""
	app.sound_button.icon = load("res://ui/icons/match-%s.svg" % ("volume" if app.audio.enabled else "muted"))
	app.sound_button.tooltip_text = "소리 켜짐 · 클릭하여 끄기" if app.audio.enabled else "소리 꺼짐 · 클릭하여 켜기"
	app.sound_button.accessibility_name = "효과음 끄기" if app.audio.enabled else "효과음 켜기"
	for button in placement_buttons+[app.ready_button,app.resign_button,app.utility_actions.get_node("LeaveMatch")]:
		var color: Color = Color("241e14") if button==app.ready_button else (palette.danger if button==app.resign_button else palette.text)
		for state in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_focus_color"]: button.add_theme_color_override(state,color)
