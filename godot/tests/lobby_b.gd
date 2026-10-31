extends SceneTree
var app
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)
func shot(title: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.35).timeout
	await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(title+".png"))
func settle_commands() -> void:
	# Commands and the visible transition finish asynchronously. Fixed sleeps can
	# attempt another join while input is still intentionally locked.
	var deadline := Time.get_ticks_msec()+8000
	await process_frame
	while app.busy or app.polling or app.ui_motion.is_transition_busy():
		if Time.get_ticks_msec() >= deadline:
			check(false,"commands and transition settle within 8 seconds")
			return
		await process_frame
	await process_frame

func run() -> void:
	root.size=Vector2i(1280,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	app._message("")
	var lobby=app.ui_shell.lobby_home
	check(lobby.is_visible_in_tree(),"B lobby visible")
	check(not app.landing.is_visible_in_tree(),"old card list hidden")
	check(lobby.selected=="computer","computer section starts expanded")
	lobby.headers.rank.grab_focus()
	var enter := InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=true
	Input.parse_input_event(enter); await process_frame
	enter=InputEventKey.new(); enter.keycode=KEY_ENTER; enter.pressed=false
	Input.parse_input_event(enter); await process_frame
	check(lobby.selected=="rank","native keyboard activates menu header")
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		lobby.select_section("computer",false)
		await shot("home-light" if light else "home-dark")
		for key in lobby.ORDER:
			lobby.headers[key].pressed.emit()
			if lobby.selected!=key: lobby.headers[key].pressed.emit()
			await create_timer(.35).timeout
			check(lobby.selected==key,"menu expands "+key+" theme "+str(light))
			check(lobby.ORDER.all(func(other):return lobby.panes[other].expanded==(other==key)),"only one submenu open "+key)
			check(app.room.is_empty(),"expanding never joins a match "+key)
			check(lobby.actions[key].all(func(b):return b.is_visible_in_tree() and not b.disabled),"active submenu usable "+key)
			await shot(key+("-light" if light else "-dark"))
		lobby.select_section("friends",false)
		lobby.room_code.text=""
		await lobby.join_friend()
		check(app.room.is_empty() and lobby.local_note.visible,"empty friend code explains inline without joining")
		lobby.select_section("computer",false)
		lobby.level_buttons[2].pressed.emit()
		check(app.level.selected==2,"difficulty selection preserved")
		lobby.select_section("friends",false)
		lobby.select_section("computer",false)
		check(app.level.selected==2,"difficulty survives menu switch")
	app.prefs.set_value("settings","light",false);app._apply_theme()
	for width in [390,320,900,1280]:
		root.size=Vector2i(width,844);app._layout()
		for key in lobby.ORDER:
			lobby.select_section(key,false)
			await create_timer(.25).timeout
			check(lobby.size.x <= width,"lobby fits width "+str(width)+" / "+key)
			check(lobby.headers.values().all(func(b): return b.get_global_rect().end.x<=width),"headers not clipped "+str(width)+" / "+key)
			check(lobby.size.x<=app.page_scroll.size.x+1,"lobby preserves horizontal page padding "+str(width)+" / "+key)
			# The responsive lobby uses 16px phone padding and 22px desktop padding.
			# Check both physical edges, not the obsolete desktop-only right inset.
			var expected_padding := 16.0 if width<=760 else 22.0
			var page_rect: Rect2 = app.page_scroll.get_global_rect()
			check(absf(page_rect.position.x-expected_padding)<=1 and absf(width-page_rect.end.x-expected_padding)<=1,"page preserves symmetric responsive margins "+str(width)+" / "+key)
			check(lobby.actions[key].all(func(b):return b.get_global_rect().position.x>=page_rect.position.x-1 and b.get_global_rect().end.x<=page_rect.end.x+1),"expanded actions fit horizontal page bounds "+str(width)+" / "+key)
			if width<=390:
				check(not lobby.preview_column.visible,"mobile prioritizes controls "+str(width))
				check(lobby.actions[key].all(func(b):return b.get_global_rect().size.y>=44),"mobile action targets remain 44px")
				await shot("mobile-"+str(width)+"-"+key)
	lobby.select_section("computer",false)
	app.busy=true;lobby._sync_state()
	check(lobby.headers.values().all(func(b): return b.disabled),"busy prevents duplicate menu commands")
	check(lobby.actions.computer.all(func(b): return b.disabled),"busy disables start")
	app.busy=false;lobby._sync_state()
	lobby.select_section("rank",false)
	check(lobby.rank_action.text=="로그인하고 매칭","guest rank login label")
	lobby.rank_action.pressed.emit()
	await create_timer(.2).timeout
	check(app.room.is_empty() and app.get_children().any(func(n):return n is Window and n.visible),"guest rank opens existing login")
	for node in app.get_children():
		if node is Window: node.hide();node.queue_free()
	await process_frame
	# Existing server path, with real isolated room creation and readiness data.
	lobby.select_section("friends",false)
	lobby.actions.friends[0].pressed.emit()
	await settle_commands()
	check(not app.room.is_empty() and app.view.get("phase")=="setup","friend create enters existing setup flow")
	check(not lobby.is_visible_in_tree(),"lobby hides during match")
	app._return_home()
	await settle_commands()
	check(lobby.is_visible_in_tree(),"return home restores lobby")
	var host: Dictionary = await app.api.request("/join",{"name":"친구"})
	lobby.select_section("friends",false)
	lobby.room_code.text=" "+str(host.room).to_lower()+" "
	await lobby.join_friend()
	var expected_seat := "B" if host.color=="W" else "W"
	check(host.color in ["W","B"],"friend host receives a playing seat")
	check(app.room==host.room and app.seat==expected_seat and app.view.get("phase")=="setup","friend code trims and joins opposite seat / host "+str(host.color))
	check(app.code_field.text==str(host.room),"friend code is normalized before join")
	await settle_commands()
	app._return_home();await settle_commands()
	lobby.select_section("computer",false)
	lobby.level_buttons[1].pressed.emit()
	lobby.actions.computer[3].pressed.emit()
	await settle_commands()
	check(app.view.get("bot",false) and "normal" in str(app.view.get("oppName","")),"computer start carries selected difficulty")
	app._return_home();await settle_commands()
	lobby.select_section("practice",false)
	lobby.actions.practice[1].pressed.emit()
	await settle_commands()
	check(app.view.get("solo",false) and app.seat=="solo","practice starts existing solo mode")
	app._return_home();await settle_commands()
	# Collapse and rapid reversal settle cleanly.
	lobby.select_section("rank");lobby.select_section("practice");lobby.select_section("friends");lobby.select_section("")
	await create_timer(.4).timeout
	check(lobby.ORDER.all(func(k):return not lobby.panes[k].body.visible and is_zero_approx(lobby.panes[k].custom_minimum_size.y)),"rapid switching leaves no ghost submenu")
	lobby.select_section("computer",false)
	app._layout()
	await shot("final-home")
	print("LOBBY_CHECKS="+str(checks))
	print("LOBBY_FAILURES="+str(failures))
	app.queue_free();await process_frame;await process_frame
	quit(failures)
