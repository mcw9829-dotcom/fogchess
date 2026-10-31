extends SceneTree
var app
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)
func overflows_page() -> bool:
	return app.page_scroll.get_child(0).get_combined_minimum_size().y>app.page_scroll.size.y+.5
func close_windows() -> void:
	for child in app.get_children():
		if child is Window: child.hide(); child.queue_free()
	await process_frame
func shot(title: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.35).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(title+".png"))
func run() -> void:
	root.size=Vector2i(1120,760)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.6).timeout
	for node in app.get_children():
		if node is Timer: node.stop()
	app.audio.enabled=false
	app._message("")
	var lobby=app.ui_shell.lobby_home
	for dimensions in [Vector2i(1120,760),Vector2i(900,600),Vector2i(1280,900)]:
		root.size=dimensions
		app.page_scroll.scroll_vertical=0
		app._layout()
		await create_timer(.4).timeout
		check(not app.rail_panel.is_visible_in_tree(),"sidebar hidden "+str(dimensions))
		check(app.page_scroll.get_v_scroll_bar().visible==overflows_page(),"lobby scroll appears only when content exceeds viewport")
		var baseline: Rect2=lobby.preview_board.get_global_rect()
		for key in lobby.ORDER:
			lobby.headers[key].grab_focus()
			lobby.select_section(key)
			var max_drift := 0.0
			var elapsed := 0.0
			while elapsed < .40:
				await process_frame
				elapsed += maxf(.001,app.get_process_delta_time())
				var rect: Rect2=lobby.preview_board.get_global_rect()
				max_drift=maxf(max_drift,rect.position.distance_to(baseline.position))
				max_drift=maxf(max_drift,rect.size.distance_to(baseline.size))
			check(max_drift<.5,"board drift <0.5px / "+str(dimensions)+" / "+key+" / measured "+str(max_drift))
			var menu_rect := Rect2(Vector2(0,0),Vector2(dimensions)-Vector2(0,22))
			check(lobby.actions[key].all(func(b):return b.get_global_rect().end.y<=menu_rect.end.y+1 and b.get_global_rect().position.y>=menu_rect.position.y-1),"expanded actions fit without scrolling / "+key)
			check(lobby.headers.values().all(func(b):return b.get_global_rect().end.y<=dimensions.y-22 and b.get_global_rect().position.y>=22),"all seven menu headers visible / "+str(dimensions)+" / "+key)
			check(app.page_scroll.get_v_scroll_bar().visible==overflows_page(),"scrollbar matches content height / "+str(dimensions)+" / "+key)
			if dimensions.y>=760:check(not app.page_scroll.get_v_scroll_bar().visible,"ordinary desktop remains scroll-free / "+key)
			check(lobby.actions[key].all(func(b):return b.get_global_rect().position.x>=22 and b.get_global_rect().end.x<=lobby.menu_column.get_global_rect().end.x+1),"action widths fit / "+key)
			check(lobby.actions[key].all(func(b):return not b.disabled),"active actions enabled / "+key)
		check(baseline.end.y<dimensions.y-65,"board and caption fit "+str(dimensions))
		lobby.select_section("computer",false)
		await shot("stable-"+str(dimensions.x))
		# Ordinary desktop is fixed; a short overflowing window must be scrollable.
		var menu_before: Rect2 = lobby.headers.computer.get_global_rect()
		var wheel := InputEventMouseButton.new()
		wheel.position = menu_before.get_center()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		root.push_input(wheel)
		await process_frame
		check(app.page_scroll.scroll_vertical>0 if overflows_page() else (lobby.headers.computer.get_global_rect()==menu_before and app.page_scroll.scroll_vertical==0),"wheel follows actual overflow / "+str(dimensions))
		app.page_scroll.scroll_vertical=0;await process_frame
		# Rapid input must leave a single expanded pane and a stationary board.
		for key in ["practice","friends","options","account","computer"]:
			lobby.select_section(key)
			await create_timer(.04).timeout
		await create_timer(.4).timeout
		check(lobby.panes.values().filter(func(p):return p.expanded).size()==1,"rapid switching ends in one pane")
		check(lobby.preview_board.get_global_rect()==baseline,"rapid switching keeps board fixed")
	# All sidebar entry points have moved to real accordion actions.
	for item in [["practice","기물 설명"],["rank","리더보드 · 레이팅 규칙"],["options","피드백 보내기"],["options","패치노트"],["account","로그인 · 회원가입"]]:
		lobby.select_section(item[0],false)
		var matches: Array=lobby.actions[item[0]].filter(func(b):return b.text==item[1])
		check(matches.size()==1,"unique accordion entry / "+item[1])
		if matches.size()!=1: continue
		matches[0].pressed.emit()
		await create_timer(.5).timeout
		check(app.get_children().any(func(n):return n is Window and n.visible),"accordion opens "+item[1])
		await close_windows()
	for item in [["records","리플레이"],["records","대국 관전"],["options","게임 설정"]]:
		lobby.select_section(item[0],false)
		var matches: Array=lobby.actions[item[0]].filter(func(b):return b.text==item[1])
		check(matches.size()==1,"unique accordion entry / "+item[1])
		if matches.size()!=1: continue
		matches[0].pressed.emit()
		await create_timer(.45).timeout
		check(app.subpage.visible and not lobby.backdrop.visible and not app.rail_panel.visible,"subpage opens without lobby background / "+item[1])
		var back: Button=null
		for node in app.subpage.get_children():
			if node is Button and "뒤로" in node.text: back=node
		check(is_instance_valid(back),"back action available / "+item[1])
		if is_instance_valid(back): back.pressed.emit()
		await create_timer(.4).timeout
		check(app.home.visible and lobby.backdrop.visible and not app.rail_panel.visible,"back returns to unified lobby / "+item[1])
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		check(lobby.backdrop.light==light,"background follows theme")
		root.size=Vector2i(1120,760);app._layout()
		lobby.select_section("computer",false)
		await shot("new-home-"+("light" if light else "dark"))
		for key in ["rank","friends","practice","records","account"]:
			lobby.select_section(key,false)
			await shot(key+"-"+("light" if light else "dark"))
		lobby.select_section("options")
		await create_timer(.4).timeout
		await shot("new-options-"+("light" if light else "dark"))
	# Mobile uses one page scroll. Account remains reachable without the old rail.
	for width in [320,390]:
		root.size=Vector2i(width,844);app._layout()
		lobby.select_section("account",false)
		await create_timer(.3).timeout
		check(lobby.find_children("*","ScrollContainer",true,false).is_empty(),"mobile has no nested menu scroll")
		app.page_scroll.ensure_control_visible(lobby.account_action)
		await process_frame
		check(lobby.account_action.get_global_rect().end.y<=844-21,"mobile account reachable "+str(width))
		await shot("mobile-account-"+str(width))
	# Local validation and busy state keep their original behavior.
	root.size=Vector2i(900,600);app._layout()
	lobby.select_section("friends",false)
	lobby.room_code.text=""
	lobby.join_friend()
	await create_timer(.25).timeout
	check(lobby.local_note.visible and lobby.local_note.get_global_rect().end.y<=578,"empty room message fits without scrolling")
	app.busy=true;lobby._sync_state()
	check(lobby.headers.values().all(func(b):return b.disabled),"busy state blocks navigation")
	check(lobby.actions.friends.all(func(b):return b.disabled),"busy state blocks room actions")
	app.busy=false;lobby._sync_state()
	print("LOBBY_CHECKS="+str(checks))
	print("LOBBY_FAILURES="+str(failures))
	app.queue_free();await process_frame;await process_frame
	quit(failures)
