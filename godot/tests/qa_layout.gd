extends SceneTree
var app
var checks := 0
var failures: Array[String] = []
var observations: Array = []
func _initialize():run.call_deferred()
func check(ok: bool, text: String):
	checks+=1;print(("PASS: " if ok else "FAIL: ")+text)
	if not ok:failures.append(text)
func settle():
	app._layout();await create_timer(.18).timeout;app._layout();await create_timer(.18).timeout
func shot(name: String):
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func visible_window() -> Window:
	for c in app.get_children():
		if c is Window and c.visible and not c.is_queued_for_deletion():return c
	return null
func click_at(window: Window, point: Vector2):
	var root_point:Vector2=Vector2(window.position)+point
	var motion:=InputEventMouseMotion.new();motion.position=root_point;motion.global_position=root_point
	root.push_input(motion,true);await process_frame
	for down in [true,false]:
		var event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=root_point;event.global_position=root_point
		root.push_input(event,true);await process_frame
	await create_timer(.35).timeout
func run():
	root.size=Vector2i(1440,900);app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app);await create_timer(.4).timeout
	for c in app.get_children():
		if c is Timer and c.name!="ChatReadVisibility":c.stop()
	app.audio.enabled=false
	var lobby=app.ui_shell.lobby_home
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		for dims in [Vector2i(1440,900),Vector2i(1120,760),Vector2i(390,844),Vector2i(320,740),Vector2i(844,390),Vector2i(915,412),Vector2i(900,600)]:
			root.size=dims
			await settle();app.page_scroll.scroll_vertical=0;await process_frame
			var preview_before:Rect2=lobby.preview_board.get_global_rect()
			for section in ["computer","practice","options"]:
				app.page_scroll.scroll_vertical=0;lobby.select_section(section,false);await settle()
				if dims.x>=800:check(lobby.preview_board.get_global_rect().position.distance_to(preview_before.position)<.5,"accordion keeps board position "+str([dims,section,light]))
				if dims.y>=760:
					if dims.x>=1120:check(not app.page_scroll.get_v_scroll_bar().visible,"normal PC stays scroll-free "+str([dims,section,light]))
				if dims==Vector2i(1120,760) and section=="practice":
					print("PC_GEOMETRY ",app.page_scroll.get_rect()," lobby ",lobby.get_rect()," min ",lobby.get_combined_minimum_size()," account ",lobby.headers.account.get_global_rect()," pane ",lobby.panes.practice.get_rect())
					await shot("short-desktop-practice-"+("light" if light else "dark"))
				var offscreen:bool=lobby.headers.account.get_global_rect().end.y>app.page_scroll.get_global_rect().end.y
				check(not offscreen or app.page_scroll.get_v_scroll_bar().visible,"overflow has usable scroll "+str([dims,section,light]))
				app.page_scroll.ensure_control_visible(lobby.headers.account);await create_timer(.2).timeout
				check(app.page_scroll.get_global_rect().encloses(lobby.headers.account.get_global_rect()),"last menu reachable "+str([dims,section,light]))
				if dims==Vector2i(844,390) and section=="practice":await shot("landscape-lobby-"+("light" if light else "dark"))
				if dims==Vector2i(1440,900) and section=="computer":await shot("desktop-lobby-"+("light" if light else "dark"))
	# Rotate while a mission and its action menu are already open.
	root.size=Vector2i(844,390);await settle();app._tutorial();await settle()
	var win:Window=visible_window();var lesson=win.get_child(0)
	lesson._tap(lesson.ORIGINS[0]);await create_timer(.4).timeout
	root.size=Vector2i(390,844);await settle()
	check(win.size.x<=366 and win.position.x>=0 and win.position.x+win.size.x<=390,"mission fits after landscape to portrait")
	check(lesson.step==0 and lesson.chosen and lesson.action_menu.opened,"rotation preserves selected mission piece")
	for button in lesson.action_menu.buttons:check(Rect2(Vector2.ZERO,lesson.action_menu.size).encloses(button.get_rect()),"rotated action icon stays on board")
	await shot("tutorial-rotated-portrait")
	# Select the attack using actual control input, then click the board target.
	await click_at(win,lesson.action_menu.buttons[0].get_global_rect().get_center())
	check(lesson.armed,"rotated mission action accepts input")
	await click_at(win,lesson.board.global_position+lesson.board.center(lesson.TARGETS[0]))
	check(lesson.step==1,"rotated mission board advances through input")
	root.size=Vector2i(844,390);await settle()
	check(win.size.y<=326 and win.position.y>=32 and win.position.y+win.size.y<=390,"mission fits after portrait to landscape")
	lesson.scroll.scroll_vertical=0;await create_timer(.2).timeout
	await click_at(win,lesson.board.global_position+lesson.board.center(lesson.ORIGINS[1]))
	await click_at(win,lesson.action_menu.buttons[2].get_global_rect().get_center())
	check(lesson.chosen and lesson.armed,"landscape mission action accepts input after reverse rotation")
	await click_at(win,lesson.board.global_position+lesson.board.center(lesson.TARGETS[1]))
	check(lesson.step==2,"landscape mission target advances through input")
	lesson.scroll.ensure_control_visible(lesson.panel.get_child(lesson.panel.get_child_count()-1));await create_timer(.3).timeout
	check(lesson.scroll.get_global_rect().encloses(lesson.panel.get_child(lesson.panel.get_child_count()-1).get_global_rect()),"mission bottom action is reachable after rotation")
	await shot("tutorial-rotated-landscape")
	await click_at(win,Vector2(win.size.x-16,-16))
	check(not is_instance_valid(win) or not win.visible,"landscape mission title close accepts pointer input")
	app._tutorial();await settle();root.size=Vector2i(390,844);await settle();win=visible_window()
	var escape=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;win.push_input(escape,true);await create_timer(.4).timeout
	check(not is_instance_valid(win) or not win.visible,"portrait mission ESC close remains reachable")
	# Obtain a real saved replay, preserving its original notation payload.
	root.size=Vector2i(1440,900)
	var fixture:Dictionary=await app.api.request("/test-focus",{})
	if not fixture.has("room"):check(false,"fixture network available");finish();return
	app._enter(fixture);await app._poll();await create_timer(1.8).timeout;await app._act({"type":"resign"})
	await app.replay.open(str(app.view.replayId),app.token)
	var replay=app.replay;var original:String=JSON.stringify(replay.data)
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme();replay.show_frame()
		for dims in [Vector2i(1440,900),Vector2i(1120,760),Vector2i(390,844),Vector2i(320,740),Vector2i(844,390),Vector2i(915,412),Vector2i(900,600)]:
			root.size=dims;await settle();app.page_scroll.ensure_control_visible(replay.bar_panel);await create_timer(.2).timeout
			check(app.page_scroll.get_global_rect().encloses(replay.bar_panel.get_global_rect()),"whole replay card remains reachable "+str([dims,light]))
			check(replay.transport_center.get_children()==[replay.previous_event,replay.previous_button,replay.play_button,replay.next_button,replay.next_event],"five-button order retained "+str([dims,light]))
			for button in replay.transport_center.get_children():
				var content:Control=button.get_meta("content")
				check(button.size.x>=44 and button.size.y>=44,"replay touch size "+str([dims,light,button.accessibility_name]))
				check(content.get_combined_minimum_size().x<=button.size.x+.1 and content.get_combined_minimum_size().y<=button.size.y+.1,"replay label/icon fit "+str([dims,light,button.accessibility_name]))
			if dims==Vector2i(844,390):await shot("landscape-replay-controls-"+("light" if light else "dark"))
			if dims==Vector2i(1440,900):await shot("desktop-replay-"+("light" if light else "dark"))
	var formatter=preload("res://features/move_record_chip.gd")
	for pair in [["resign","기권"],["23. resign","23. 기권"],["timeout","시간 초과"],["disconnect","접속 종료"],["B@c5","B@c5"],["Rxd6","Rxd6"]]:
		check(formatter.display_notation(pair[0])==pair[1],"notation display "+pair[0])
	replay.seek(replay.data.frames.size()-1);await settle()
	check(replay._frame_title(replay.index).contains("기권") and not replay._frame_title(replay.index).contains("resign"),"frame title uses translated action")
	var translated_chip:bool=false
	for chip in replay.move_chips:
		if chip.visible and chip.get_meta("notation").text=="기권":translated_chip=true
	check(translated_chip,"replay chip uses translated action")
	check(JSON.stringify(replay.data)==original,"display leaves saved replay payload unchanged")
	root.size=Vector2i(1440,900);await settle();await shot("replay-korean-events")
	finish()
func finish():
	var f=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close()
	print("QA_LAYOUT_CHECKS=",checks," FAILURES=",failures.size())
	quit(1 if not failures.is_empty() else 0)
