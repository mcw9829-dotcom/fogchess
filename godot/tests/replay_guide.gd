extends SceneTree
var app
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)
	else: print("PASS: "+text)
func shot(name: String) -> void:
	await create_timer(.25).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func settle() -> void:
	app._layout()
	await create_timer(.2).timeout
	app._layout()
	await create_timer(.15).timeout
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-fixture",{"scenario":"piece_N"})
	await app.api.request("/test-brush",{"room":fixture.room})
	app._enter(fixture)
	await app._poll()
	for attempt in range(80):
		if not app.ui_motion.is_transition_busy(): break
		await create_timer(.05).timeout
	var ux = app.game_ux
	for light in [false,true]:
		app.prefs.set_value("settings","light",light)
		app._apply_theme()
		for width in [1280,390,320]:
			root.size = Vector2i(width,900 if width==1280 else 844)
			app.prefs.set_value("settings","practice_tips",true)
			ux.active_tip = "fog"
			ux.displayed_tip = ""
			ux.render_practice()
			await settle()
			check(ux.practice_label.get_theme_font_size("font_size")==18,"guide headline readable "+str([width,light]))
			check(not ux.practice_extra.visible,"exception initially folded "+str([width,light]))
			check(ux.practice_card.size.x<=app.controls.size.x,"guide fits rail "+str([width,light]))
			check(ux.practice_next.size.x>=44 and ux.practice_off.size.x>=44,"guide touch buttons "+str([width,light]))
			if width<600: app.page_scroll.scroll_vertical = int(ux.practice_card.global_position.y)-80
			if width!=320: await shot("guide-%s-%s" % ["desktop" if width==1280 else "mobile","light" if light else "dark"])
			ux.practice_disclosure.pressed.emit()
			await process_frame
			check(ux.practice_extra.visible and "두 번째 칸" in ux.practice_extra.text and "1칸만" in ux.practice_extra.text,"pawn exceptions retained "+str([width,light]))
			ux.render_practice()
			check(ux.practice_extra.visible,"poll preserves open exception "+str([width,light]))
			if width==1280: await shot("guide-expanded-"+("light" if light else "dark"))
	ux.seen_tips.clear()
	for tip in ["reload","exposure"]:
		ux.active_tip = tip
		ux.render_practice()
		check(not ux.practice_extra.visible,"new situation folds previous exception "+tip)
		ux.practice_next.pressed.emit()
		check(ux.seen_tips.has(tip),"acknowledgement tracked "+tip)
	ux.practice_off.pressed.emit()
	check(not ux.practice_card.get_parent().visible and not app.prefs.get_value("settings","practice_tips"),"disable guide hides card and saves preference")
	app.prefs.set_value("settings","practice_tips",true)
	ux.render_practice()
	check(ux.practice_card.get_parent().visible,"guide returns after settings re-enable")
	root.size = Vector2i(1280,900)
	app.page_scroll.scroll_vertical = 0
	await app._select(Vector2i(6,6))
	await app._act({"type":"move","pid":"W_N1","r":4,"c":7})
	await app._act({"type":"resign"})
	if app.view.get("replayId")==null: check(false,"fixture saved replay"); quit(1); return
	await app.replay.open(app.view.replayId,app.token)
	var replay = app.replay
	replay.step(1)
	check(not ux.practice_card.get_parent().visible,"guide hidden in replay")
	check(not replay.tools_box.visible,"report tools initially folded")
	replay.tools_toggle.pressed.emit()
	check(replay.tools_box.visible,"report tools unfold")
	replay.tools_toggle.pressed.emit()
	check(not replay.history_panel.visible,"duplicate move history panel removed")
	check(replay.close_button.get_parent()==app.match_ui.chrome,"one close action in header")
	check(replay.transport_center.get_children()==[replay.previous_event,replay.previous_button,replay.play_button,replay.next_button,replay.next_event],"five buttons follow approved sequence")
	for light in [false,true]:
		app.prefs.set_value("settings","light",light)
		app._apply_theme()
		replay.show_frame()
		for width in [1280,390,320]:
			root.size = Vector2i(width,900 if width==1280 else 844)
			app.page_scroll.scroll_vertical = 0
			await settle()
			check(replay.vision_panel.get_parent()==app.controls,"vision follows board in rail "+str([width,light]))
			check(replay.vision_note.size.y<32,"rail heading remains one line "+str([width,light]))
			check(replay.move_chips[0].get_meta("notation").size.x>=40,"move notation remains visible "+str([width,light]))
			check(replay.transport_center.size.x<=replay.transport.size.x+1,"transport stays inside board width "+str([width,light]))
			var bottom: float = replay.previous_event.global_position.y
			for button in replay.transport_center.get_children():
				check(button.size.x>=44 and button.size.y>=44 and absf(button.global_position.y-bottom)<1,"five-button touch row "+str([button.accessibility_name,width,light]))
			check(app.game.get_global_rect().end.x<=width+1,"game no horizontal overflow "+str([width,light]))
			if width==1280: check(app.board.size.x>=520,"large replay board preserved "+str(light))
			if width!=320: await shot("replay-%s-%s" % ["desktop" if width==1280 else "mobile","light" if light else "dark"])
			if width==390:
				app.page_scroll.scroll_vertical = int(replay.vision_panel.global_position.y)-60
				await shot("replay-mobile-rail-"+("light" if light else "dark"))
	root.size = Vector2i(1280,900)
	app.page_scroll.scroll_vertical = 0
	# Legacy saved replays still work when per-side views were not recorded.
	var old: Dictionary = replay.data.duplicate(true)
	for frame in old.frames: frame.erase("perspectives")
	replay.close()
	replay.open_data(old)
	replay.vision = "W"
	replay.show_frame()
	check(replay.vision=="all" and replay.vision_buttons[1].disabled,"legacy replay falls back to full view")
	replay.close_button.pressed.emit()
	check(not replay.active and not replay.close_button.visible and not replay.tools_panel.visible,"close restores normal controls")
	check(replay.history_panel.visible,"live history returns after close")
	print("DESIGN_CHECKS=",checks)
	print("REPLAY_FAILURES=",failures)
	quit(1 if failures else 0)
