extends SceneTree
var app: Control
var failures := 0
var checks := 0
var out: String
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok: failures+=1
	print(("PASS: " if ok else "FAIL: ")+label)
func settle(seconds: float=.2): await create_timer(seconds).timeout
func shot(name: String) -> Image:
	await process_frame
	RenderingServer.force_draw(false)
	var pixels:=root.get_texture().get_image()
	pixels.save_png(out.path_join(name+".png"))
	return pixels
func wait_phase(wanted: String):
	for i in range(180):
		await process_frame
		if is_instance_valid(app.ui_motion.transition) and app.ui_motion.transition.phase==wanted: return
	check(false,"transition reached "+wanted)
func image_difference(first: Image, second: Image, rect: Rect2) -> float:
	var region:=Rect2i(rect.grow(-10))
	var a:=first.get_region(region).get_data()
	var b:=second.get_region(region).get_data()
	var sum:=0.0
	for i in range(a.size()): sum+=absf(float(a[i])-float(b[i]))/255.0
	return sum/a.size()
func run():
	out=OS.get_environment("FOG_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1120,760)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await settle(.4)
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false;app.session="a";app.me={"name":"플레이어","rating":1000,"tier":"N"}
	for dimensions in [Vector2i(1120,760),Vector2i(390,844)]:
		root.size=dimensions;app._layout();await settle(.3)
		for light in [false,true]:
			app.prefs.set_value("settings","light",light);app._apply_theme();await settle(.2)
			var prefix: String=("mobile" if dimensions.x<500 else "desktop")+("-light" if light else "-dark")
			await app._match_command("join")
			await app.api.request("/test-queue-age",{})
			await app._match_update(await app.api.request("/match/status",{"session":"a"}))
			await settle(.2)
			var initial: Rect2=app.lobby_status.queue_card.get_global_rect()
			var reference:=await shot(prefix+"-lobby")
			await app._join({"vs_bot":true,"level":"easy"})
			await wait_phase("playing")
			var tr=app.ui_motion.transition;tr.set_process(false)
			var arrived: Rect2=app.lobby_status.queue_card.get_global_rect()
			check(initial.is_equal_approx(arrived),prefix+" queue geometry unchanged on entry")
			check(is_equal_approx(tr.DURATION,1.3),prefix+" approved transition duration retained")
			for value in [.0,.15,.5,1.0,1.3]:
				tr._pose(value)
				var image:=await shot(prefix+"-entry-"+str(value))
				var difference:=image_difference(reference,image,initial)
				check(difference<.012,prefix+" queue stays visible and fixed at "+str(value)+"s; difference="+str(difference))
			tr._complete();await settle(.2)
			check(not app.lobby_status.queue_card.get_global_rect().intersects(app.board.get_global_rect()),prefix+" queue and board do not overlap")
			await shot(prefix+"-game")
			await app.api.request("/practice/leave",{"session":"a","room":app.room})
			app._return_home();await wait_phase("playing")
			tr.set_process(false)
			var back: Rect2=app.lobby_status.queue_card.get_global_rect()
			check(initial.is_equal_approx(back),prefix+" queue geometry unchanged on return")
			for value in [1.3,.7,.15,.0]:
				tr._pose(value)
				var image:=await shot(prefix+"-return-"+str(value))
				check(image_difference(reference,image,initial)<.012,prefix+" queue fixed during return "+str(value))
			tr._complete();await settle(.2)
			await app._match_command("cancel")
			await settle(.2)
	print("QUEUE_TRANSITION_CHECKS=%d" % checks)
	print("QUEUE_ACTIVITIES_FAILURES=%d" % failures)
	app.queue_free();await process_frame;quit(1 if failures else 0)
