extends SceneTree
var app
var scaler
var checks := 0
var failures: Array[String] = []
var cases: Array = []
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	print(("PASS " if ok else "FAIL ")+message)
	if not ok: failures.append(message)
func settle(seconds: float=.3): await create_timer(seconds).timeout
func shot(name: String):
	await settle()
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func viewport(css: Vector2i, dpr: float):
	root.size = Vector2i(Vector2(css)*dpr)
	scaler.apply_css_size(css)
	await settle(.4)
	check(app.size.distance_to(Vector2(css))<1,"logical viewport "+str(css)+" DPR "+str(dpr))
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().get_size()==root.size,"full resolution canvas "+str(css))
func mouse_click(control: Control):
	# The web engine supplies canvas-pixel positions, before viewport stretching.
	var physical: Vector2 = root.get_stretch_transform()*control.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=physical
		event.global_position=physical
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		root.push_input(event,false)
		await process_frame
	await settle(.4)
func touch_cell(cell: Vector2i):
	var physical: Vector2 = root.get_stretch_transform()*(app.board.global_position+app.board.center(cell))
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position=physical
		event.pressed=down
		root.push_input(event,false)
		await process_frame
	await settle(.2)
func close_windows():
	for child in app.get_children():
		if child is Window: child.hide(); child.queue_free()
	await process_frame
func run():
	root.borderless=true
	root.size=Vector2i(1120,760)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await settle(.6)
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","lobby_music",false)
	scaler=load("res://features/web_viewport.gd").new()
	app.add_child(scaler)
	var lobby=app.ui_shell.lobby_home
	for entry in [[Vector2i(320,740),2.0],[Vector2i(360,692),3.0],[Vector2i(390,744),3.0],[Vector2i(412,820),2.625],[Vector2i(844,390),2.0],[Vector2i(834,1112),2.0],[Vector2i(1440,900),1.0],[Vector2i(1440,900),1.5]]:
		await viewport(entry[0],entry[1])
		lobby.select_section("computer",false)
		app.page_scroll.scroll_vertical=0
		await settle()
		var mobile: bool=entry[0].x<774
		check(lobby.compact==mobile,"correct breakpoint "+str(entry[0]))
		if mobile:
			check(not lobby.preview_column.visible,"portrait hides decorative preview")
			check(lobby.headers.computer.size.y>=60,"primary touch target >=60 CSS pixels")
			check(lobby.level_buttons.all(func(b):return b.size.y>=44),"difficulty touch targets >=44 CSS pixels")
			check(lobby.menu_column.get_global_rect().end.x<=app.size.x,"no horizontal menu overflow")
			await mouse_click(lobby.headers.practice)
			check(lobby.selected=="practice","scaled input hits correct menu "+str(entry[0]))
			lobby.select_section("computer",false)
		await shot("lobby-"+str(entry[0].x)+"-dpr"+str(entry[1]))
		cases.append({"css":str(entry[0]),"dpr":entry[1],"physical":str(root.size)})
	# Resizing a high-density display must not leave the desktop layout cached.
	await viewport(Vector2i(360,692),3.0)
	check(lobby.compact,"landscape/tablet/desktop back to portrait")
	app.prefs.set_value("settings","light",true);app._apply_theme()
	await shot("lobby-light-360")
	app.prefs.set_value("settings","light",false);app._apply_theme()
	app._account()
	await settle()
	var windows: Array=app.get_children().filter(func(n):return n is Window and n.visible)
	check(windows.size()==1,"login opens")
	if windows.size()==1:
		check(windows[0].size.x<=360,"login fits logical width")
	await shot("login-360")
	await viewport(Vector2i(320,640),3.0)
	if windows.size()==1:
		check(windows[0].size.x<=296,"open login adapts to narrower viewport")
		check(windows[0].position.x>=0,"open login remains on screen")
	await shot("login-320")
	await close_windows()
	app._account()
	await settle()
	windows=app.get_children().filter(func(n):return n is Window and n.visible)
	check(windows.size()==1 and windows[0].size.x<=296,"new login fits smallest phone")
	await close_windows()
	await viewport(Vector2i(360,692),3.0)
	app._settings()
	await shot("settings-360")
	app._navigation_home()
	await app._join({})
	await app.api.request("/join",{"room":app.room,"name":"Mobile fixture opponent"})
	await app._poll()
	await settle(1.8)
	var assist=app.ui_shell.aim_assist
	for css in [Vector2i(320,640),Vector2i(360,692),Vector2i(390,744),Vector2i(412,820)]:
		await viewport(css,3.0)
		app.page_scroll.scroll_vertical=0
		await settle()
		check(app.split.vertical,"portrait match stacked "+str(css))
		check(app.board.size.x>=css.x-40,"board fills phone width "+str(css))
		check(root.get_visible_rect().encloses(assist.ready_action.get_global_rect()),"ready button visible "+str(css))
		check(assist.footer.get_global_rect().end.x<=app.size.x-7,"footer keeps right margin "+str(css))
		check(app.board.get_global_rect().end.y<=assist.footer.get_global_rect().position.y,"ready footer does not obscure board "+str(css))
		await shot("setup-"+str(css.x))
	await assist._ready_pressed()
	check(app.view.get("ready",false),"ready still reaches server")
	var data: Dictionary=await app.api.request("/test-focus",{})
	app._enter(data)
	await app._poll()
	await settle(1.8)
	await viewport(Vector2i(360,692),3.0)
	app.page_scroll.scroll_vertical=0
	for r in range(12):
		for c in range(12):
			var p=app.board.tile(Vector2i(r,c)).get("p")
			if p is Dictionary and p.get("t")=="Q" and p.get("o")=="W":
				await app._select(Vector2i(r,c))
				app._choose_action("scan")
	await settle()
	check(app.board.touch_aim_enabled,"portrait touch aiming active")
	var turn: int=app.view.turnCount
	await touch_cell(Vector2i(7,8))
	check(assist.pending==Vector2i(7,8),"DPR3 screen touch targets correct board square")
	check(app.view.turnCount==turn,"preview does not execute action")
	check(root.get_visible_rect().encloses(assist.confirm.get_global_rect()),"scan confirm within screen")
	await shot("scan-360")
	print("SCAN_GEOMETRY ",JSON.stringify({"app":str(app.size),"window":str(root.size),"visible":str(root.get_visible_rect()),"confirm":str(assist.confirm.get_global_rect()),"footer":str(assist.footer.get_global_rect()),"render":str(root.get_texture().get_image().get_size())}))
	check(root.get_visible_rect().encloses(assist.confirm.get_global_rect()),"settled scan confirm within screen")
	check(assist.footer.get_global_rect().end.x<=app.size.x-7,"scan footer keeps right margin")
	await assist.commit()
	check(int(app.view.turnCount)==turn+1,"confirm executes exactly one scan")
	await app._act({"type":"resign"})
	var replay_id: String=str(app.view.get("replayId",""))
	check(not replay_id.is_empty(),"fixture replay created")
	await app.replay.open(replay_id,app.token)
	await settle()
	check(app.board.size.x>=320,"mobile replay board uses full width")
	await shot("replay-360")
	# Web metrics can briefly vanish when a tab is hidden; retain last usable size.
	var previous=root.content_scale_size
	scaler.apply_css_size(Vector2i.ZERO)
	check(root.content_scale_size==previous,"hidden canvas retains valid size")
	var out=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"\t"));out.close()
	app.queue_free()
	await process_frame
	print("MOBILE_VIEWPORT_CHECKS=",checks," FAILURES=",failures.size())
	quit(0 if failures.is_empty() else 1)
