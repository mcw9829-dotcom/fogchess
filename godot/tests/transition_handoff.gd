extends SceneTree
var app
var out: String
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func shot(name: String) -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	image.save_png(out.path_join(name+".png"))
	return image
func matches_pixels(a: Image, b: Image) -> bool:
	if a.get_size()!=b.get_size():return false
	var first:=a.get_data();var second:=b.get_data()
	for i in range(first.size()):
		if absi(int(first[i])-int(second[i]))>2:return false
	return true
func alpha_check(tr):
	var backdrop:=ColorRect.new();backdrop.color=Color(.1,.2,.3,1)
	backdrop.position=Vector2(30,30);backdrop.size=Vector2(260,100);tr.stage.add_child(backdrop)
	var reference:=ColorRect.new();reference.color=Color(.8,.4,.2,.5)
	reference.position=Vector2(10,10);reference.size=Vector2(80,80);backdrop.add_child(reference)
	var pixels:=Image.create(80,80,false,Image.FORMAT_RGBA8);pixels.fill(Color(.4,.2,.1,.5))
	var captured=tr._art(pixels,Rect2(0,0,80,80),backdrop);captured.position=Vector2(150,10)
	for opacity in [0.0,.25,.5,.75,1.0]:
		reference.modulate.a=opacity;tr._capture_opacity(captured,opacity)
		await process_frame;RenderingServer.force_draw(false)
		var image:=root.get_texture().get_image()
		var real:=image.get_pixel(80,80);var proxy:=image.get_pixel(220,80)
		check(maxf(absf(real.r-proxy.r),maxf(absf(real.g-proxy.g),absf(real.b-proxy.b)))<=2.0/255,"captured pixels match native alpha fade "+str(opacity))
	backdrop.queue_free();await process_frame
func wait_phase(phase: String):
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(app.ui_motion.transition) and app.ui_motion.transition.phase==phase:return
	check(false,"reaches "+phase)
func run():
	out=OS.get_environment("FOG_CAPTURE_DIR")
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer:child.stop()
	app.audio.enabled=false
	for light in [false,true]:
		for black in [false,true]:
			var name: String=("light" if light else "dark")+("-black" if black else "-white")
			app.prefs.set_value("settings","light",light);app._apply_theme();await create_timer(.2).timeout
			await app._join({"solo":true})
			if black:
				app.seat="B"
				var data: Dictionary=app.view.duplicate(true);data.yourColor="B";app._apply_state(data)
			await wait_phase("playing")
			var tr=app.ui_motion.transition
			tr.set_process(false)
			if not light and not black:await alpha_check(tr)
			check(is_equal_approx(tr.DURATION,1.3),"1.3 second duration unchanged "+name)
			tr._pose(.8)
			check(tr.board_surround.visible and not tr.lobby_board.show_surround and not tr.match_board.show_surround,"single surround through content crossfade "+name)
			tr._pose(.95)
			check(not tr.lobby_board.visible and tr.match_board.visible,"old contents hidden after 80ms handoff "+name)
			await shot(name+"-settled-board")
			tr._pose(1.2)
			var notice: Array=tr.hud.filter(func(part):return part.fade_only)
			check(notice.size()==1 and notice[0].mask.visible and notice[0].node.modulate.a>0,"notice appears before transition ends "+name)
			var opacity: Color=notice[0].node.modulate
			check(is_equal_approx(opacity.r,opacity.a) and opacity.a<1,"captured fade modulates RGB and alpha together "+name)
			tr._pose(tr.DURATION)
			var proxy:=await shot(name+"-proxy")
			tr._complete()
			app.board.set_process(false)
			var live:=await shot(name+"-live")
			app.board.set_process(true)
			check(matches_pixels(proxy,live),"last transition frame matches real game pixels "+name)
			check(app.board.show_surround,"ordinary game board retains original frame "+name)
			tr.cancel();await process_frame;await process_frame
			app._return_home();await wait_phase("idle")
			check(app.home.visible and not app.ui_motion.is_transition_busy(),"reverse still returns to interactive lobby "+name)
	print("LOBBY_CHECKS=",checks);print("LOBBY_FAILURES=",failures)
	app.queue_free();await process_frame;await process_frame;quit(failures)
