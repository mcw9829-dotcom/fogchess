extends SceneTree
var app
var checks:=0
var failures:=0
var out: String
func _initialize():run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func shot(name: String) -> Image:
	await process_frame;RenderingServer.force_draw(false)
	var pixels:=root.get_texture().get_image()
	pixels.save_png(out.path_join(name+".png"))
	return pixels
func wait_phase(phase: String):
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(app.ui_motion.transition) and app.ui_motion.transition.phase==phase:return
	check(false,"reaches "+phase)
func color_near(a: Color,b: Color) -> bool:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))<=2.0/255
func sample(pixels: Image, cell: Vector2i) -> Color:
	var point: Vector2=app.board.global_position+app.board.center(cell)
	return pixels.get_pixelv(Vector2i(point))
func empty_cell(fogged: bool) -> Vector2i:
	for r in [0,1,9,10,11,2,3,4,5,6,7,8]:
		for c in range(12):
			var data: Dictionary=app.view.grid[r][c]
			if int(data.get("t",0))==0 and data.get("p")==null and (int(data.get("f",1))>0)==fogged:return Vector2i(r,c)
	return Vector2i(-1,-1)
func run():
	out=OS.get_environment("FOG_CAPTURE_DIR");root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer:child.stop()
	app.audio.enabled=false
	for light in [false,true]:
		for black in [false,true]:
			var name: String=("light" if light else "dark")+("-black" if black else "-white")
			app.prefs.set_value("settings","light",light);app._apply_theme();await create_timer(.15).timeout
			check(app.ui_shell.lobby_home.preview_board.fog_display_strength==0,"lobby starts bright "+name)
			await app._join({"solo":true})
			if black:
				app.seat="B";var black_view: Dictionary=app.view.duplicate(true);black_view.yourColor="B";app._apply_state(black_view)
			await wait_phase("playing")
			var tr=app.ui_motion.transition;tr.set_process(false)
			var grid: Array=app.view.grid.duplicate(true)
			check(tr.lobby_board.fog_display_strength==0 and tr.match_board.fog_display_strength==0,"both moving contents retain lobby brightness "+name)
			check(tr.match_board.view.grid==grid and not app.reveal,"presentation never changes fog flags or requests reveal "+name)
			var hidden:=empty_cell(true);var visible_cell:=empty_cell(false)
			check(hidden.x>=0 and visible_cell.x>=0,"fixture has hidden and visible empty cells "+name)
			tr.refresh_view()
			check(tr.match_board.fog_display_strength==0 and tr.match_board.view.grid==grid,"state update preserves bright presentation and authorized data "+name)
			tr._pose(tr.DURATION)
			var proxy:=await shot(name+"-bright-proxy")
			var expected:=Color("#f0d9b5") if (hidden.x+hidden.y)%2==0 else Color("#b58863")
			check(color_near(sample(proxy,hidden),expected),"hidden empty square renders original bright board color "+name)
			tr._complete();app.board.set_process(false)
			var first:=await shot(name+"-bright-live")
			check(not tr.is_busy() and app.board.fog_display_strength==0,"fog begins only after 1.3 second movement completes "+name)
			check(color_near(sample(first,hidden),sample(proxy,hidden)),"first live board has no brightness jump "+name)
			app.board._process(1.0/60)
			check(app.board.fog_display_strength==0,"first live process tick holds brightness "+name)
			var last:=0.0;var monotonic:=true
			for i in range(12):
				app.board._process(1.0/60)
				monotonic=monotonic and app.board.fog_display_strength>=last
				last=app.board.fog_display_strength
			var half:=await shot(name+"-fog-half")
			check(is_equal_approx(app.board.fog_display_strength,.5),"fog reaches half opacity after 0.2 seconds "+name)
			for i in range(12):
				app.board._process(1.0/60)
				monotonic=monotonic and app.board.fog_display_strength>=last
				last=app.board.fog_display_strength
			var settled:=await shot(name+"-fog-settled")
			check(monotonic and app.board.fog_display_strength==1 and app.board.fog_arrival_age<0,"fog reaches original opacity smoothly in 24 frames "+name)
			check(sample(first,hidden).get_luminance()>sample(half,hidden).get_luminance() and sample(half,hidden).get_luminance()>sample(settled,hidden).get_luminance(),"rendered hidden square darkens monotonically "+name)
			check(color_near(sample(first,visible_cell),sample(settled,visible_cell)),"visible square keeps the same brightness "+name)
			check(app.board.view.grid==grid and app.view.grid==grid,"fog arrival never edits pieces or visibility "+name)
			app.board.begin_fog_arrival();app.board._process(.01);app.board._process(.2)
			var fading_strength: float=app.board.fog_display_strength
			app._return_home();await wait_phase("playing");tr.set_process(false)
			check(is_equal_approx(tr.match_board.fog_display_strength,fading_strength),"early return starts at current fog brightness "+name)
			check(tr.lobby_board.fog_display_strength==0,"return destination is bright lobby "+name)
			tr._complete();await process_frame
			check(app.home.visible and app.board.fog_arrival_age<0 and app.board.fog_display_strength==1,"return clears live fog animation "+name)
			app.board.set_process(true)
	for width in [390,320]:
		root.size=Vector2i(width,844);app._layout();await create_timer(.2).timeout
		await app._join({"solo":true});await wait_phase("playing")
		check(not app.ui_motion.transition.source_visible and app.ui_motion.transition.match_board.fog_display_strength==0,"mobile enters bright "+str(width))
		await wait_phase("idle");await create_timer(.5).timeout
		check(app.board.fog_display_strength==1 and app.board.fog_arrival_age<0,"mobile restores normal fog after entry "+str(width))
		app._return_home();await wait_phase("idle")
	print("LOBBY_CHECKS=",checks);print("LOBBY_FAILURES=",failures)
	app.queue_free();await process_frame;await process_frame;quit(failures)
