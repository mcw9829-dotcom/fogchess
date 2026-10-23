extends Control
## Decorative clock activity; the authoritative countdown remains server-owned.
var active := false
var elapsed := 0.0
var ink := Color("ffcf73")
const CYCLE := 3.4
const POUR := 2.8
func _ready() -> void:
	custom_minimum_size = Vector2(30,30)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(active and is_visible_in_tree())
func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED: set_process(active and is_visible_in_tree())
func set_state(running: bool, color: Color) -> void:
	active = running
	ink = color
	set_process(active and is_visible_in_tree())
	queue_redraw()
func _process(delta: float) -> void:
	elapsed = fmod(elapsed+delta,CYCLE)
	queue_redraw()
func _draw() -> void:
	var fraction := minf(elapsed/POUR,1.0)
	var flip := clampf((elapsed-POUR)/(CYCLE-POUR),0.0,1.0)
	var angle := PI*flip*flip*(3.0-2.0*flip)
	draw_set_transform(size/2,angle,Vector2.ONE*(minf(size.x,size.y)/30.0))
	var glass := ink
	glass.a = .7
	draw_polyline(PackedVector2Array([Vector2(-6,-8),Vector2(6,-8),Vector2(4,-3),Vector2(1,0),Vector2(4,3),Vector2(6,8),Vector2(-6,8),Vector2(-4,3),Vector2(-1,0),Vector2(-4,-3),Vector2(-6,-8)]),glass,1.4,true)
	if fraction<.99:
		var fill_y := lerpf(-7,-1,fraction)
		var half_width := 5*(1.0-fraction)
		draw_colored_polygon(PackedVector2Array([Vector2(-half_width,fill_y),Vector2(half_width,fill_y),Vector2(0,-1)]),ink)
	if fraction>.01:
		draw_colored_polygon(PackedVector2Array([Vector2(-5,7),Vector2(5,7),Vector2(0,7-6*fraction)]),ink)
	if flip==0: draw_line(Vector2(0,0),Vector2(0,6-6*fraction),ink,1.1,true)
	for y in [-11,11]: draw_line(Vector2(-8,y),Vector2(8,y),ink,2.5,true)
	draw_set_transform(Vector2.ZERO)
