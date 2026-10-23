extends Control
## All piece visibility, terrain and legal targets come from the server.
signal tapped(cell: Vector2i)
signal selection_cancelled()
signal dragged(origin: Vector2i, target: Vector2i)
var view: Dictionary = {}
var selected := Vector2i(-1,-1)
var targets: Array = []
var ranges: Array = []
var mode := "move"
var flip := false
var colorblind := false:
	set(value):
		colorblind = value
		if is_instance_valid(fx): fx.colorblind = value
		queue_redraw()
var effects := true
var textures: Dictionary = {}
var piece_content_rects: Dictionary = {}
var terrain_textures: Dictionary = {}
var fog_alpha: Dictionary = {}
var clock := 0.0
var bursts: Array = []
var fx: Control
var hover := Vector2i(-1,-1)
var down := Vector2i(-1,-1)
var right_down := Vector2i(-1,-1)
var down_pos := Vector2.ZERO
var is_dragging := false
var annotations: Array = []
var piece_motion: Dictionary = {}
var recoil: Dictionary = {}
var brush_reactions: Dictionary = {}

func _ready() -> void:
	fx = preload("res://fx_layer(파티클·전투 이펙트).gd").new()
	add_child(fx)
	fx.colorblind = colorblind
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(300,300)
	for kind in "kqrbnp":
		for side in "ld":
			textures[kind+side] = load("res://pieces/Chess_%st45.svg" % (kind+side))
	for variant in range(2): terrain_textures["forest_%d" % variant] = load("res://terrain/forest_%d.svg" % variant)
	for r in range(12):
		for c in range(12): terrain_textures["bush_%d_%d" % [r,c]] = load("res://terrain/bush_%d_%d.svg" % [r,c])
	mouse_exited.connect(func(): hover = Vector2i(-1,-1))

func set_view(data: Dictionary, black: bool) -> void:
	# A new snapshot must never leave a stale sprite over newly concealed cells.
	if data.get("room")!=view.get("room") or black!=flip or data.get("yourColor")!=view.get("yourColor"):
		piece_motion.clear()
		recoil.clear()
	elif not piece_motion.is_empty():
		var destination: Vector2i = piece_motion.to
		var grid: Array = data.get("grid",[])
		var current: Variant = grid[destination.x][destination.y].get("p") if grid.size()==12 else null
		if not current is Dictionary or current.get("o")!=piece_motion.p.o or current.get("t")!=piece_motion.p.t: piece_motion.clear()

	if view.get("room", "") != data.get("room", "") or view.get("yourColor") != data.get("yourColor"):
		fog_alpha.clear()
		bursts.clear()
		if is_instance_valid(fx): fx.clear()
	if data.get("room")!=view.get("room") or data.get("yourColor")!=view.get("yourColor"): brush_reactions.clear()
	view = data
	flip = black
	queue_redraw()

func geometry() -> Rect2:
	var side := maxf(1.0, minf(size.x-36, size.y-36))
	return Rect2((size-Vector2.ONE*side)/2, Vector2.ONE*side)

func center(cell: Vector2i) -> Vector2:
	var pos := Vector2(11-cell.y,11-cell.x) if flip else Vector2(cell.y,cell.x)
	return geometry().position + (pos+Vector2.ONE*0.5)*geometry().size.x/12

func cell_at(pos: Vector2) -> Vector2i:
	var rect := geometry()
	if not rect.has_point(pos): return Vector2i(-1,-1)
	var xy := Vector2i((pos-rect.position)/(rect.size.x/12))
	return Vector2i(11-xy.y,11-xy.x) if flip else Vector2i(xy.y,xy.x)

func tile(cell: Vector2i) -> Dictionary:
	var grid: Array = view.get("grid", [])
	if cell.x < 0 or cell.y < 0 or cell.x >= grid.size() or cell.y >= grid[cell.x].size(): return {}
	return grid[cell.x][cell.y]

func _get_tooltip(at_position: Vector2) -> String:
	if is_dragging or down.x>=0: return ""
	var cell := cell_at(at_position)
	var p: Variant = tile(cell).get("p")
	if not p is Dictionary or p.get("o")!=view.get("yourColor"): return ""
	var s := geometry().size.x/12.0
	# The same screen-space offsets as the drawn badges, including flipped boards.
	var badge := center(cell)+Vector2(s*.3,-s*.3)
	if at_position.distance_to(badge)<=maxf(7.0,s*.18):
		for exposure in view.get("exposed",[]):
			if exposure.get("pid")==p.get("id"): return "상대에게 위치가 보이는 중입니다."
	badge = center(cell)+Vector2(-s*.3,-s*.3)
	if at_position.distance_to(badge)<=maxf(7.0,s*.18):
		for reload_state in view.get("reloading",[]):
			if reload_state.get("pid")==p.get("id"): return "사격 후 내 차례 한 턴 동안 재장전합니다. 이동은 가능합니다."
	return ""

func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.is_empty(): return null
	return preload("res://status_tooltip(상태 설명 카드).gd").new(self,for_text)

func contains(cells: Array, cell: Vector2i) -> bool:
	for rc in cells:
		if int(rc[0]) == cell.x and int(rc[1]) == cell.y: return true
	return false

func play_fx(data: Dictionary) -> void:
	if data.is_empty(): return
	if effects and not fx.reduced and data.get("confirmed_source",false) and data.get("motion_piece") is Dictionary:
		for key in ["from","to"]:
			if data.get(key) is Array:
				var cell := Vector2i(data[key][0],data[key][1])
				if int(tile(cell).get("t",0))==3: brush_reactions[cell] = -.28 if key=="to" else 0.0
	var visual := data.duplicate(true)
	if effects and not fx.reduced and data.get("motion_piece") is Dictionary and data.get("from") is Array and data.get("to") is Array:
		var destination := Vector2i(int(data.to[0]),int(data.to[1]))
		var current: Variant = tile(destination).get("p")
		# Local confirmed action only. Do not reconstruct concealed enemy identities.
		if current is Dictionary and current.get("t")==data.motion_piece.get("t") and current.get("o")==data.motion_piece.get("o"):
			piece_motion = {"p":data.motion_piece,"from":Vector2i(int(data.from[0]),int(data.from[1])),"to":destination,"age":0.0,"duration":.28 if current.t=="N" else .24}
			visual["delay"] = piece_motion.duration
	if effects and not fx.reduced and data.get("confirmed_source",false) and data.get("from") is Array and data.get("type") in ["fire","barrage"]:
		recoil = {"cell":Vector2i(data.from[0],data.from[1]),"target":Vector2i(data.cells[0][0],data.cells[0][1]),"age":0.0}

	if effects:
		fx.position = geometry().position
		fx.size = geometry().size
		fx.flipped = flip
		fx.play(visual)
	elif data.get("type")!="move":
		bursts.append({"age":0.0,"type":data.get("type","move"),"cells":data.get("cells",[])})

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		hover = cell_at(event.position)
		if down.x >= 0 and down_pos.distance_to(event.position)>7:
			is_dragging = true
	if event is InputEventMouseButton:
		var cell := cell_at(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				selection_cancelled.emit()
				right_down = cell
			elif right_down.x>=0 and cell.x>=0:
				annotations.append([right_down,cell])
				right_down = Vector2i(-1,-1)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				annotations.clear()
				down = cell
				down_pos = event.position
				is_dragging = false
			else:
				if down.x>=0 and cell.x>=0:
					if is_dragging and down!=cell: dragged.emit(down,cell)
					else: tapped.emit(cell)
				down = Vector2i(-1,-1)
				is_dragging = false
		accept_event()

func _process(delta: float) -> void:
	clock += delta
	for cell in brush_reactions.keys():
		brush_reactions[cell] += delta
		if brush_reactions[cell]>.55: brush_reactions.erase(cell)
	if not effects or fx.reduced: brush_reactions.clear()
	if not effects or fx.reduced:
		piece_motion.clear()
		recoil.clear()
	if not piece_motion.is_empty():
		piece_motion.age += delta
		if piece_motion.age>=piece_motion.duration: piece_motion.clear()
	if not recoil.is_empty():
		recoil.age += delta
		if recoil.age>=.22: recoil.clear()
	fx.position = geometry().position
	fx.size = geometry().size
	fx.flipped = flip
	for burst in bursts: burst.age += delta
	bursts = bursts.filter(func(b): return b.age<0.9)
	queue_redraw()

func _piece_opacity(cell: Vector2i) -> float:
	return .65 if int(tile(cell).get("t",0))==3 else 1.0

func _bush(cell: Vector2i, box: Rect2, s: float) -> void:
	# Original grass silhouettes and oval base, 20% taller, anchored to tile bottom.
	# A small brightness lift improves contrast without filling the checkerboard.
	var grass_box := Rect2(box.position-Vector2(0,s*.20),Vector2(s,s*1.20))
	if brush_reactions.has(cell) and brush_reactions[cell]>=0:
		var age: float = brush_reactions[cell]
		grass_box.position.x += sin(age*32)*s*.035*(1-age/.55)
	var tint := Color(1.10,1.10,1.10,1).lerp(Color(14.0/255,18.0/255,22.0/255),float(fog_alpha.get(cell,0)))
	draw_texture_rect(terrain_textures["bush_%d_%d" % [cell.x,cell.y]],grass_box,false,tint)

func _draw() -> void:
	if is_instance_valid(fx): draw_set_transform(fx.shake_offset)
	var rect := geometry()
	var s := rect.size.x/12
	draw_style_box(_frame(),rect.grow(5))
	for r in range(12):
		for c in range(12):
			var cell := Vector2i(r,c)
			var at := center(cell)
			var box := Rect2(at-Vector2.ONE*s/2,Vector2.ONE*s)
			var data := tile(cell)
			draw_rect(box,Color("#f0d9b5") if (r+c)%2==0 else Color("#b58863"))
			var terrain := int(data.get("t",0))
			if terrain==1:
				draw_texture_rect(terrain_textures["forest_%d" % ((r+c)%2)],box,false)
			if terrain==2: _river(box,cell,s)
			var alpha := float(data.get("f",1))*.86
			# Conceal newly hidden cells immediately; only revealing fades in.
			var previous := float(fog_alpha.get(cell,alpha))
			fog_alpha[cell] = alpha if alpha>previous else move_toward(previous,alpha,.055)
			draw_rect(box,Color(14.0/255,18.0/255,22.0/255,fog_alpha[cell]))
			if view.get("phase")=="setup" and view.get("yourColor") in ["W","B"]:
				var zone: Array = view.get("zone",[9,11])
				if r>=zone[0] and r<=zone[1]: draw_rect(box.grow(-2),Color(.4,.8,1,.3),false,1)
			if contains(view.get("scanTiles",[]),cell):
				draw_rect(box.grow(-2),signal_color("scan",.7),false,2)
			if contains(ranges,cell): draw_rect(box,signal_color(mode,.15))
			var p: Variant = data.get("p")
			if p is Dictionary and not (is_dragging and down==cell) and not _moving_at(cell):
				_piece(p,at,s,_piece_opacity(cell),true,selected==cell)
			if contains(targets,cell):
				var col := signal_color(mode,.85)
				if mode=="scan":
					draw_rect(box,signal_color("scan",.2))
					draw_rect(box.grow(-4),signal_color("scan"),false,2)
				elif data.get("p") or mode!="move": draw_arc(at,s*.42,0,TAU,32,col,3,true)
				else: draw_circle(at,s*.17,col)
			if p is Dictionary and p.get("o")==view.get("yourColor"):
				for reload_state in view.get("reloading",[]):
					if reload_state.get("pid")==p.get("id"):
						# ? means reload; ! at top-right means the enemy can see this piece.
						var badge := box.position+Vector2(s*.2,s*.2)
						preload("res://status_badge(공통 상태 배지).gd").draw_reload(self,badge,s)
				for exposure in view.get("exposed",[]):
					if exposure.get("pid")==p.get("id"):
						var badge := box.position+Vector2(s*.8,s*.2)
						preload("res://status_badge(공통 상태 배지).gd").exposure(self,badge,s)
			if hover==cell and selected!=cell: draw_rect(box.grow(-1),Color(1,1,1,.45),false,1)
	if not piece_motion.is_empty():
		var t: float = clampf(piece_motion.age/piece_motion.duration,0,1)
		var eased: float = t*t*(3-2*t)
		var at := center(piece_motion.from).lerp(center(piece_motion.to),eased)
		var visible_here: bool = piece_motion.p.o==view.get("yourColor") or tile(cell_at(at)).get("f",1)==0
		if visible_here:
			var lift: float = sin(t*PI)*s*(.42 if piece_motion.p.t=="N" else .10)
			draw_circle(at+Vector2(0,s*.28),s*.22,Color(0,0,0,.18))
			_piece(piece_motion.p,at-Vector2(0,lift),s*(1+.06*sin(t*PI)),_piece_opacity(cell_at(at)),false,selected==piece_motion.to)
	if mode=="scan" and contains(targets,hover):
		for dr in range(2):
			for dc in range(2):
				var cell := hover+Vector2i(dr,dc)
				if cell.x<12 and cell.y<12: draw_rect(Rect2(center(cell)-Vector2.ONE*s/2,Vector2.ONE*s),signal_color("scan",.25))
	if is_dragging and tile(down).get("p") is Dictionary:
		_piece(tile(down).p,get_local_mouse_position(),s,_piece_opacity(down),true,true)
	# Foreground grass covers the feet of stationary, moving and dragged pieces.
	# Use each tile's fog tint so hidden terrain does not become bright again.
	for r in range(12):
		for c in range(12):
			var cell := Vector2i(r,c)
			if int(tile(cell).get("t",0))!=3: continue
			var box := Rect2(center(cell)-Vector2.ONE*s/2,Vector2.ONE*s)
			_bush(cell,box,s)
			# Interaction borders stay legible above foreground foliage.
			if contains(view.get("scanTiles",[]),cell): draw_rect(box.grow(-2),signal_color("scan",.7),false,2)
			if hover==cell and selected!=cell: draw_rect(box.grow(-1),Color(1,1,1,.45),false,1)
	for a in annotations: _annotation(a[0],a[1],s)
	for b in bursts:
		for rc in b.cells:
			var at := center(Vector2i(int(rc[0]),int(rc[1])))
			var progress: float = b.age/.9
			var col := Color(.59,.37,.88,1-progress) if b.type=="scan" else Color(1,.58,.22,1-progress)
			if b.type in ["fire","barrage"]:
				draw_circle(at,s*(.12+progress*.48),Color(1,.28,.1,(1-progress)*.3))
				draw_circle(at,s*(.07+progress*.2),Color(1,.94,.7,(1-progress)*.85))
			elif b.type=="scan":
				draw_rect(Rect2(at-Vector2.ONE*s/2,Vector2.ONE*s),Color(.59,.37,.88,(1-progress)*.3))
			draw_arc(at,s*(.1+progress*.65),0,TAU,32,col,3,true)
			if b.type!="scan":
				for i in range(8): draw_circle(at+Vector2.from_angle(i*TAU/8)*s*progress*.75,2.5*(1-progress),col)
	var font := ThemeDB.fallback_font
	for i in range(12):
		var cell := Vector2i(11,i)
		var at := center(cell)
		draw_string(font,Vector2(at.x-4,rect.position.y-6),String.chr(97+i),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#9a938a"))
		at = center(Vector2i(i,0))
		draw_string(font,Vector2(rect.position.x-17,at.y+4),str(i+1),HORIZONTAL_ALIGNMENT_RIGHT,14,11,Color("#9a938a"))

func _annotation(source: Vector2i, target: Vector2i, cell_size: float) -> void:
	var begin := center(source)
	var end := center(target)
	# Scale the solid stroke with the tile, without an outline.
	var stroke := clampf(cell_size*.085,2.5,6.0)
	var ink := Color("#0072b2") if colorblind else Color("#16834b")
	if begin.is_equal_approx(end):
		draw_arc(begin,cell_size*.4,0,TAU,64,ink,stroke,true)
	else:
		var direction := (begin-end).normalized()
		draw_line(_annotation_start(source,end,cell_size,stroke),end,ink,stroke,true)
		draw_polyline(PackedVector2Array([end+direction.rotated(.55)*cell_size*.3,end,end+direction.rotated(-.55)*cell_size*.3]),ink,stroke,true)

func _annotation_start(source: Vector2i, end: Vector2, cell_size: float, stroke: float) -> Vector2:
	var begin := center(source)
	var piece: Variant = tile(source).get("p")
	# Only the visible source piece shortens a line; crossed pieces and the tip
	# retain the existing overlay order. Hidden pieces must not affect annotations.
	if not piece is Dictionary or begin.is_equal_approx(end): return begin
	var key := str(piece.t).to_lower()+("l" if piece.o=="W" else "d")
	if not piece_content_rects.has(key):
		var texture: Texture2D = textures.get(key)
		if texture==null: return begin
		var pixels := texture.get_image()
		if pixels==null: return begin
		if pixels.is_compressed(): pixels.decompress()
		var used := pixels.get_used_rect()
		var dimensions := Vector2(pixels.get_size())
		piece_content_rects[key] = Rect2(Vector2(used.position)/dimensions,Vector2(used.size)/dimensions)
	var content: Rect2 = piece_content_rects[key]
	var sprite_size := cell_size*.86
	var bounds := Rect2(begin-Vector2.ONE*sprite_size*.5+content.position*sprite_size,content.size*sprite_size).grow(stroke*.5+1.0)
	var direction := (end-begin).normalized()
	var exit_x := INF if is_zero_approx(direction.x) else ((bounds.end.x if direction.x>0 else bounds.position.x)-begin.x)/direction.x
	var exit_y := INF if is_zero_approx(direction.y) else ((bounds.end.y if direction.y>0 else bounds.position.y)-begin.y)/direction.y
	return begin+direction*maxf(0.0,minf(exit_x,exit_y))

func _frame() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#3a352f")
	style.set_corner_radius_all(3)
	style.shadow_color = Color(0,0,0,.45)
	style.shadow_size = 14
	style.shadow_offset = Vector2(0,6)
	style.set_border_width_all(3)
	# Turn ownership is shown in the HUD; selection is shown on the piece itself.
	style.border_color = Color("#57534c")
	return style

func _piece(p: Dictionary, at: Vector2, s: float, opacity: float, shadow: bool=true, highlighted: bool=false) -> void:
	if not recoil.is_empty() and center(recoil.cell).distance_to(at)<1:
		var direction := (center(recoil.target)-at).normalized()
		at -= direction*sin(clampf(recoil.age/.22,0,1)*PI)*s*.10
	var key: String = str(p.t).to_lower()+("l" if p.o=="W" else "d")
	var texture: Texture2D = textures.get(key)
	if texture:
		if shadow: draw_circle(at+Vector2(s*.03,s*.3),s*.25,Color(0,0,0,.2*opacity))
		var piece_box := Rect2(at-Vector2.ONE*s*.43,Vector2.ONE*s*.86)
		if highlighted: preload("res://piece_outline(기물 선택 외곽선).gd").draw(self,texture,piece_box,opacity)
		draw_texture_rect(texture,piece_box,false,Color(1,1,1,opacity))

func _river(box: Rect2, cell: Vector2i, s: float) -> void:
	for stripe in range(8):
		var t := float(stripe)/7
		draw_rect(Rect2(box.position+Vector2(0,s*stripe/8),Vector2(s,s/8+.5)),Color("#58b1e7").lerp(Color("#2f7bb2"),t))
	for i in range(3):
		var shift := fmod((clock*.18 if effects else 0.0)+i*.31+cell.x*.12,1.0)
		var begin := box.position+Vector2(s*shift,s*(.25+i*.23))
		draw_line(begin,Vector2(minf(begin.x+s*.17,box.end.x),begin.y),Color(1,1,1,.22),1.4,true)
	for direction in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
		if int(tile(cell+direction).get("t",-1))==2: continue
		var offset := Vector2(direction.y,direction.x)*(-1 if flip else 1)
		var mid := box.get_center()+offset*(s/2-1.5)
		var tangent := Vector2(-offset.y,offset.x)*(s/2)
		draw_line(mid-tangent,mid+tangent,Color(.82,.95,1,.65),3,true)

func _moving_at(cell: Vector2i) -> bool:
	return not piece_motion.is_empty() and piece_motion.to==cell

func signal_color(kind: String, alpha: float=1.0) -> Color:
	var palette = {"move":"009fca","attack":"e69f00","fire":"e69f00","barrage":"e69f00","scan":"0072b2"} if colorblind else {"move":"388c3a","attack":"e69f00","fire":"23a5e6","barrage":"e69f00","scan":"975ee0"}
	return Color(Color(palette.get(kind,"56b4e9")),alpha)
