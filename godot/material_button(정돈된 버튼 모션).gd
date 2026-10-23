extends Control
## Material Standard decoration. Native Button alone owns activation and its hit rectangle.
var button: Button
var amount := 0.0
var velocity := 0.0
var target := 0.0
var ripples: Array = []
var sources: Dictionary = {}
var confirmation := 0.0
var last_pointer := -1000
var pointer_origin := Vector2.ZERO
var pointer_active := false

func _ready() -> void:
	button = get_parent() as Button
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.button_down.connect(_down)
	button.button_up.connect(_up)
	button.gui_input.connect(_input_event)
	button.mouse_exited.connect(cancel)
	button.focus_exited.connect(cancel)
	button.visibility_changed.connect(func(): if not button.is_visible_in_tree(): reset())
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer: ancestor.scroll_started.connect(cancel)
		ancestor = ancestor.get_parent()
	set_process(false)

func _down() -> void:
	if button.disabled: return
	target = 1.0
	set_process(true)
	if Time.get_ticks_msec()-last_pointer>100: add_ripple(button.size*.5)

func _up() -> void:
	target = 0.0
	pointer_active = false
	for ripple in ripples: ripple.released = true
	set_process(true)

func _input_event(event: InputEvent) -> void:
	if button.disabled: return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			last_pointer = Time.get_ticks_msec()
			pointer_origin = event.position
			pointer_active = true
			# button_down may precede gui_input; replace its center ripple in that frame.
			if not ripples.is_empty() and ripples[-1].age<.025: ripples.pop_back()
			add_ripple(event.position)
		else: _up()
	elif event is InputEventScreenTouch:
		if event.pressed:
			if Time.get_ticks_msec()-last_pointer>60:
				last_pointer = Time.get_ticks_msec()
				pointer_origin = event.position
				pointer_active = true
				add_ripple(event.position)
		else: _up()
	elif event is InputEventScreenDrag and pointer_active and event.position.distance_to(pointer_origin)>10:
		cancel()
	elif event is InputEventKey and event.is_action_pressed("ui_cancel"):
		cancel()

func add_ripple(origin: Vector2) -> void:
	if button.disabled: return
	ripples.append({"origin":origin,"age":0.0,"fade":0.0,"released":false})
	if ripples.size()>3: ripples.pop_front()
	set_process(true)
	queue_redraw()

func cancel() -> void:
	_up()

func confirm() -> void:
	confirmation = .22
	set_process(true)

func reset() -> void:
	amount = 0.0
	velocity = 0.0
	target = 0.0
	confirmation = 0.0
	ripples.clear()
	_apply_geometry()
	queue_redraw()
	set_process(false)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(button): reset()

func _process(delta: float) -> void:
	if not is_instance_valid(button): return
	if button.disabled or not button.is_visible_in_tree(): reset(); return
	var steps := maxi(1,ceili(minf(delta,.04)/.004))
	var dt := minf(delta,.04)/steps
	for i in range(steps):
		velocity += (-1400.0*(amount-target)-2.0*.9*sqrt(1400.0)*velocity)*dt
		amount += velocity*dt
	if absf(amount-target)<.001 and absf(velocity)<.01:
		amount = target
		velocity = 0.0
	_apply_geometry()
	for ripple in ripples:
		ripple.age += delta
		if ripple.released or ripple.age>.65: ripple.fade += delta/.18
	ripples = ripples.filter(func(r): return r.fade<1.0)
	confirmation = maxf(0.0,confirmation-delta)
	queue_redraw()
	if velocity==0.0 and amount==target and ripples.is_empty() and confirmation==0.0: set_process(false)

func _apply_geometry() -> void:
	if not is_instance_valid(button): return
	for state in ["normal","hover","pressed"]:
		var style := button.get_theme_stylebox(state)
		if not style is StyleBoxFlat: continue
		var resource_id: int = style.get_instance_id()
		if not sources.has(state) or sources[state].id!=resource_id:
			# Native dialog buttons may inherit shared theme resources. Animate a private copy.
			style = style.duplicate()
			button.add_theme_stylebox_override(state,style)
			sources[state] = {"id":style.get_instance_id(),"radius":style.corner_radius_top_left}
		var base: float = sources[state].radius
		style.set_corner_radius_all(roundi(lerpf(base,maxf(3.0,base-3.0),amount)))
		style.expand_margin_left = -button.size.x*.0075*amount
		style.expand_margin_right = -button.size.x*.0075*amount
		style.expand_margin_top = -button.size.y*.0075*amount
		style.expand_margin_bottom = -button.size.y*.0075*amount
	button.queue_redraw()

func _rounded_polygon(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var r := minf(radius,minf(rect.size.x,rect.size.y)*.5)
	var centers := [rect.position+Vector2(r,r),rect.position+Vector2(rect.size.x-r,r),rect.end-Vector2(r,r),rect.position+Vector2(r,rect.size.y-r)]
	for corner in range(4):
		for step in range(9):
			var angle := PI+corner*PI*.5+step*PI/16.0
			points.append(centers[corner]+Vector2(cos(angle),sin(angle))*r)
	return points

func _draw() -> void:
	if not is_instance_valid(button) or button.disabled: return
	var inset := button.size*.0075*amount
	var bounds := Rect2(inset,button.size-inset*2.0)
	if bounds.size.x<1 or bounds.size.y<1: return
	var style := button.get_theme_stylebox("normal")
	var radius: float = style.corner_radius_top_left if style is StyleBoxFlat else 9.0
	var outline := _rounded_polygon(bounds,radius)
	var ink := button.get_theme_color("font_color")
	for ripple in ripples:
		var origin: Vector2 = ripple.origin
		var reach := maxf(maxf(origin.distance_to(bounds.position),origin.distance_to(bounds.end)),maxf(origin.distance_to(Vector2(bounds.end.x,bounds.position.y)),origin.distance_to(Vector2(bounds.position.x,bounds.end.y))))
		var progress := 1.0-pow(1.0-clampf(ripple.age/.46,0.0,1.0),3)
		var circle := PackedVector2Array()
		for i in range(48): circle.append(origin+Vector2.from_angle(TAU*i/48.0)*maxf(1,reach*progress))
		for polygon in Geometry2D.intersect_polygons(circle,outline):
			draw_colored_polygon(polygon,Color(ink,.12*(1.0-ripple.fade)))
	if confirmation>0:
		var ring := StyleBoxFlat.new()
		ring.bg_color = Color.TRANSPARENT
		ring.border_color = Color("e3bd78")
		ring.border_color.a = confirmation/.22*.7
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(roundi(radius))
		draw_style_box(ring,bounds)
