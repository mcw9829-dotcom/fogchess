extends Control
var angle := 0.0
func _ready() -> void: custom_minimum_size = Vector2(38,38)
func _process(delta: float) -> void: angle += delta*TAU; queue_redraw()
func _draw() -> void:
	draw_arc(size/2,16,0,TAU,48,Color("3a352f"),3,true)
	draw_arc(size/2,16,angle,angle+PI/2,16,Color("c69a5e"),3,true)
