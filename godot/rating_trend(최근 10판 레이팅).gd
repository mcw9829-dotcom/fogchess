extends Control
## Uses only persisted ratings. One point is one settled rated match; no interpolated history.
var rows: Array = []
var selected := -1
var points := PackedVector2Array()
const GOLD = Color("#e5bf79")
const BLUE = Color("#9cc6e6")
const INK = Color("#f3eee4")
const MUTED = Color("#b8c3c6")

func _ready() -> void:
	custom_minimum_size = Vector2(0,166)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	accessibility_name = "최근 레이팅 대국 그래프. 왼쪽 오른쪽 방향키로 각 대국 확인"
	mouse_exited.connect(func(): selected = rows.size()-1; queue_redraw())
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func set_rows(newest_first: Array) -> void:
	rows = []
	for row in newest_first:
		if row is Dictionary and row.get("rating_after") != null and row.get("delta") != null:
			rows.append(row.duplicate())
		if rows.size() == 10: break
	rows.reverse()
	selected = rows.size()-1
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if rows.is_empty(): return
	if event is InputEventMouseMotion or event is InputEventScreenTouch:
		if event is InputEventScreenTouch and not event.pressed: return
		var nearest := 0
		var distance := INF
		for i in range(points.size()):
			var d = absf(points[i].x-event.position.x)
			if d < distance: distance = d; nearest = i
		selected = nearest
		queue_redraw()
	elif event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT,KEY_RIGHT]:
		selected = clampi(selected + (-1 if event.keycode == KEY_LEFT else 1),0,rows.size()-1)
		queue_redraw()
		accept_event()

func text_at(value: String, at: Vector2, width: float, font_size: int, color: Color, align: HorizontalAlignment=HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(get_theme_default_font(),at,value,align,width,font_size,color)

func _draw() -> void:
	if rows.is_empty(): return
	var low := float(rows[0].rating_after)
	var high := low
	for row in rows:
		low = minf(low,float(row.rating_after))
		high = maxf(high,float(row.rating_after))
	var pad := maxf(10,(high-low)*.16)
	low = floor((low-pad)/10.0)*10
	high = ceil((high+pad)/10.0)*10
	var plot := Rect2(42,36,maxf(20,size.x-56),78)
	points = PackedVector2Array()
	for i in range(3):
		var y = plot.position.y + i*plot.size.y/2
		var rating = high-i*(high-low)/2
		draw_line(Vector2(plot.position.x,y),Vector2(plot.end.x,y),Color(1,1,1,.10),1)
		text_at(str(int(rating)),Vector2(0,y+4),35,11,MUTED,HORIZONTAL_ALIGNMENT_RIGHT)
	for i in range(rows.size()):
		var x = plot.position.x+plot.size.x*(float(i)/(rows.size()-1) if rows.size()>1 else .5)
		points.append(Vector2(x,plot.end.y-(float(rows[i].rating_after)-low)/(high-low)*plot.size.y))
	if points.size()>1:
		var fill = points.duplicate()
		fill.append(Vector2(points[-1].x,plot.end.y))
		fill.append(Vector2(points[0].x,plot.end.y))
		draw_colored_polygon(fill,Color(GOLD,.07))
		draw_polyline(points,GOLD,2,true)
	for i in range(points.size()):
		draw_circle(points[i],3,GOLD,true,-1,true)
		text_at(str(i+1),Vector2(points[i].x-8,plot.end.y+18),16,10,MUTED,HORIZONTAL_ALIGNMENT_CENTER)
	var before = int(rows[0].rating_after)-int(rows[0].delta)
	var after = int(rows[-1].rating_after)
	text_at("최근 %d판 · %+d" % [rows.size(),after-before],Vector2(0,17),size.x,14,INK)
	if selected>=0 and selected<rows.size():
		var row: Dictionary = rows[selected]
		var p := points[selected]
		draw_line(Vector2(p.x,plot.position.y),Vector2(p.x,plot.end.y),Color(BLUE,.25),1)
		draw_circle(p,6,Color("#192329"),true,-1,true)
		draw_arc(p,6,0,TAU,32,BLUE,1.5,true)
		draw_circle(p,2.5,BLUE,true,-1,true)
		var outcome: String = {"win":"승","loss":"패","draw":"무"}.get(row.get("result",""),"대국")
		var caption = "%d번째 · %s   %d점 (%+d)" % [selected+1,outcome,int(row.rating_after),int(row.delta)]
		text_at(caption,Vector2(0,158),size.x,12,INK,HORIZONTAL_ALIGNMENT_CENTER)
		accessibility_description = caption
	if has_focus(): draw_style_box(get_theme_stylebox("focus","Button"),Rect2(Vector2.ZERO,size))
