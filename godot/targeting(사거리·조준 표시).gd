extends Control
## Visual targeting only: every legal cell comes from the server's /moves response.
## Clamping never changes a clicked cell or reveals concealed terrain/pieces.
var board: Control
var ground_decal: Dictionary = {}
var decal_remaining := 0.0
var stage_age := 0.0
var hover_age := 1.0
var press_age := 1.0
var motion_time := 0.0
var motion_key := ""
var last_hover := Vector2i(-1,-1)
var last_valid := false
var press_echo: Dictionary = {}
var echo_age := 1.0
const DIRECTIONS = [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	board.tapped.connect(_on_target_pressed)

func _process(delta: float) -> void:
	advance_motion(delta)
	decal_remaining = maxf(0.0,decal_remaining-delta)
	if decal_remaining<=0.0: ground_decal.clear()
	position = board.geometry().position
	size = board.geometry().size
	queue_redraw()

func animated() -> bool:
	return board.effects and not board.fx.reduced

func advance_motion(delta: float) -> void:
	echo_age += delta
	if echo_age>=.22 or not animated(): press_echo.clear()
	var key := "%s:%s:%s:%s" % [board.view.get("room",""),board.selected,board.mode,board.flip] if active() else ""
	if key!=motion_key:
		motion_key = key
		motion_time = 0.0
		stage_age = 0.0
		hover_age = 0.0
		press_age = 1.0
		last_hover = Vector2i(-1,-1)
	if key.is_empty():
		stage_age = 0.0
		return
	var valid: bool = aim_state(board.hover).valid if board.hover.x>=0 else false
	if board.hover!=last_hover or valid!=last_valid:
		hover_age = 0.0
		last_hover = board.hover
		last_valid = valid
	if not animated():
		stage_age = 1.0
		hover_age = 1.0
		press_age = 1.0
		return
	stage_age += delta
	hover_age += delta
	press_age += delta
	motion_time += delta

func _on_target_pressed(cell: Vector2i) -> void:
	if not active() or not animated() or cell==board.selected: return
	press_age = 0.0
	var state := aim_state(cell)
	var cursor: Vector2i = state.cell
	if cursor.x<0: return
	var geometry := scan_cursor(cursor) if board.mode=="scan" else {"center":at(cursor),"radius":size.x/12.0*.4}
	press_echo = {"center":geometry.center,"radius":geometry.radius,"color":ink(state.valid),"size":size,"flip":board.flip}
	echo_age = 0.0

func entry_amount() -> float:
	return 1.0-pow(1.0-clampf(stage_age/.24,0.0,1.0),3.0) if animated() else 1.0

func breathing() -> float:
	return .92+.08*sin(motion_time*TAU/3.2) if animated() else 1.0

func response_amount() -> float:
	# Ease to rest with zero end velocity instead of stopping a linear ramp abruptly.
	return pow(maxf(0.0,1.0-hover_age/.20),2.0)*.65+pow(maxf(0.0,1.0-press_age/.22),2.0) if animated() else 0.0

func range_ring(point: Vector2, radius: float, color: Color) -> void:
	var amount := entry_amount()
	var end := -PI*.5+TAU*maxf(.001,amount)
	var shown_radius := radius*lerpf(.97,1.0,amount)
	draw_arc(point,shown_radius,-PI*.5,end,128,Color(.04,.06,.08,.55*amount),4.0,true)
	draw_arc(point,shown_radius,-PI*.5,end,128,Color(color,color.a*amount*breathing()),2.0,true)

func clear_decal() -> void:
	ground_decal.clear()
	decal_remaining = 0.0
	press_echo.clear()

func prepare_barrage(cells: Array) -> void:
	ground_decal = cell_set(cells)
	decal_remaining = .18

func at(cell: Vector2i) -> Vector2:
	return board.center(cell)-board.geometry().position

func cell_set(cells: Array) -> Dictionary:
	var result := {}
	for rc in cells: result[Vector2i(int(rc[0]),int(rc[1]))] = true
	return result

func active() -> bool:
	return board.selected.x>=0 and board.mode in ["scan","barrage","fire"] and (not board.targets.is_empty() or not board.ranges.is_empty())

func legal_area() -> Dictionary:
	return cell_set(board.ranges if board.mode=="fire" else board.targets)

func aim_state(raw: Vector2i) -> Dictionary:
	var area := legal_area()
	var cursor := raw
	if not area.has(raw) and not area.is_empty():
		var best := INF
		for cell: Vector2i in area:
			# Rook previews cannot jump from a blocked direction to another ray.
			if board.mode=="barrage":
				var delta: Vector2i = raw-board.selected
				var direction := Vector2i(signi(delta.x),0) if absi(delta.x)>=absi(delta.y) else Vector2i(0,signi(delta.y))
				var step: Vector2i = cell-board.selected
				if step.x*direction.y!=step.y*direction.x or step.x*direction.x+step.y*direction.y<=0: continue
			var distance := Vector2(cell).distance_squared_to(Vector2(raw))
			if distance<best:
				best = distance
				cursor = cell
		if best==INF: cursor = Vector2i(-1,-1)
	return {"cell":cursor,"valid":board.contains(board.targets,raw),"clamped":cursor!=raw}

func scan_area(anchor: Vector2i) -> Dictionary:
	var result := {}
	for dr in range(2):
		for dc in range(2):
			var cell := anchor+Vector2i(dr,dc)
			if cell.x>=0 and cell.y>=0 and cell.x<12 and cell.y<12: result[cell] = true
	return result

func scan_cursor(anchor: Vector2i) -> Dictionary:
	var footprint := scan_area(anchor)
	var midpoint := Vector2.ZERO
	for cell: Vector2i in footprint: midpoint += at(cell)
	midpoint /= maxf(1.0,footprint.size())
	var radius := 1.44 if footprint.size()==4 else (1.14 if footprint.size()==2 else .72)
	return {"cells":footprint,"center":midpoint,"radius":radius*size.x/12.0}

func ink(valid: bool=true) -> Color:
	if not valid: return Color("#ed9759") if board.colorblind else Color("#f47e83")
	# Brighter strokes stay readable over both wood and fog.
	return {"scan":Color("#75caff") if board.colorblind else Color("#c3a1fa"),"fire":Color("#f2c572") if board.colorblind else Color("#72c9ed"),"barrage":Color("#f2c572")}.get(board.mode,Color.WHITE)

func fill_cells(cells: Dictionary, color: Color) -> void:
	var s := size.x/12.0
	for cell: Vector2i in cells: draw_rect(Rect2(at(cell)-Vector2.ONE*s*.5,Vector2.ONE*s),color)

func contour(cells: Dictionary, color: Color, width: float) -> void:
	var s := size.x/12.0
	for cell: Vector2i in cells:
		for direction: Vector2i in DIRECTIONS:
			if cells.has(cell+direction): continue
			var normal := Vector2(direction.y,direction.x)*(-1.0 if board.flip else 1.0)
			var mid := at(cell)+normal*s*.5
			var tangent := Vector2(-normal.y,normal.x)*s*.5
			draw_line(mid-tangent,mid+tangent,Color(.04,.06,.08,.7),width+2.0,true)
			draw_line(mid-tangent,mid+tangent,color,width,true)

func ring(point: Vector2, radius: float, color: Color, width: float=2.0) -> void:
	draw_arc(point,radius,0,TAU,96,Color(.04,.06,.08,.65),width+2.0,true)
	draw_arc(point,radius,0,TAU,96,color,width,true)

func reticle_turn_angle(seconds: float) -> float:
	# One full clockwise turn in twelve seconds, then one counterclockwise turn.
	# Cosine gives zero angular velocity at both reversals and at the loop seam.
	return PI*(1.0-cos(TAU*fposmod(seconds,24.0)/24.0))

func reticle(point: Vector2, radius: float, color: Color, valid: bool, reactive: bool=true) -> void:
	var response := response_amount() if reactive else 0.0
	color.a *= entry_amount()
	radius *= 1.0+.065*response
	color = color.lerp(Color(1,1,1,color.a),minf(.25,response*.22)) if valid else color
	var turn := reticle_turn_angle(motion_time) if reactive and animated() and board.mode in ["scan","fire"] else 0.0
	for i in range(4):
		var angle := PI*.25+i*PI*.5+turn
		draw_arc(point,radius,angle-.22,angle+.22,12,Color(color,color.a*(breathing() if reactive else 1.0)),2.0+response*.6 if reactive else 1.3,true)
	var d := radius*.25
	if valid:
		draw_line(point-Vector2(d,0),point+Vector2(d,0),color,1.5,true)
		draw_line(point-Vector2(0,d),point+Vector2(0,d),color,1.5,true)
	else:
		draw_line(point-Vector2(d,d),point+Vector2(d,d),color,2.5,true)
		draw_line(point-Vector2(d,-d),point+Vector2(d,-d),color,2.5,true)

func arrow(from: Vector2, to: Vector2, color: Color, s: float, focused: bool=false) -> void:
	var direction := (to-from).normalized()
	var start := from+direction*s*.55
	var end := to+direction*s*.35
	var side := Vector2(-direction.y,direction.x)
	var amount := entry_amount()
	end = start.lerp(end,maxf(.35,amount))
	var neck := end-direction*minf(s*.32,start.distance_to(end)*.6)
	var width := s*.055
	# One simple silhouette: no bevels, spine, chevrons or decorative stop marks.
	var polygon := PackedVector2Array([start+side*width,neck+side*width,neck+side*s*.19,end,neck-side*s*.19,neck-side*width,start-side*width])
	var alpha := amount*breathing()
	var response := response_amount() if focused else 0.0
	draw_colored_polygon(polygon,Color(color,(.22 if focused else .10)*alpha+response*.035))
	var outline := polygon.duplicate()
	outline.append(polygon[0])
	draw_polyline(outline,Color(.04,.06,.08,.45*alpha),3.5,true)
	draw_polyline(outline,Color(color,(.95 if focused else .45)*alpha),1.7+response*.4,true)

func scan_groups(cells: Dictionary) -> Array:
	var remaining := cells.duplicate()
	var groups: Array = []
	while not remaining.is_empty():
		var group := {}
		var pending: Array = [remaining.keys()[0]]
		remaining.erase(pending[0])
		while not pending.is_empty():
			var cell: Vector2i = pending.pop_back()
			group[cell] = true
			for direction: Vector2i in DIRECTIONS:
				var neighbor := cell+direction
				if remaining.has(neighbor):
					remaining.erase(neighbor)
					pending.append(neighbor)
		groups.append(group)
	return groups

func barrage_lane(raw: Vector2i) -> Dictionary:
	var lane := {}
	if board.mode!="barrage" or raw.x<0 or raw==board.selected: return lane
	var cursor: Vector2i = aim_state(raw).cell
	if cursor.x<0: return lane
	var delta: Vector2i = cursor-board.selected
	var direction := Vector2i(signi(delta.x),signi(delta.y))
	var area := legal_area()
	for distance in range(1,12):
		var cell: Vector2i = board.selected+direction*distance
		if not area.has(cell): break
		lane[cell] = true
	return lane

func friendly_in_lane(raw: Vector2i) -> Array[Vector2i]:
	var friends: Array[Vector2i] = []
	for cell: Vector2i in barrage_lane(raw):
		var piece: Variant = board.tile(cell).get("p")
		# Only identities already supplied in the public view; no hidden lookup.
		if piece is Dictionary and piece.get("o")==board.view.get("yourColor"):
			friends.append(cell)
	return friends

const SURVEILLANCE_PERIOD := 12.0
const SURVEILLANCE_OPACITY := .30
func surveillance_angle(seconds: float) -> float:
	return seconds*TAU/SURVEILLANCE_PERIOD

func surveillance(cells: Dictionary, color: Color, s: float) -> void:
	# Surveillance uses the radar alone; the authorized cells still clip its light.
	var animate: bool = board.effects and not board.fx.reduced
	var phase: float = surveillance_angle(board.clock) if animate else -.65
	for group: Dictionary in scan_groups(cells):
		var first: Vector2i = group.keys()[0]
		var bounds := Rect2(at(first)-Vector2.ONE*s*.5,Vector2.ONE*s)
		for cell: Vector2i in group: bounds = bounds.merge(Rect2(at(cell)-Vector2.ONE*s*.5,Vector2.ONE*s))
		var midpoint := bounds.get_center()
		var radius := minf(bounds.size.x,bounds.size.y)*.41
		# Clip every radar segment to the actual scanned cells, even for joined L shapes.
		var rim: Array = []
		for i in range(80):
			var angle := i*TAU/80.0
			var a := midpoint+Vector2.from_angle(angle)*radius
			var b := midpoint+Vector2.from_angle(angle+TAU/80.0)*radius
			if not group.has(board.cell_at(a+board.geometry().position)) or not group.has(board.cell_at(b+board.geometry().position)): continue
			var tail := fposmod(phase-angle,TAU)
			var alpha := lerpf(1.0,.72,tail/1.2) if tail<1.2 else .72
			draw_line(a,b,Color(.04,.05,.07,.72*SURVEILLANCE_OPACITY),4.2,true)
			rim.append([a,b,alpha])
		# Finish all dark under-strokes before the bright rim to avoid dotted joins.
		for segment in rim: draw_line(segment[0],segment[1],Color(color,segment[2]*SURVEILLANCE_OPACITY),2.2,true)
		# Sweep trail stays inside each authorized cell; it never reveals fog content.
		for j in range(12):
			var wedge := PackedVector2Array([midpoint,midpoint+Vector2.from_angle(phase-j*.075)*radius,midpoint+Vector2.from_angle(phase-(j+1)*.075)*radius])
			for cell: Vector2i in group:
				var top := at(cell)-Vector2.ONE*s*.5
				var tile_polygon := PackedVector2Array([top,top+Vector2(s,0),top+Vector2(s,s),top+Vector2(0,s)])
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(wedge,tile_polygon):
					draw_colored_polygon(clipped,Color(color,.24*(1.0-j/12.0)*SURVEILLANCE_OPACITY))
		# Four moving rim accents make the slow rotation readable between turns.
		for quarter in range(4):
			for segment in range(8):
				var angle := phase+quarter*TAU/4.0+segment*.035
				var a := midpoint+Vector2.from_angle(angle)*radius*.90
				var b := midpoint+Vector2.from_angle(angle+.035)*radius*.90
				if group.has(board.cell_at(a+board.geometry().position)) and group.has(board.cell_at(b+board.geometry().position)):
					draw_line(a,b,Color(color,.92*SURVEILLANCE_OPACITY),2.4,true)
		if group.has(board.cell_at(midpoint+board.geometry().position)):
			draw_circle(midpoint,2.2,Color(color,.8*SURVEILLANCE_OPACITY))

func _draw() -> void:
	if not is_instance_valid(board) or size.x<=0: return
	var s := size.x/12.0
	if not press_echo.is_empty() and press_echo.size==size and press_echo.flip==board.flip:
		var progress := clampf(echo_age/.22,0.0,1.0)
		var eased := 1.0-pow(1.0-progress,3.0)
		draw_arc(press_echo.center,press_echo.radius*(1.0+.08*eased),0,TAU,96,Color(press_echo.color,pow(1.0-progress,2.0)*.65),1.8,true)
	if not ground_decal.is_empty():
		var gold := Color("#f2c572")
		fill_cells(ground_decal,Color(gold,.18))
		contour(ground_decal,gold,2.5)
	# Persisted scans use quiet radar sweeps, without square frames.
	var zones: Array = board.view.get("scanZones",[]) if board.view.get("scanZones") is Array else []
	if not zones.is_empty():
		for zone: Dictionary in zones:
			if int(zone.get("remaining",0))<=0: continue
			var enemy: bool = board.view.get("yourColor") in ["W","B"] and zone.get("owner")!=board.view.get("yourColor")
			var scan_ink := Color("#ffc570") if enemy else (Color("#75caff") if board.colorblind else Color("#c3a1fa"))
			surveillance(cell_set(zone.get("cells",[])),scan_ink,s)
	else:
		var scanned := cell_set(board.view.get("scanTiles",[]))
		# Older saved replays have only public tile footprints.
		if not scanned.is_empty(): surveillance(scanned,Color("#c3a1fa"),s)
	if not active(): return
	var area := legal_area()
	var accent := ink()
	var enter := entry_amount()
	for r in range(12):
		for c in range(12):
			var cell := Vector2i(r,c)
			if not area.has(cell) and cell!=board.selected:
				draw_rect(Rect2(at(cell)-Vector2.ONE*s*.5,Vector2.ONE*s),Color(.02,.03,.05,.32*enter))
	fill_cells(area,Color(accent,.065*enter))
	if board.mode=="fire":
		# Radius 5 is the unchanged bishop rule; forest holes remain excluded by /moves.
		range_ring(at(board.selected),s*5.0,Color(accent,.85))
		for rc in board.targets:
			var enemy := Vector2i(rc[0],rc[1])
			if enemy!=board.hover: reticle(at(enemy),s*.34,Color(accent,.38),true,false)
	elif board.mode=="scan":
		range_ring(at(board.selected),s*6.0,Color(accent,.85))
	else:
		contour(area,Color(accent,.26*enter),1.2)
		if board.mode=="barrage":
			var focus: Vector2i = aim_state(board.hover).cell if board.hover.x>=0 and board.hover!=board.selected else Vector2i(-1,-1)
			for direction: Vector2i in DIRECTIONS:
				if focus.x>=0:
					var delta: Vector2i = focus-board.selected
					if delta.x*direction.y==delta.y*direction.x and delta.x*direction.x+delta.y*direction.y>0: continue
				var last: Vector2i = board.selected
				for distance in range(1,12):
					var cell: Vector2i = board.selected+direction*distance
					if not area.has(cell): break
					last = cell
				if last!=board.selected: arrow(at(board.selected),at(last),Color(accent,.65),s)
	if board.hover.x<0 or board.hover==board.selected: return
	var state := aim_state(board.hover)
	var color := ink(state.valid)
	var cursor: Vector2i = state.cell
	if cursor.x<0:
		if board.mode!="barrage": reticle(at(board.hover),s*.35,color,false)
		return
	if board.mode=="scan":
		var aoe := scan_cursor(cursor)
		var midpoint: Vector2 = aoe.center
		var radius: float = aoe.radius
		# Four tiles share one circular reticle; no individual tile fills or frames.
		draw_circle(midpoint,radius,Color(color,.055*enter*breathing()))
		ring(midpoint,radius,Color(color,.65*enter*breathing()),1.5)
		reticle(midpoint,radius*.92,Color(color,enter),state.valid)
	elif board.mode=="barrage":
		var delta: Vector2i = cursor-board.selected
		var direction := Vector2i(signi(delta.x),signi(delta.y))
		var lane := {}
		var last: Vector2i = board.selected
		for distance in range(1,12):
			var cell: Vector2i = board.selected+direction*distance
			if not area.has(cell): break
			lane[cell] = true
			last = cell
		fill_cells(lane,Color(color,(.10+response_amount()*.025)*enter))
		contour(lane,Color(color,.55*enter),1.5)
		arrow(at(board.selected),at(last),color,s,true)
		for friend: Vector2i in friendly_in_lane(board.hover):
			# A warning, not an invalid-state color: friendly fire remains legal.
			var warning := Color("#ffd27d")
			ring(at(friend),s*.40,Color(warning,.9),1.6)
			# Triangle at the lower corner distinguishes fire risk from the round exposure badge.
			var mark := at(friend)+Vector2(s*.30,s*.27)
			var radius := maxf(5.0,s*.13)
			var triangle := PackedVector2Array([mark+Vector2(0,-radius),mark+Vector2(radius,radius*.8),mark+Vector2(-radius,radius*.8)])
			draw_colored_polygon(triangle,warning)
			triangle.append(triangle[0])
			draw_polyline(triangle,Color("#272b2b"),1.3,true)
		if not state.valid: reticle(at(cursor),s*.30,color,false)
	else:
		var start := at(board.selected)
		var end := at(cursor)
		draw_line(start+(end-start).normalized()*s*.5,end,color,1.5,true)
		reticle(end,s*.42,color,state.valid)
	if state.clamped and board.mode!="barrage":
		draw_dashed_line(at(cursor),at(board.hover),Color(color,.65),1.5,s*.15,true)
		reticle(at(board.hover),s*.30,color,false)

