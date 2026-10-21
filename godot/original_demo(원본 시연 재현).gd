extends Control
## The deployed game's scene data and timeline, rendered by Godot.
signal caption_changed(text: String)
signal activated()
signal playback_changed(playing: bool)
var spec: Dictionary = {}
var frames: Array = []
var index := 0
var elapsed := 0.0
var transition := 0.0
var running := false
var intro := false
var effects := true
var sound: Callable
var cols := 7
var fx: Control
var textures: Dictionary = {}
var previous: Dictionary = {}
var shown: Dictionary = {}
var state: Dictionary = {}
var host: Control
static var source: Dictionary = {}

static func scenes() -> Dictionary:
	if source.is_empty(): source = integers(JSON.parse_string(FileAccess.get_file_as_string("res://original_scenes(원본 시연 데이터).json")))
	return source

static func integers(value: Variant) -> Variant:
	if value is float: return int(value) if value==floor(value) else value
	if value is Array: return value.map(integers)
	if value is Dictionary:
		for key in value: value[key] = integers(value[key])
	return value

func _ready() -> void:
	for kind in "kqrbnp":
		for side in "ld": textures[kind+side] = load("res://pieces/Chess_%st45.svg" % (kind+side))
	fx = preload("res://fx_layer(파티클·전투 이펙트).gd").new()
	fx.cols = cols
	add_child(fx)
	mouse_filter = Control.MOUSE_FILTER_PASS
	apply_frame(0,true)
	if not intro:
		mouse_entered.connect(start)
		mouse_exited.connect(func(): if host==null: stop())

func start() -> void:
	if running: return
	activated.emit()
	running = true
	playback_changed.emit(true)
	index = 0
	elapsed = 0
	apply_frame(0,true)

func stop() -> void:
	if not running: return
	running = false
	playback_changed.emit(false)
	index = 0
	elapsed = 0
	fx.clear()
	apply_frame(0,true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT: start()

func frame_duration(which: int) -> float:
	if not intro: return .85
	return float(frames[which].get("hold",4000))/1000.0+(1.2 if which==frames.size()-1 else 0)

func _process(delta: float) -> void:
	var side := minf(size.x-4,size.y-4)
	fx.position = Vector2((size.x-side)/2,2)
	fx.size = Vector2.ONE*side
	if not is_visible_in_tree():
		if not intro and running: stop()
		return
	transition = minf(.55,transition+delta)
	if running:
		elapsed += delta
		if elapsed>=frame_duration(index):
			elapsed -= frame_duration(index)
			index = (index+1)%frames.size()
			apply_frame(index,intro and index==0)
	queue_redraw()

func positions(frame: Dictionary) -> Dictionary:
	if intro: return frame.get("at",{})
	var result := {"self":frame.get("p",[3,3])}
	for i in range(frame.get("foes",[]).size()): result["foe"+str(i)] = frame.foes[i]
	return result

func piece(id: String) -> Dictionary:
	if intro: return spec.pieces[id]
	return {"t":spec.t if id=="self" else "P","o":"W" if id=="self" else "B"}

func lit(frame: Dictionary,r: int,c: int) -> bool:
	if not intro: return not [r,c] in frame.get("fog",[])
	return [r,c] in frame.get("lit",[]) or [r,c] in frame.get("scan",[]) or r in spec.get("zone",[])

func apply_frame(which: int,first: bool=false) -> void:
	if frames.is_empty(): return
	previous = positions(state)
	state = frames[which]
	transition = .55 if first else 0.0
	var current := positions(state)
	var visible: Dictionary = {}
	for id in current:
		var rc: Variant = current[id]
		if rc==null: continue
		var info := piece(id)
		if info.o=="W" or lit(state,rc[0],rc[1]):
			visible[id] = true
			if intro and info.o!="W" and not shown.has(id) and not first and effects: reveal(rc)
	shown = visible
	if not first:
		if effects:
			for id in state.get("flash",[]):
				if current.get(id)!=null: reveal(current[id])
			if state.get("fx") is Dictionary: fx.play(state.fx)
		if state.has("snd") and sound.is_valid(): sound.call(state.snd)
	caption_changed.emit(str(state.get("cap","")))
	queue_redraw()

func reveal(rc: Array) -> void:
	var pos: Vector2 = fx.point(rc)
	var cw: float = fx.cell_width()
	fx.flash(pos,cw*1.1,.25,Color(1,.902,.627,.95))
	fx.ring(pos,cw*.2,cw*1.2,.5,Color(1,.863,.55,.9),3)

func easing(value: float) -> float:
	# CSS cubic-bezier(.4,0,.2,1): invert its x coordinate.
	var low := 0.0
	var high := 1.0
	for i in range(12):
		var t := (low+high)/2
		var x := 3*(1-t)*(1-t)*t*.4+3*(1-t)*t*t*.2+t*t*t
		if x<value: low=t
		else: high=t
	var t := (low+high)/2
	return 3*(1-t)*t*t+t*t*t

func _draw() -> void:
	if fx==null: return
	var side: float = fx.size.x
	var cw := side/cols
	var offset: Vector2 = fx.position+fx.shake_offset
	var border := StyleBoxFlat.new()
	border.bg_color = Color(.2,.2,.2)
	border.set_border_width_all(2)
	border.border_color = Color(1,1,1,.7)
	border.set_corner_radius_all(6)
	draw_style_box(border,Rect2(offset-Vector2.ONE*2,Vector2.ONE*(side+4)))
	for r in range(cols):
		for c in range(cols):
			var rect := Rect2(offset+Vector2(c,r)*cw,Vector2.ONE*cw)
			draw_rect(rect,Color("f0d9b5") if (r+c)%2==0 else Color("b58863"))
			var terrain: Dictionary = spec.get("terrain",{})
			if [r,c] in terrain.get("forest",[]): draw_texture_rect(load("res://terrain/forest_%d.svg" % ((r+c)%2)),rect,false)
			elif [r,c] in terrain.get("bush",[]): draw_texture_rect(load("res://terrain/bush_%d_%d.svg" % [r,c]),rect,false)
			if not lit(state,r,c): draw_rect(rect,Color(10.0/255,12.0/255,22.0/255,.72))
			if r in spec.get("zone",[]): draw_rect(rect.grow(-1),Color(.47,.784,1,.55),false,2)
			if [r,c] in state.get("scan",[]): draw_rect(rect,Color(.588,.373,.882,.35))
			if [r,c] in state.get("beam",[]): draw_rect(rect,Color(.137,.647,.902,.42))
			if [r,c] in state.get("hit",[]): draw_rect(rect,Color(.839,.188,.173,.35))
			if [r,c] in state.get("dot",[]): draw_circle(rect.get_center(),cw*.2*(.9-.15*cos(elapsed/.8*TAU)),Color(.22,.549,.227,.7))
	var current := positions(state)
	# Enemy first, friendly pieces above them, matching .demop z-index.
	var ids := current.keys()
	ids.sort_custom(func(a,b): return piece(a).o=="B" and piece(b).o=="W")
	for id in ids:
		var rc: Variant = current[id]
		if rc==null or not shown.has(id): continue
		var info := piece(id)
		var pos := Vector2(float(rc[1]),float(rc[0]))
		if previous.get(id)!=null and not fx.reduced:
			var old: Array = previous[id]
			pos = Vector2(old[1],old[0]).lerp(pos,easing(transition/.55))
		var alpha := .32 if id in state.get("ghost",[]) else 1.0
		if state.get("exposed",false) and id=="self": draw_circle(offset+(pos+Vector2.ONE*.5)*cw,cw*.48,Color(.84,.188,.17,.35))
		var texture: Texture2D = textures[str(info.t).to_lower()+("l" if info.o=="W" else "d")]
		var piece_box := Rect2(offset+pos*cw,Vector2.ONE*cw)
		if not intro and running and id=="self": preload("res://piece_outline(기물 선택 외곽선).gd").draw(self,texture,piece_box,alpha)
		draw_texture_rect(texture,piece_box,false,Color(1,1,1,alpha))
