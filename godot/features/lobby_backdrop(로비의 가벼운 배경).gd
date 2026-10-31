extends Control
## Approved digital tactical map. Decorative only; never owns pointer input.
const REFERENCE := Vector2(1120,760)
const ROUTE := [Vector2(.414,.81),Vector2(.44,.7),Vector2(.451,.59),Vector2(.425,.48),Vector2(.455,.345),Vector2(.515,.247),Vector2(.639,.164),Vector2(.756,.125),Vector2(.889,.163),Vector2(1.04,.29)]
var light := false
var phase := 0.0
var palette: Dictionary
var wash: GradientTexture2D
var reading_wash: GradientTexture2D
var glow: GradientTexture2D
var mist: GradientTexture2D
var contours: Array = []
var river := PackedVector2Array()
var motion_layer: Control
var exit_motion: Tween
var match_exit_armed := false

class MapMotion extends Control:
	var map: Control
	func _draw() -> void: map.draw_motion(self)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	motion_layer = MapMotion.new()
	motion_layer.map = self
	motion_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(motion_layer)
	motion_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_rebuild)
	visibility_changed.connect(func(): set_process(is_visible_in_tree()))
	set_light(light)
	_rebuild()

func set_light(value: bool) -> void:
	if wash and light==value: return
	light = value
	palette = {"edge":Color("#ece7dc"),"map":Color("#e6e8e7"),"line":Color("#4c6579"),"gold":Color("#9d712c"),"blue":Color("#4177a0"),"tree":Color("#66756f")} if light else {"edge":Color("#171a20"),"map":Color("#252a30"),"line":Color("#94a8ba"),"gold":Color("#e2bc6f"),"blue":Color("#81b7e6"),"tree":Color("#93a09e")}
	wash = _gradient([palette.edge,palette.map],Vector2(0,1),Vector2(1,0))
	reading_wash = _gradient([palette.edge,Color(palette.edge,0)],Vector2.ZERO,Vector2.RIGHT)
	glow = _gradient([Color(palette.gold,.23),Color(palette.gold,0)],Vector2(.5,.5),Vector2(1,.5))
	glow.fill = GradientTexture2D.FILL_RADIAL
	mist = _gradient([Color(palette.line,0),Color(palette.line,.032 if light else .040),Color(palette.line,0)],Vector2.ZERO,Vector2.DOWN)
	queue_redraw()
	if is_instance_valid(motion_layer): motion_layer.queue_redraw()

func _gradient(colors: Array, start: Vector2, finish: Vector2) -> GradientTexture2D:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray(colors)
	var offsets := PackedFloat32Array()
	for i in range(colors.size()): offsets.append(float(i)/float(colors.size()-1))
	ramp.offsets = offsets
	var texture := GradientTexture2D.new()
	texture.gradient = ramp
	texture.width = 128; texture.height = 128
	texture.fill_from = start; texture.fill_to = finish
	return texture

func _rebuild() -> void:
	contours.clear()
	for region in [[Vector2(.86,.12),Vector2(.27,.26),.5],[Vector2(.67,1.04),Vector2(.31,.22),2.2],[Vector2(1.09,.67),Vector2(.18,.44),1.8]]:
		for layer in range(7):
			var points := PackedVector2Array()
			for k in range(145):
				var angle := float(k)/144.0*TAU
				var wave := 1.0+.14*sin(3*angle+region[2])+.065*sin(7*angle+region[2]*.4)+.035*cos(11*angle)
				points.append((region[0]+Vector2(cos(angle),sin(angle))*region[1]*(.35+layer*.125)*wave)*size)
			contours.append({"points":points,"major":layer%3==0})
	river.clear()
	var segments := [[Vector2(.57,-.03),Vector2(.70,.18),Vector2(.82,.13),Vector2(.85,.39)],[Vector2(.85,.39),Vector2(.91,.6),Vector2(.78,.78),Vector2(.98,1.06)]]
	for segment in segments:
		for i in range(41):
			var t := float(i)/40.0
			river.append((pow(1-t,3)*segment[0]+3*pow(1-t,2)*t*segment[1]+3*(1-t)*t*t*segment[2]+pow(t,3)*segment[3])*size)
	queue_redraw()
	if is_instance_valid(motion_layer): motion_layer.queue_redraw()

func _draw() -> void:
	if not wash or size.x<=0 or size.y<=0: return
	draw_texture_rect(wash,Rect2(Vector2.ZERO,size),false)
	var spacing := Vector2(48,48)*size/REFERENCE
	for i in range(16):
		var x := size.x*.42+i*spacing.x
		if x<size.x: draw_line(Vector2(x,0),Vector2(x,size.y),Color(palette.line,.055),.6,true)
	for i in range(17):
		var y := size.y*22/760.0+i*spacing.y
		if y<size.y: draw_line(Vector2(size.x*.4,y),Vector2(size.x,y),Color(palette.line,.055),.6,true)
	for contour in contours:
		draw_polyline(contour.points,Color(palette.line,.23 if contour.major else .11),1.1 if contour.major else .7,true)
	if river.size()>1:
		draw_polyline(river,Color(palette.blue,.07),maxf(3,15*size.x/1120.0),true)
		draw_polyline(river,Color(palette.blue,.15),1.2,true)
	for i in range(ROUTE.size()-1):
		var from: Vector2 = ROUTE[i]*size
		var to: Vector2 = ROUTE[i+1]*size
		var length := from.distance_to(to)
		var cursor := 0.0
		while cursor<length:
			draw_line(from.lerp(to,cursor/length),from.lerp(to,minf(cursor+3.5,length)/length),Color(palette.gold,.34),1,true)
			cursor += 10.5
	for i in [0,2,4,6,8]: draw_arc(ROUTE[i]*size,3.2,0,TAU,24,Color(palette.gold,.48),1,true)
	for point in [Vector2(.49,.12),Vector2(.95,.72),Vector2(.51,.86),Vector2(.91,.91),Vector2(.64,.04)]:
		_grove(point*size)
	var north := size*Vector2(.966,.061)
	draw_line(north-Vector2(13,0),north+Vector2(13,0),Color(palette.line,.23),1,true)
	draw_line(north-Vector2(0,13),north+Vector2(0,13),Color(palette.line,.23),1,true)
	draw_colored_polygon(PackedVector2Array([north-Vector2(0,17),north+Vector2(-3,-5),north+Vector2(3,-5)]),Color(palette.gold,.45))
	# Leave the navigation column quiet, with a soft edge instead of a panel.
	draw_rect(Rect2(Vector2.ZERO,Vector2(size.x*.30,size.y)),palette.edge)
	draw_texture_rect(reading_wash,Rect2(Vector2(size.x*.30,0),Vector2(size.x*.20,size.y)),false)

func _grove(at: Vector2) -> void:
	var unit := clampf(size.x/1120.0,.7,1.1)
	for i in range(5):
		var center := at+Vector2((i%3)*9,(i/3)*10)*unit
		var triangle := PackedVector2Array([center+Vector2(0,-6)*unit,center+Vector2(-4,3)*unit,center+Vector2(4,3)*unit,center+Vector2(0,-6)*unit])
		draw_colored_polygon(triangle,Color(palette.tree,.18))
		draw_polyline(triangle,Color(palette.tree,.23),.8,true)
		draw_line(center+Vector2(0,2)*unit,center+Vector2(0,6)*unit,Color(palette.tree,.23),.8,true)

func draw_motion(canvas: Control) -> void:
	if not glow: return
	var cursor := fposmod(phase/34.0+.26,1.0)*(ROUTE.size()-1)
	var i := mini(ROUTE.size()-2,int(cursor))
	var point: Vector2 = ROUTE[i].lerp(ROUTE[i+1],cursor-i)*size
	canvas.draw_texture_rect(glow,Rect2(point-Vector2.ONE*12,Vector2.ONE*24),false)
	canvas.draw_circle(point,1.8,Color(palette.gold,.7),true,-1,true)
	for band in range(2):
		var y := size.y*(.16+band*.70)+sin(phase/12.0+band)*size.y*.018
		var shift := sin(phase/18.0+band)*size.x*.025
		canvas.draw_texture_rect(mist,Rect2(Vector2(size.x*.43+shift,y-22),Vector2(size.x*.62,57)),false)

func _process(delta: float) -> void:
	phase += minf(delta,.1)
	motion_layer.queue_redraw()

func arm_match_exit() -> void:
	match_exit_armed = is_visible_in_tree()

func set_lobby_visible(value: bool) -> void:
	if is_instance_valid(exit_motion): exit_motion.kill()
	if value:
		match_exit_armed = false
		modulate = Color.WHITE
		scale = Vector2.ONE
		show()
		set_process(true)
	elif match_exit_armed:
		match_exit_armed = false
		# Only the decorative map moves; live board hit targets stay coherent.
		pivot_offset = size*Vector2(.68,.50)
		exit_motion = create_tween().set_parallel(true)
		exit_motion.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		exit_motion.tween_property(self,"modulate:a",0.0,1.0)
		exit_motion.tween_property(self,"scale",Vector2.ONE*1.035,1.0)
		exit_motion.chain().tween_callback(func(): hide();scale=Vector2.ONE;modulate=Color.WHITE)
	else:
		hide()
		scale=Vector2.ONE;modulate=Color.WHITE
