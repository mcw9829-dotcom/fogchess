extends Control
var elapsed := 0.0
var origin := Vector2.ZERO
var radius := 0.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>=.5: queue_free(); return
	queue_redraw()
func _draw() -> void:
	var t := clampf(elapsed/.5,0,1)
	draw_circle(origin,radius*(1-pow(1-t,3)),Color(1,1,1,.16*(1-t)))
