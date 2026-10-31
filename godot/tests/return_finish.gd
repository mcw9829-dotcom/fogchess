extends SceneTree
var app
var checks:=0
var failures:=0
var out: String
func _initialize():run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func shot(name: String) -> Image:
	await process_frame;RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image();image.save_png(out.path_join(name+".png"));return image
func near_images(a: Image,b: Image,region: Rect2i=Rect2i()) -> bool:
	if region.has_area():a=a.get_region(region);b=b.get_region(region)
	var first:=a.get_data();var second:=b.get_data()
	if first.size()!=second.size():return false
	for i in range(first.size()):
		if absi(int(first[i])-int(second[i]))>2:return false
	return true
func wait_phase(phase: String):
	var deadline:=Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(app.ui_motion.transition) and app.ui_motion.transition.phase==phase:return
	check(false,"reaches "+phase)
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
			await app._join({"solo":true});await wait_phase("idle");await create_timer(.45).timeout
			var ended: Dictionary=app.view.duplicate(true);ended.phase="over";ended.winner="W"
			if black:app.seat="B";ended.yourColor="B"
			app._apply_state(ended);await create_timer(.6).timeout
			var grid: Array=app.view.grid.duplicate(true)
			var panel_rect: Rect2i=Rect2i(app.result_panel.get_global_rect())
			var original:=await shot(name+"-result")
			app._return_home();await wait_phase("playing")
			var tr=app.ui_motion.transition;tr.set_process(false);tr._pose(tr.DURATION)
			check(is_equal_approx(tr.DURATION,1.3),"approved 1.3 second duration retained "+name)
			check(is_instance_valid(tr.return_result) and tr.return_result.visible,"result survives first return frame "+name)
			var first:=await shot(name+"-return-start")
			check(near_images(original,first,panel_rect),"result region has no first-frame cut "+name)
			check(tr.match_board.fog_display_strength==tr.saved_fog_strength,"return starts at original fog brightness "+name)
			tr._pose(tr.DURATION-.09)
			check(is_equal_approx(tr.return_result.modulate.a,.5),"result fades rather than disappearing instantly "+name)
			tr._pose(tr.DURATION-.20)
			check(not tr.return_result.visible,"result cleared before board moves "+name)
			var previous: float=tr.saved_fog_strength;var smooth:=true;var max_step:=0.0
			for frame in range(27):
				tr._pose(tr.DURATION-frame/60.0)
				var current: float=tr.match_board.fog_display_strength
				smooth=smooth and current<=previous+.00001;max_step=maxf(max_step,previous-current);previous=current
			check(smooth and previous==0.0 and max_step<.08,"fog clears gradually before artwork swap "+name)
			check(tr.match_board.modulate.a==1.0,"fog removal happens before two board contents blend "+name)
			check(tr.match_board.view.grid==grid,"return rendering never reveals or edits pieces "+name)
			var backdrop=app.ui_shell.lobby_home.backdrop;backdrop.set_process(false)
			backdrop.phase+=2.0;backdrop.motion_layer.queue_redraw();tr._pose(.1)
			check(tr.map.phase==backdrop.phase,"transition map follows the live lobby clock "+name)
			tr._pose(0.0)
			var final_proxy:=await shot(name+"-final-proxy")
			tr._complete()
			var final_live:=await shot(name+"-final-live")
			check(near_images(final_proxy,final_live),"last return frame matches actual lobby pixels "+name)
			check(app.home.visible and not tr.is_busy() and not tr.is_processing_input(),"return releases input and clears transition "+name)
			backdrop.set_process(true)
	# A departure during the entry fog fade must start at that partial opacity.
	await app._join({"solo":true});await wait_phase("idle")
	app.board.set_process(false);app.board.begin_fog_arrival();app.board._process(0);app.board._process(.2)
	app._return_home();await wait_phase("playing")
	var partial=app.ui_motion.transition;partial.set_process(false);partial._pose(partial.DURATION)
	check(is_equal_approx(partial.match_board.fog_display_strength,.5),"early exit preserves partial fog")
	check(not is_instance_valid(partial.return_result),"ordinary match exit creates no result overlay")
	partial._pose(partial.DURATION-.4);check(partial.match_board.fog_display_strength==0,"partial fog also resolves to bright lobby")
	partial._complete();app.board.set_process(true)
	for width in [390,320]:
		root.size=Vector2i(width,844);app._layout();await create_timer(.2).timeout
		await app._join({"solo":true});await wait_phase("idle");await create_timer(.45).timeout
		app._return_home();await wait_phase("playing")
		var mobile=app.ui_motion.transition;mobile.set_process(false);mobile._pose(mobile.DURATION-.4)
		check(not mobile.source_visible and mobile.match_board.fog_display_strength==mobile.saved_fog_strength,"mobile fades board without inventing bright lobby board "+str(width))
		mobile._pose(0);mobile._complete();await process_frame
		check(app.home.visible and not mobile.is_busy(),"mobile return releases input "+str(width))
	print("LOBBY_CHECKS=",checks);print("LOBBY_FAILURES=",failures)
	app.queue_free();await process_frame;await process_frame;quit(failures)
