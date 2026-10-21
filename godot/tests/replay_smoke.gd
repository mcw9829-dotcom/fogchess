extends SceneTree
var app
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok: failures+=1; push_error(text)
	else: print("PASS: "+text)
func run() -> void:
	root.size = Vector2i(1280,850)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	var fixture: Dictionary = await app.api.request("/test-fixture",{"scenario":"piece_N"})
	await app.api.request("/test-brush",{"room":fixture.room})
	app._enter(fixture)
	await app._poll()
	await app._select(Vector2i(6,6))
	await app._act({"type":"move","pid":"W_N1","r":4,"c":7})
	await app._act({"type":"resign"})
	check(app.view.phase=="over","fixture ends")
	check(app.view.get("replayId")!=null,"finished game has saved replay")
	check(app.prefs.get_value(app.api.base_url,"replays",[]).size()==1,"local replay library remembers game")
	var id: String = app.view.replayId
	await app.replay.open(id,app.token)
	check(app.replay.active and app.replay.bar.visible,"replay opens from finished room")
	check(app.replay.index==0,"starts at initial board")
	check(app.replay.frame_picker.item_count==app.replay.data.frames.size(),"notation picker contains every frame")
	app.replay.jump_event(1)
	check(app.replay.index==1,"event jump finds capture")
	app.replay.vision="W"
	check("시야: 백" in app.replay.report_context() and app.replay.data.id in app.replay.report_context(),"report includes replay ID frame and perspective")
	app.replay.seek(0)
	app.replay.vision="all"
	check(app.replay.bar_panel.get_index()>app.board.get_index(),"transport below board")
	check(app.replay.vision_panel.get_index()<app.board.get_index(),"vision selector above board")
	app.replay.vision_buttons[1].pressed.emit()
	check(app.board.tile(Vector2i(0,0)).get("p")==null,"white vision hides distant black king")
	app.replay.vision_buttons[2].pressed.emit()
	check(app.board.tile(Vector2i(0,0)).get("p") is Dictionary,"black vision shows own king")
	app.replay.vision_buttons[0].pressed.emit()
	check(app.board.tile(Vector2i(0,0)).get("p") is Dictionary,"full vision restored")
	check(app.board.tile(Vector2i(6,6)).get("p") is Dictionary,"initial knight restored")
	app.replay.step(1)
	check(app.board.tile(Vector2i(4,7)).get("p") is Dictionary,"next move restores capture position")
	app.replay.step(-1)
	check(app.board.tile(Vector2i(6,6)).get("p") is Dictionary,"previous move restores original position")
	var original_index: int = app.replay.index
	await app._poll()
	check(app.replay.index==original_index and app.view.phase!="over","live poll does not overwrite replay")
	app.replay.toggle()
	await create_timer(1.7).timeout
	check(app.replay.index==1,"automatic playback advances")
	app.replay.toggle()
	var paused: int = app.replay.index
	await create_timer(1.7).timeout
	check(app.replay.index==paused,"pause holds frame")
	app.replay.step(999)
	check(app.replay.next_button.disabled,"last frame stops forward navigation")
	app.replay.step(-1)
	app.replay.toggle()
	await create_timer(1.7).timeout
	check(not app.replay.playing and app.replay.timer.is_stopped(),"autoplay stops at final frame")
	app.replay.toggle()
	check(app.replay.index==0,"autoplay restarts from beginning")
	app.replay.toggle()
	app.replay.step(999)
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280,1000)
		app.replay.step(-1)
		await create_timer(.3).timeout
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("res://tests/replay_board.png")
		root.size = Vector2i(390,844)
		await create_timer(.3).timeout
		RenderingServer.force_draw(false)
		check(app.replay.transport_center.size.x<=app.replay.transport.size.x,"mobile transport fits")
		root.get_texture().get_image().save_png("res://tests/replay_mobile.png")
		root.size = Vector2i(1280,850)
	app.replay.close()
	check(not app.replay.active and app.view.phase=="over","close restores result")
	app._return_home()
	app.replay.menu()
	check(app.subpage.visible,"saved replay library opens")
	var saved: Array = app.prefs.get_value(app.api.base_url,"replays",[])
	await app.replay.open(saved[0].id,saved[0].token)
	check(app.replay.active,"saved replay reopens after leaving room")
	app.replay.close()
	for node in app.audio.get_children():
		if node is AudioStreamPlayer: node.stop()
	await create_timer(.5).timeout
	print("REPLAY_FAILURES=",failures)
	quit(1 if failures else 0)
