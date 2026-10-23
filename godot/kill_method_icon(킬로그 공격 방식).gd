extends Control
var method := "melee"
var ink := Color("#eee2cc")

func _ready() -> void:
	custom_minimum_size = Vector2(26,22)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var at := size/2
	if method=="melee":
		for sign_value in [-1,1]:
			var a := at+Vector2(-7*sign_value,-7)
			var b := at+Vector2(7*sign_value,7)
			draw_line(a,b,ink,1.8,true)
			draw_line(b+Vector2(-4*sign_value,0),b+Vector2(0,-4),ink,1.8,true)
	elif method=="barrage":
		for y in [-4,4]:
			draw_line(at+Vector2(-10,y),at+Vector2(8,y),ink,1.8,true)
			draw_polyline(PackedVector2Array([at+Vector2(4,y-3),at+Vector2(9,y),at+Vector2(4,y+3)]),ink,1.8,true)
	else:
		draw_arc(at,6,0,TAU,24,ink,1.5,true)
		draw_line(at-Vector2(10,0),at+Vector2(10,0),ink,1.5,true)
		draw_line(at-Vector2(0,10),at+Vector2(0,10),ink,1.5,true)
