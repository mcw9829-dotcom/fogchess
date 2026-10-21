extends Button
var kind := "move"
var caption := "이동"
var light := false

func _ready() -> void:
	custom_minimum_size = Vector2(46,46)
	size = Vector2(46,46)
	pivot_offset = size/2
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _draw() -> void:
	var ink := Color("#423524") if light else Color("#f1dfbb")
	if disabled: ink = Color("#858079")
	draw_circle(Vector2(23,23),22,Color("#fff8ea") if light else Color("#302b24"))
	draw_arc(Vector2(23,23),22,0,TAU,48,Color.WHITE if is_hovered() or has_focus() else Color("#c69a5e"),2,true)
	var at := Vector2(23,17)
	if kind=="attack":
		for sign_value in [-1,1]:
			var a := at+Vector2(-8*sign_value,-8)
			var b := at+Vector2(8*sign_value,8)
			draw_line(a,b,ink,2,true)
			draw_polyline(PackedVector2Array([a+Vector2(0,5),a,a+Vector2(5*sign_value,0)]),ink,2,true)
			draw_line(b+Vector2(-6*sign_value,0),b+Vector2(0,-6),ink,2,true)
	elif kind=="scan":
		for radius in [4,9]: draw_arc(at,radius,0,TAU,24,ink,1.5,true)
		draw_line(at,at+Vector2(8,-8),ink,2,true)
	elif kind in ["fire","barrage"]:
		draw_arc(at,7,0,TAU,24,ink,1.5,true)
		draw_line(at-Vector2(11,0),at+Vector2(11,0),ink,2,true)
		draw_line(at-Vector2(0,11),at+Vector2(0,11),ink,2,true)
		if kind=="barrage": draw_circle(at,3,ink)
	elif kind=="none":
		draw_arc(at,8,0,TAU,24,ink,1.5,true)
		draw_line(at-Vector2(6,6),at+Vector2(6,6),ink,2,true)
	else:
		draw_line(at+Vector2(-7,7),at+Vector2(7,-7),ink,2,true)
		draw_polyline(PackedVector2Array([at+Vector2(-1,-7),at+Vector2(7,-7),at+Vector2(7,1)]),ink,2,true)
	draw_string(get_theme_default_font(),Vector2(23-get_theme_default_font().get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10).x/2,38),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,10,ink)
