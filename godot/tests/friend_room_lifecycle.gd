extends SceneTree
var app
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok: failures += 1
func wait_for(condition: Callable) -> void:
	var end := Time.get_ticks_msec()+6500
	while not condition.call() and Time.get_ticks_msec()<end:
		await create_timer(.05).timeout
func settled() -> void:
	await wait_for(func(): return not app.busy and not app.ui_motion.is_transition_busy())
	await process_frame
func shot(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args(): return
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func confirm_leave(accept: bool) -> void:
	app.game_session._leave_prompt()
	await process_frame
	var dialog=app.get_node_or_null("GameConfirmation")
	check(is_instance_valid(dialog),"leave confirmation exists")
	if not is_instance_valid(dialog): return
	if accept: dialog.get_ok_button().pressed.emit()
	else: dialog.get_cancel_button().pressed.emit()
	await wait_for(func(): return app.get_node_or_null("GameConfirmation")==null)
	await settled()
func run() -> void:
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for node in app.get_children():
		if node is Timer: node.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","lobby_music",false)
	var owner: Dictionary=await app.api.request("/signup",{"name":"CancelOwner","pw":"FixturePass123!"})
	app.session=owner.session;app.me=owner.user
	for width in [1440,390]:
		var before_history: Dictionary=await app.api.request("/me/history",{"session":app.session})
		root.size=Vector2i(width,900 if width==1440 else 844)
		app._layout()
		await app._join({"room":"ZZZZ"})
		check(app.room.is_empty() and app.home.visible and app.notice.text.contains("방 코드"),"invalid code stays in lobby with error "+str(width))
		await shot("invalid-"+str(width))
		await app._join({});await settled()
		var old_room: String=app.room
		check(not old_room.is_empty() and not app.view.get("bothJoined",true),"empty friend room created")
		await confirm_leave(false)
		check(app.room==old_room,"cancel dialog keeps original room")
		await confirm_leave(true)
		await wait_for(func(): return app.room.is_empty())
		await settled()
		await app.lobby_status.refresh_active()
		check(app.room.is_empty() and app.home.visible and app.lobby_status.active.is_empty(),"empty room exit releases account "+str(width))
		await shot("cancelled-"+str(width))
		var history: Dictionary=await app.api.request("/me/history",{"session":app.session})
		check(history.has("rows") and history.rows==before_history.rows,"cancel produces no history")
		await app._match_command("join")
		check(app.matching,"rank queue works after cancellation")
		await app._match_command("cancel")
		var host: Dictionary=await app.api.request("/join",{"name":"Friend"})
		await app._join({"room":host.room});await settled()
		check(app.room==host.room and app.seat!=host.color and app.view.get("bothJoined",false),"valid friend join works after cancellation")
		await app._act({"type":"resign"})
		await confirm_leave(true)
		await settled()
	# A peer joins after the user has already opened the empty-room exit dialog.
	await app._join({});await settled()
	var race_room: String=app.room
	var race_token: String=app.token
	app.game_session._leave_prompt();await process_frame
	await app.api.request("/join",{"room":race_room,"name":"ArrivingPeer"})
	app.get_node("GameConfirmation").get_ok_button().pressed.emit()
	await wait_for(func(): return app.view.get("bothJoined",false))
	check(app.room==race_room and app.token==race_token and app.view.get("bothJoined",false),"peer arriving during confirmation preserves both seats")
	check(app.notice.text.contains("취소할 수 없습니다"),"race displays cancellation refusal")
	await shot("peer-arrival-protected")
	print("FRIEND_ROOM_CHECKS=",checks)
	print("GODOT_SMOKE_FAILURES=",failures)
	app.queue_free();await process_frame;await process_frame
	quit(failures)
