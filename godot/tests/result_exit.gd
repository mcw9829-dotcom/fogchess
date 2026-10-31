extends SceneTree
var app
var checks := 0
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func buttons(text: String) -> Array:
	return app.result_actions.get_children().filter(func(n):return n is Button and n.text==text)
func shot(name: String):
	await create_timer(.3).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func run():
	root.size=Vector2i(1280,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	await app._join({"vs_bot":true,"level":"easy"})
	await create_timer(2.0).timeout
	await app._act({"type":"resign"})
	check(app.view.get("phase")=="over" and app.view.get("bot",false),"real bot defeat reaches result")
	var ended: Dictionary=app.view.duplicate(true)
	var variants: Array=[
		{"name":"bot","bot":true},
		{"name":"solo","solo":true},
		{"name":"friend"},
		{"name":"opponent-left","oppConnected":false},
		{"name":"proposal-sent","rematch":{"me":true,"opp":false}},
		{"name":"proposal-received","rematch":{"me":false,"opp":true}},
		{"name":"series-complete","series":{"me":2,"opp":1,"winner":"W","complete":true,"final":true}},
	]
	for winner in ["W","B","draw"]:
		for spec in variants:
			app.seat="W"
			app.view=ended.duplicate(true)
			app.view.merge({"winner":winner,"yourColor":"W","bot":false,"solo":false,"oppConnected":true,"rematch":{},"series":{},"replayId":"fixture-replay"},true)
			app.view.merge(spec,true)
			app.result_signature=""
			app._render_result()
			var label: String=spec.name+" "+winner
			check(buttons("나가기").size()==1 and buttons("홈으로").is_empty(),"one consistently named exit: "+label)
			check(buttons("기보 / 리플레이 보기").size()==1,"replay remains available: "+label)
			if spec.name in ["bot","solo"]:
				check(buttons("다시 대국").size()==1,"rematch remains available: "+label)
			var exit_button=buttons("나가기")[0]
			app._render_result()
			check(buttons("나가기").size()==1 and buttons("나가기")[0]==exit_button,"poll refresh preserves exit: "+label)
	# A received rematch proposal must not remove the exit during state updates.
	app.view=ended.duplicate(true);app.view.bot=false;app.view.oppConnected=true;app.view.rematch={}
	app._render_result()
	app.view.rematch={"me":false,"opp":true};app._render_result()
	check(buttons("나가기").size()==1 and buttons("다음 판 수락").size()==1 and buttons("거절").size()==1,"incoming offer keeps exit and both responses")
	app.seat="spectator";app._render_result()
	check(buttons("관전 마치기").size()==1 and buttons("나가기").is_empty(),"spectator keeps one dedicated exit")
	app.seat="W";app.view=ended.duplicate(true);app._render_result()
	# Both themes and the narrowest supported mobile layout keep exit in view.
	var scaler=load("res://features/web_viewport.gd").new();app.add_child(scaler)
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		for width in [1280,360,320]:
			var logical=Vector2i(width,900 if width==1280 else 740)
			root.size=logical*(1 if width==1280 else 3)
			scaler.apply_css_size(logical)
			await create_timer(.4).timeout
			app.page_scroll.scroll_vertical=0
			var exit_button=buttons("나가기")[0]
			var rect: Rect2=exit_button.get_global_rect()
			var scroll=app.result_panel.get_node("ResultScroll")
			check(rect.size.y>=44 and scroll.get_global_rect().encloses(rect),"exit is visible and touch-sized: "+str(width)+" light="+str(light))
			await shot(("light" if light else "dark")+"-defeat-"+str(width))
	# Use actual scaled input to open the exit confirmation, then cancel and leave.
	var exit_button=buttons("나가기")[0]
	var physical: Vector2=root.get_stretch_transform()*exit_button.get_global_rect().get_center()
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.position=physical;event.global_position=physical
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,false)
		await process_frame
	await create_timer(.4).timeout
	var dialogs: Array=app.get_children().filter(func(n):return n is Window and n.visible)
	check(dialogs.size()==1,"result exit opens confirmation through scaled input")
	if dialogs.size()==1:
		check(dialogs[0].get_ok_button().text=="나가기" and not app.game_session.leave_is_resignation(),"finished match exit is not a new resignation")
		dialogs[0].get_cancel_button().pressed.emit()
		await create_timer(.4).timeout
		check(not app.room.is_empty() and app.result_panel.visible,"cancel stays on result")
		buttons("나가기")[0].pressed.emit()
		await create_timer(.3).timeout
		dialogs=app.get_children().filter(func(n):return n is Window and n.visible)
		dialogs[0].get_ok_button().pressed.emit()
		await create_timer(2.0).timeout
		check(app.room.is_empty() and app.home.visible and not app.ui_motion.is_transition_busy(),"confirmed exit returns to usable lobby")
	var f=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close()
	print("RESULT_EXIT_CHECKS=",checks," FAILURES=",failures.size())
	app.queue_free();await process_frame;await process_frame;quit(failures.size())
