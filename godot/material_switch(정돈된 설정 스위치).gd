extends CheckButton
## Native toggle semantics, fixed hit area, Standard spring thumb.
const Motion = preload("res://calm_motion(차분한 깊이 모션 기준).gd")
var travel := 0.0
var start := 0.0
var elapsed := 0.0
var speed := 0.0
var goal := 0.0
func _ready() -> void:
	custom_minimum_size = Vector2(62,44)
	var image := Image.create(54,32,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var blank := ImageTexture.create_from_image(image)
	for key in ["checked","unchecked","checked_disabled","unchecked_disabled","checked_mirrored","unchecked_mirrored","checked_disabled_mirrored","unchecked_disabled_mirrored"]:
		add_theme_icon_override(key,blank)
	travel = 1.0 if button_pressed else 0.0
	goal = travel
	toggled.connect(func(value): start = travel; elapsed = 0.0; goal = 1.0 if value else 0.0; set_process(true))
	set_process(false)
func _process(delta: float) -> void:
	elapsed += delta
	travel = lerpf(start,goal,Motion.ease(elapsed/Motion.PAGE))
	if elapsed>=Motion.PAGE:
		travel = goal
		set_process(false)
	queue_redraw()
func _draw() -> void:
	var origin := Vector2(size.x-58,(size.y-32)*.5)
	var light := get_theme_color("font_color").get_luminance()<.5
	var off := Color("bdc4b8") if light else Color("4b574c")
	var on := Color("e3bd78")
	var track := StyleBoxFlat.new()
	track.bg_color = off.lerp(on,clampf(travel,0,1))
	if disabled: track.bg_color.a = .45
	track.set_corner_radius_all(16)
	draw_style_box(track,Rect2(origin,Vector2(54,32)))
	var center := origin+Vector2(16+22*travel,16)
	draw_circle(center,12,Color("f8f5f0") if light else Color("222827"))
	if travel>.02:
		var color := Color("775523") if light else on
		color.a = clampf(travel,0,1)
		draw_line(center+Vector2(-4,0),center+Vector2(-1,3),color,2,true)
		draw_line(center+Vector2(-1,3),center+Vector2(5,-4),color,2,true)
