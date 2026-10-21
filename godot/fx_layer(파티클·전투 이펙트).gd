extends Control
## Board-space effects with confirmed-action timing and reduced-motion support.
const SPARK = [Color("fff7d6"),Color("ffe08a"),Color("ffc24d"),Color.WHITE]
const DEBRIS = [Color("3a2e22"),Color("6b5238"),Color("8a6d4a"),Color("2b2521"),Color("b08a55")]
const CONFETTI = [Color("e6c96a"),Color("f3ecdf"),Color("c69a5e"),Color("d63a1a"),Color("3d7bd6"),Color.WHITE]
var parts: Array = []
var timers: Array = []
var time := 0.0
var shake := 0.0
var slow := 0.0
var shake_offset := Vector2.ZERO
var reduced := false
var colorblind := false
var preview := false
var cols := 12
var flipped := false
var glow: Node2D
var gradients: Dictionary = {}
var vignette_texture: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	# Keep procedural textures alive and upload them before the first draw.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,.32,1])
	gradient.colors = PackedColorArray([Color(0,0,0,0),Color(0,0,0,0),Color.BLACK])
	vignette_texture = GradientTexture2D.new()
	vignette_texture.gradient = gradient
	vignette_texture.fill = GradientTexture2D.FILL_RADIAL
	vignette_texture.fill_from = Vector2(.5,.5)
	vignette_texture.fill_to = Vector2(1.28,.5)
	for color in [Color(1,.784,.353,.95),Color(1,.941,.706,.95),Color(1,.902,.627,.98),Color(1,.863,.47)]: radial(color,Color(1,.47,.118,0),true)
	radial(Color(.71,.604,.416,.6),Color(.71,.604,.416,0))
	radial(Color(.306,.29,.275,.55),Color(.235,.227,.22,0))
	radial(Color(1,.588,.196,.95),Color(1,.235,.039,0))
	glow = Node2D.new()
	var material := CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = material
	add_child(glow)
	glow.draw.connect(func(): render(glow,true))
	if OS.has_feature("web"):
		reduced = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))

func cell_width() -> float: return size.x / cols
func point(rc: Array) -> Vector2:
	var p := Vector2(float(rc[1]),float(rc[0]))
	if flipped: p = Vector2.ONE*(cols-1)-p
	return (p+Vector2.ONE*.5)*cell_width()

func clear() -> void:
	parts.clear()
	timers.clear()
	shake = 0
	slow = 0
	shake_offset = Vector2.ZERO
	queue_redraw()
	if is_instance_valid(glow): glow.queue_redraw()

func add(p: Dictionary) -> void:
	if parts.size()>=600: parts.pop_front()
	p.merge({"age":0.0,"v":Vector2.ZERO,"life":.5,"size":2.0,"rot":0.0,"vr":0.0,"grav":0.0,"drag":0.0,"color":Color.WHITE},false)
	if colorblind:
		var tint: Color = p.color
		if tint.s>.2:
			p.color = Color(Color("#0072b2") if tint.b>tint.r else Color("#e69f00"),tint.a)
	parts.append(p)
func after(delay: float, action: Callable) -> void: timers.append({"at":time+delay,"action":action})
func shake_by(value: float) -> void:
	if not reduced: shake = maxf(shake,value)
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		if not parts.is_empty() or not timers.is_empty(): clear()
		return
	var real := minf(delta,.05)
	var dt := real*(.35 if slow>0 else 1.0)
	slow = maxf(0,slow-real)
	time += dt
	var due: Array = []
	for timer in timers:
		if timer.at<=time: due.append(timer)
	for timer in due:
		timers.erase(timer)
		timer.action.call()
	for p in parts:
		p.age += dt
		p.pos += p.v*dt
		p.v.y += p.grav*dt
		p.v *= maxf(0,1-p.drag*dt)
		p.rot += p.vr*dt
	parts = parts.filter(func(p): return p.age<p.life)
	shake_offset = Vector2(randf_range(-1,1),randf_range(-1,1))*shake*7
	shake = maxf(0,shake-real*2.4)
	queue_redraw()
	if is_instance_valid(glow): glow.queue_redraw()

func radial(inner: Color, outer: Color, flash: bool=false) -> Texture2D:
	var key := str(inner)+str(outer)+str(flash)
	if not gradients.has(key):
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0,.35,1] if flash else [0,1])
		gradient.colors = PackedColorArray([Color.WHITE,inner,outer] if flash else [inner,outer])
		var texture := GradientTexture2D.new()
		texture.width = 128
		texture.height = 128
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(.5,.5)
		texture.fill_to = Vector2(1,.5)
		texture.gradient = gradient
		gradients[key] = texture
	return gradients[key]

func _draw() -> void:
	if preview:
		draw_set_transform(shake_offset)
		for r in range(cols):
			for c in range(cols): draw_rect(Rect2(Vector2(c,r)*cell_width(),Vector2.ONE*cell_width()),Color("f0d9b5") if (r+c)%2==0 else Color("b58863"))
	render(self,false)

func render(canvas: CanvasItem, additive: bool) -> void:
	for p in parts:
		if bool(p.get("add",false))!=additive: continue
		var k: float = clampf(p.age/p.life,0,1)
		var alpha: float = float(p.get("a",1))*(1.0 if p.get("hold",false) else 1-k)
		if p.get("fade_in",false): alpha *= minf(1,k*4)
		var color: Color = p.color
		color.a *= alpha
		var pos: Vector2 = p.pos+shake_offset
		canvas.draw_set_transform(Vector2.ZERO)
		match p.kind:
			"spark": canvas.draw_line(pos,pos-p.v*.025,color,p.size,true)
			"dot": canvas.draw_circle(pos,p.size,color)
			"smoke", "flash":
				var radius: float = p.size*(.35+k*1.1) if p.kind=="smoke" else lerpf(p.r0,p.r1,1-pow(1-k,2))
				var edge: Color = p.get("edge",Color(p.color,0))
				canvas.draw_texture_rect(radial(p.color,edge,p.kind=="flash"),Rect2(pos-Vector2.ONE*radius,Vector2.ONE*radius*2),false,Color(1,1,1,alpha))
			"ring": canvas.draw_arc(pos,lerpf(p.r0,p.r1,1-pow(1-k,3)),0,TAU,64,color,maxf(1,p.size*(1-k)),true)
			"debris", "confetti":
				if p.kind=="confetti": pos.x += sin(p.age*p.freq)*p.amp
				canvas.draw_set_transform(pos,p.rot)
				canvas.draw_rect(Rect2(Vector2(-p.size/2,-p.size/(4 if p.kind=="confetti" else 3)),Vector2(p.size,p.size*(.5 if p.kind=="confetti" else .66))),color)
			"tracer":
				var h := minf(1,k*1.15)
				var begin: Vector2 = p.pos.lerp(p.target,maxf(0,h-p.length))+shake_offset
				var end: Vector2 = p.pos.lerp(p.target,h)+shake_offset
				canvas.draw_line(begin,end,Color(color,.12*alpha),p.size+12,true)
				canvas.draw_line(begin,end,color,p.size,true)
			"sweep":
				var angle: float = p.angle+k*1.5*TAU
				for i in range(7):
					var polygon := PackedVector2Array([pos])
					for j in range(6): polygon.append(pos+Vector2.from_angle(angle-(i+1)*.2+j*.04)*p.radius)
					canvas.draw_colored_polygon(polygon,Color(.22,.53,.92,.38*(1-i/7.0)*alpha))
				canvas.draw_arc(pos,p.radius,0,TAU,64,Color(.22,.53,.92,.85*alpha),1.5,true)
			"slash":
				var extent: float = p.size*(.5+.5*k)
				canvas.draw_line(pos+Vector2(-extent,extent*.6),pos+Vector2(extent,-extent*.6),color,3*(1-k)+1,true)
				canvas.draw_line(pos+Vector2(-extent,-extent*.6),pos+Vector2(extent,extent*.6),Color(color,.5*alpha),2,true)
			"scan_frame":
				var extent: float = p.size
				for direction in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
					var corner: Vector2 = pos+direction*extent
					canvas.draw_line(corner,corner-Vector2(direction.x*extent*.45,0),color,2,true)
					canvas.draw_line(corner,corner-Vector2(0,direction.y*extent*.45),color,2,true)
			"vignette":
				canvas.draw_texture_rect(vignette_texture,Rect2(shake_offset,size),false,Color(1,1,1,color.a))
	canvas.draw_set_transform(Vector2.ZERO)

func ring(pos: Vector2,r0: float,r1: float,life: float,color: Color,width: float=4) -> void:
	add({"kind":"ring","pos":pos,"r0":r0,"r1":r1,"life":life,"color":color,"size":width})
func flash(pos: Vector2,radius: float,life: float,color: Color=Color(1,.784,.353,.95)) -> void:
	add({"kind":"flash","pos":pos,"r0":radius*.2,"r1":radius,"life":life,"color":color,"edge":Color(1,.47,.118,0),"add":true})
func tracer(from: Vector2,to: Vector2,life: float,color: Color,width: float=2.5,length: float=.35) -> void:
	add({"kind":"tracer","pos":from,"target":to,"life":life,"color":color,"size":width,"length":length,"hold":true,"add":true})
func vignette(alpha: float,life: float) -> void: add({"kind":"vignette","pos":Vector2.ZERO,"color":Color(0,0,0,alpha),"life":life})
func emit_particles(kind: String,pos: Vector2,count: int,speed: float=0,big: bool=false) -> void:
	var cw := cell_width()
	if reduced: count = {"spark":int(ceil(count/4.0)),"dust":2,"smoke":3,"fireball":4,"debris":0}.get(kind,count)
	for i in range(count):
		var a := randf()*TAU
		var p := {"kind":kind,"pos":pos}
		match kind:
			"spark":
				var s := randf_range(speed*.35,speed)
				p.merge({"v":Vector2(cos(a)*s,sin(a)*s-speed*.15),"grav":cw*9,"drag":1.8,"life":randf_range(.3,.6),"size":randf_range(1,2.2),"color":SPARK.pick_random(),"add":true})
			"dust":
				var s := randf_range(cw*.5,cw*1.6)
				p.merge({"v":Vector2(cos(a)*s,sin(a)*s*.5-cw*.4),"drag":2.5,"life":randf_range(.45,.8),"size":randf_range(cw*.28,cw*.45),"color":Color(.71,.604,.416,.6),"kind":"smoke"},true)
			"smoke":
				var s := randf_range(cw*.3,cw*(2.2 if big else 1.2))
				p.pos += Vector2(randf_range(-4,4),randf_range(-4,4))
				p.merge({"v":Vector2(cos(a)*s*.5,-absf(sin(a))*s-cw*(1.2 if big else .6)),"drag":.9,"life":randf_range(1.2,2) if big else randf_range(.8,1.4),"size":randf_range(cw*.4,cw*(.9 if big else .6)),"color":Color(.306,.29,.275,.55),"edge":Color(.235,.227,.22,0)})
			"fireball":
				var s := randf_range(cw*1.5,cw*5)
				p.merge({"v":Vector2(cos(a)*s,sin(a)*s-cw*1.5),"drag":2.2,"life":randf_range(.35,.6),"size":randf_range(cw*.45,cw*.75),"color":Color(1,.588,.196,.95),"edge":Color(1,.235,.039,0),"kind":"smoke","add":true},true)
			"debris":
				a = -randf_range(.15,PI-.15)
				var s := randf_range(speed*.4,speed)
				p.merge({"v":Vector2(cos(a)*s*randf_range(.6,1.4),sin(a)*s),"grav":cw*16,"drag":.4,"vr":randf_range(-12,12),"rot":randf()*TAU,"life":randf_range(.6,1),"size":randf_range(2.5,5.5),"color":DEBRIS.pick_random()})
		add(p)

func impact(pos: Vector2,scale: float=1) -> void:
	var cw := cell_width()
	flash(pos,cw*1.2*scale,.18)
	ring(pos,cw*.2,cw*1.3*scale,.45,Color(1,.863,.55,.9),3)
	emit_particles("spark",pos,roundi(22*scale),cw*9*scale)
	emit_particles("dust",pos,roundi(8*scale))
	emit_particles("debris",pos,roundi(8*scale),cw*7*scale)

func play(data: Dictionary) -> void:
	if float(data.get("delay",0))>0:
		var delayed := data.duplicate(true)
		delayed.erase("delay")
		after(float(data.delay),func(): play(delayed))
		return
	var cw := cell_width()
	var cells: Array = data.get("cells",[]).map(func(rc): return point(rc))
	var source: Variant = point(data.from) if data.get("from") is Array and data.from.size()==2 else null
	var kind: String = data.get("type","move")
	if kind in ["victory","defeat","drawend"]: ending(kind); return
	if cells.is_empty(): return
	match kind:
		"move":
			var pos: Vector2 = cells.back()
			ring(pos,cw*.15,cw*.43,.28,Color(.88,.78,.53,.65),2)
			if not reduced: emit_particles("dust",pos,3)
		"capture":
			for pos in cells:
				flash(pos,cw*.70,.12)
				add({"kind":"slash","pos":pos,"life":.23,"size":cw*.52,"color":Color("fff1c5"),"add":true})
				emit_particles("spark",pos,10,cw*5)
				ring(pos,cw*.2,cw*1.05,.45,Color(1,.863,.55,.9),3)
			shake_by(.15)
		"fire":
			var hit := func(): impact(cells[0],.95); emit_particles("smoke",cells[0],8); shake_by(.25)
			if source!=null:
				flash(source,cw*.7,.14,Color(1,.941,.706,.95))
				ring(source,cw*.12,cw*.4,.12,Color("ffe9a0"),2)
				after(.07,func(): tracer(source,cells[0],.10,Color("ffe9a0"),2.5,.3))
				after(.17,hit)
			else: hit.call()
		"barrage":
			if source!=null:
				flash(source,cw*1.1,.18,Color(1,.902,.627,.98))
				emit_particles("smoke",source,6)
				emit_particles("dust",source,8)
			shake_by(.45)
			for i in range(cells.size()):
				var pos: Vector2 = cells[i]
				var previous: Vector2 = cells[i-1] if i>0 else (source if source!=null else pos)
				var last: bool = i==cells.size()-1
				after(.09*i+(.05 if source!=null else 0),func():
					if previous!=pos: tracer(previous,pos,.08,Color("ffd88a"),4,.9)
					impact(pos,1.1 if last else .8)
					emit_particles("smoke",pos,6 if last else 2)
					shake_by(.55 if last else .4)
					if last: ring(pos,cw*.3,cw*2.4,.6,Color(1,.784,.47,.85),4))
		"scan":
			for target in cells:
				add({"kind":"scan_frame","pos":target,"life":.75,"size":cw*.45,"color":Color("85ccff")})
			var pos := Vector2.ZERO
			for cell in cells: pos += cell
			pos /= cells.size()
			add({"kind":"sweep","pos":pos,"radius":cw*1.5,"angle":randf()*TAU,"life":1.0})
			ring(pos,cw*.3,cw*1.875,.6,Color(.22,.53,.92,.85),2)
			after(.3,func(): ring(pos,cw*.3,cw*1.875,.6,Color(.22,.53,.92,.6),2))
			var found: Array = data.get("extra",[])
			for i in range(found.size()):
				var at := point(found[i])
				after(.35+i*.1,func():
					ring(at,cw*.1,cw*.8,.5,Color(.47,.745,1),3)
					add({"kind":"dot","pos":at,"life":.6,"size":cw*.14,"color":Color("9fd0ff"),"add":true}))
		"kill":
			var pos: Vector2 = cells.back()
			var hit := func():
				vignette(.6,.5)
				flash(pos,cw*2.6,.28,Color(1,.863,.47))
				ring(pos,cw*.3,cw*3.2,.7,Color(1,.902,.627,.95),5)
				emit_particles("spark",pos,44,cw*13)
				shake_by(.65)
				if not reduced: slow = .3
				after(.06,func(): emit_particles("fireball",pos,26); emit_particles("debris",pos,26,cw*11))
				after(.2,func(): emit_particles("smoke",pos,30,0,true))
				after(.45,func(): emit_particles("spark",pos,14,cw*5))
			if source!=null:
				flash(source,cw*.8,.14,Color(1,.941,.706,.95))
				tracer(source,pos,.12,Color("ffe9a0"),3,.3)
				after(.12,hit)
			else: hit.call()

func ending(kind: String) -> void:
	var cw := cell_width()
	var count: int = {"victory":20 if reduced else 120,"defeat":15 if reduced else 80,"drawend":10 if reduced else 40}[kind]
	if kind=="defeat": vignette(.7,2.2)
	for i in range(count):
		after(randf_range(0,{"victory":.9,"defeat":1.2,"drawend":.8}[kind]),func():
			var p := {"kind":"confetti","pos":Vector2(randf_range(0,size.x),randf_range(-cw,0)),"fade_in":true,"rot":randf()*TAU,"drag":.4}
			if kind=="victory": p.merge({"v":Vector2(randf_range(-20,20),randf_range(cw*1.2,cw*2.4)),"grav":cw*1.5,"vr":randf_range(-4,4),"freq":randf_range(3,7),"amp":randf_range(4,12),"life":randf_range(2.2,3.2),"size":randf_range(5,9),"color":CONFETTI.pick_random()})
			elif kind=="defeat": p.merge({"kind":"dot","v":Vector2(randf_range(-8,8),randf_range(cw*.5,cw*1.1)),"drag":.2,"life":randf_range(2,3.2),"size":randf_range(1.2,2.6),"color":Color(.588,.588,.588,.8)},true)
			else: p.merge({"v":Vector2(randf_range(-10,10),randf_range(cw*.9,cw*1.6)),"grav":cw,"vr":randf_range(-3,3),"freq":randf_range(3,6),"amp":randf_range(3,8),"life":randf_range(2,2.8),"size":randf_range(4,7),"color":[Color("cfc7bb"),Color("a49d93"),Color("e6c96a")].pick_random()})
			add(p))
	if kind=="victory": after(.2,func(): emit_particles("spark",Vector2(size.x/2,size.y*.4),30,cw*8))
