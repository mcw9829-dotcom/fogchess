extends Node
## Calm depth presentation. Commands and selected state update immediately.
const Motion = preload("res://calm_motion(차분한 깊이 모션 기준).gd")
const ButtonMotion = preload("res://material_button(정돈된 버튼 모션).gd")
var app
var selected: Button
class NavigationIndicator extends Node2D:
	var size := Vector2.ZERO
	var style: StyleBoxFlat
	func _draw() -> void:
		if style != null: draw_style_box(style,Rect2(Vector2.ZERO,size))

var indicator: NavigationIndicator
var nav_position := Vector2.ZERO
var nav_velocity := Vector2.ZERO
var nav_size := Vector2.ZERO
var nav_size_velocity := Vector2.ZERO
var nav_vertical := true
var nav_from := Vector2.ZERO
var nav_to := Vector2.ZERO
var nav_size_from := Vector2.ZERO
var nav_size_to := Vector2.ZERO
var nav_age := 1.0
var panels: Array = []
var last_room := ""
var last_turn := ""
var last_ready := false
var result_key := ""
var view_seen := false

func _init(context: Control) -> void:
	app = context

func attach(button: Button) -> void:
	if button.has_node("MaterialMotion"): return
	var effect := ButtonMotion.new()
	effect.name = "MaterialMotion"
	button.add_child(effect)

func confirm(button: Button) -> void:
	if is_instance_valid(button) and button.has_node("MaterialMotion"): button.get_node("MaterialMotion").confirm()

func select_navigation(button: Button) -> void:
	if not is_instance_valid(button): return
	var first := not is_instance_valid(indicator)
	if first:
		indicator = NavigationIndicator.new()
		indicator.name = "MaterialNavIndicator"
		app.rail.add_child(indicator)
		app.rail.move_child(indicator,0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color("c69a5e")
		style.set_corner_radius_all(12)
		indicator.style = style
	selected = button
	if first or nav_vertical!=app.rail.vertical:
		nav_position = button.global_position
		nav_size = button.size
		nav_velocity = Vector2.ZERO
		nav_size_velocity = Vector2.ZERO
		nav_vertical = app.rail.vertical
		nav_to = nav_position
		nav_size_to = nav_size
	_update_indicator()

func _update_indicator() -> void:
	if not is_instance_valid(indicator) or not is_instance_valid(selected): return
	indicator.visible = selected.is_visible_in_tree()
	indicator.global_position = nav_position
	indicator.size = nav_size.max(Vector2.ONE)
	indicator.queue_redraw()

func _motion_host(panel: Control) -> Node:
	# Move the embedded window, not its clipped drawing surface.
	return panel.get_parent() if panel.get_parent() is Window else panel

func _place(host: Node, position: Vector2) -> void:
	if host is Window: host.position = Vector2i(position.round())
	else: host.position = position

func _remove_motion(panel: Control, restore: bool=true) -> Vector2:
	var base := Vector2(_motion_host(panel).position)
	for item in panels.duplicate():
		if item.node!=panel: continue
		base = item.base
		panels.erase(item)
		if restore:
			_place(_motion_host(panel),base)
			panel.scale = Vector2.ONE
			panel.modulate = Color.WHITE
	return base

func enter_panel(panel: Control, distance: float=Motion.DISTANCE, duration: float=Motion.ENTER, scale_from: float=Motion.SCALE) -> void:
	if not is_instance_valid(panel) or not panel.is_visible_in_tree(): return
	var base := _remove_motion(panel)
	var offset := Vector2(0,distance)
	panels.append({"node":panel,"host":_motion_host(panel),"age":0.0,"base":base,"last_offset":offset,"from_offset":offset,"to_offset":Vector2.ZERO,"from_scale":scale_from,"to_scale":1.0,"from_alpha":.2,"to_alpha":1.0,"duration":duration,"done":Callable()})
	panel.pivot_offset = panel.size*Vector2(.5,.65)
	_place(_motion_host(panel),base+offset)
	panel.scale = Vector2.ONE*scale_from
	panel.modulate.a = .2

func enter_screen(panel: Control) -> void:
	enter_panel(panel,Motion.DISTANCE,Motion.PAGE,1.0)

func _shade_to(shade: Control, alpha: float, duration: float) -> void:
	if not is_instance_valid(shade): return
	var previous: Variant = shade.get_meta("depth_tween") if shade.has_meta("depth_tween") else null
	if previous is Tween: previous.kill()
	var tween := shade.create_tween()
	shade.set_meta("depth_tween",tween)
	tween.tween_property(shade,"modulate:a",alpha,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func enter_window(panel: Control, shade: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	if panel.get_window().get_meta("motion_closing",false): return
	enter_panel(panel)
	if is_instance_valid(shade):
		shade.modulate.a = 0
		_shade_to(shade,1.0,.18)

func exit_window(panel: Control, shade: Control, done: Callable) -> void:
	if not is_instance_valid(panel):
		if done.is_valid(): done.call()
		return
	var current := Vector2(_motion_host(panel).position)
	var base := _remove_motion(panel,false)
	panels.append({"node":panel,"host":_motion_host(panel),"age":0.0,"base":base,"last_offset":current-base,"from_offset":current-base,"to_offset":Vector2(0,Motion.DISTANCE*.5),"from_scale":panel.scale.x,"to_scale":Motion.SCALE,"from_alpha":panel.modulate.a,"to_alpha":0.0,"duration":Motion.EXIT,"done":done})
	_shade_to(shade,0.0,Motion.EXIT)

func close_window(window: Window, panel: Control, shade: Control) -> void:
	if not is_instance_valid(window) or window.get_meta("motion_closing",false): return
	window.set_meta("motion_closing",true)
	window.set_disable_input(true)
	exit_window(panel,shade,window.queue_free)

func pulse(control: Control) -> void:
	if not is_instance_valid(control): return
	var old: Variant = control.get_meta("material_pulse") if control.has_meta("material_pulse") else null
	if old is Tween: old.kill()
	control.modulate = Color(1.08,1.06,1.02)
	var tween := control.create_tween()
	control.set_meta("material_pulse",tween)
	tween.tween_property(control,"modulate",Color.WHITE,.18)

func observe_view() -> void:
	var room: String = app.room
	var turn: String = str([app.view.get("phase"),app.view.get("turn"),app.view.get("turnCount")])
	var ready: bool = app.view.get("ready",false)
	if view_seen and last_room==room:
		if turn!=last_turn and app.view.get("phase")=="play": pulse(app.ui_shell.match_header)
		if ready and not last_ready: confirm(app.ready_button)
	last_room = room
	last_turn = turn
	last_ready = ready
	view_seen = not room.is_empty()
	if app.view.get("phase")=="over":
		var key: String = str([room,app.view.get("replayId"),app.view.get("winner"),app.view.get("turnCount")])
		if key!=result_key:
			result_key = key
			enter_panel.call_deferred(app.result_panel.get_child(0),8.0)
	else: result_key = ""

func _process(delta: float) -> void:
	if is_instance_valid(selected) and is_instance_valid(indicator):
		if nav_to!=selected.global_position or nav_size_to!=selected.size:
			nav_from = nav_position
			nav_size_from = nav_size
			nav_to = selected.global_position
			nav_size_to = selected.size
			nav_age = 0.0
		nav_age += delta
		var progress := Motion.ease(nav_age/Motion.PAGE)
		nav_position = nav_from.lerp(nav_to,progress)
		nav_size = nav_size_from.lerp(nav_size_to,progress)
		_update_indicator()
	for item in panels.duplicate():
		if not is_instance_valid(item.node): panels.erase(item); continue
		var panel: Control = item.node
		# A parent container can relayout during resizing; follow its new origin.
		if Vector2(item.host.position).distance_to(item.base+item.last_offset)>1.0: item.base = Vector2(item.host.position)
		item.age += delta
		var progress := Motion.ease(item.age/item.duration)
		var offset: Vector2 = item.from_offset.lerp(item.to_offset,progress)
		panel.pivot_offset = panel.size*Vector2(.5,.65)
		_place(item.host,item.base+offset)
		item.last_offset = offset
		panel.scale = Vector2.ONE*lerpf(item.from_scale,item.to_scale,progress)
		panel.modulate.a = lerpf(item.from_alpha,item.to_alpha,progress)
		if item.age>=item.duration or not panel.is_visible_in_tree():
			panels.erase(item)
			_place(item.host,item.base)
			panel.scale = Vector2.ONE
			panel.modulate = Color.WHITE
			if item.done.is_valid(): item.done.call()
