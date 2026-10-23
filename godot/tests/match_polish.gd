extends SceneTree
var app: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error(message)
func settle() -> void:
	await create_timer(.2).timeout
func capture(label: String) -> void:
	await settle()
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := ProjectSettings.globalize_path("res://../.dev-data/match-polish-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var picture := root.get_texture().get_image()
	picture.save_png(folder.path_join(label+".png"))
	var header: Rect2 = app.match_ui.turn_panel.get_global_rect()
	picture.get_region(Rect2i(header)).save_png(folder.path_join(label+"-timer.png"))
	if app.action_menu.opened:
		var at: Rect2 = app.action_menu.buttons[0].get_global_rect().merge(app.action_menu.buttons[1].get_global_rect()).merge(app.action_menu.buttons[2].get_global_rect()).grow(6)
		picture.get_region(Rect2i(at)).save_png(folder.path_join(label+"-ability.png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await settle()
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	await app._select(Vector2i(5,8))
	app.view.turnSecondsLeft = 6
	app._render()
	await settle()
	var glass = app.match_ui.hourglass
	check(glass.visible and glass.active,"live countdown shows an active hourglass")
	var time_before: float = glass.elapsed
	await create_timer(.25).timeout
	check(glass.elapsed!=time_before,"hourglass animates with elapsed frame time")
	check(glass.ink==app.clock_label.get_theme_color("font_color"),"urgent clock and hourglass share their color")
	var actions: Array = app.find_children("*","Button",true,false)
	check(not actions.any(func(button): return button.text=="행동 바꾸기"),"redundant action-change button removed")
	check(not app.coach_label.visible,"generic choose-action headline is absent")
	check(not "기물 옆 아이콘" in app.action_hint.text,"repeated action instructions removed")
	check("상대에게 위치" in app.action_hint.text and app.action_hint.visible,"important exposure state remains visible")
	check(app.action_menu.buttons[1].visible and app.action_menu.buttons[1].disabled and app.action_menu.buttons[1].caption=="능력 없음","no-ability button retains its full caption and disabled state")
	check(app.action_menu.buttons[0].visible and app.action_menu.buttons[2].visible,"attack and movement remain visible for a knight")
	glass.elapsed = 3.05
	glass.queue_redraw()
	await capture("desktop-dark")
	app._choose_action("move")
	check(app.coach_label.visible and "이동" in app.coach_label.text,"target-stage instruction remains visible")
	app.piece_input._invalid_target(Vector2i(0,0))
	check(app.coach_label.visible and "턴 소모 없음" in app.action_hint.text,"invalid-target recovery remains visible")
	app.piece_input._show_actions(false)
	app._update_selection_ui()
	app.replay.active = true
	app._render()
	check(not glass.active,"replay snapshot stops hourglass")
	time_before = glass.elapsed
	await create_timer(.2).timeout
	check(glass.elapsed==time_before,"stopped hourglass does not advance")
	app.replay.active = false
	app.view.turnSecondsLeft = null
	app._render()
	check(not glass.visible and not glass.active,"missing clock hides and stops hourglass")
	app.view.turnSecondsLeft = 6
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	app._render()
	check(glass.ink==app.clock_label.get_theme_color("font_color"),"hourglass follows light-theme urgency color")
	app.piece_input._show_actions(false)
	await capture("desktop-light")
	for width in [390,320]:
		root.size = Vector2i(width,844)
		app._layout()
		app._render()
		await settle()
		var clock: Rect2 = app.clock_label.get_global_rect()
		var hour: Rect2 = glass.get_global_rect()
		check(not clock.intersects(hour),"hourglass and timer never overlap at "+str(width))
		check(app.match_ui.turn_panel.size.x<=root.size.x,"timer fits narrow viewport "+str(width))
		check(app.clock_label.get_line_count()==1,"time stays on one line "+str(width))
		app.piece_input._show_actions(false)
		await settle()
		var buttons = app.action_menu.buttons
		check(not buttons[0].get_rect().intersects(buttons[1].get_rect()) and not buttons[1].get_rect().intersects(buttons[2].get_rect()),"enlarged action buttons do not overlap at "+str(width))
		check(buttons.all(func(button): return Rect2(Vector2.ZERO,app.action_menu.size).encloses(button.get_rect())),"action buttons stay inside board at "+str(width))
		await capture("mobile-"+str(width))
	root.size = Vector2i(1280,900)
	app._layout()
	await app._select(Vector2i(7,5))
	check(app.action_menu.buttons[1].visible and app.action_menu.buttons[1].kind=="fire","selecting a bishop shows its real ability button")
	await capture("bishop-ability")
	app.moves.reloading = true
	app.piece_input._show_actions(false)
	check(app.action_menu.buttons[1].visible and app.action_menu.buttons[1].disabled and app.action_menu.buttons[1].caption=="재장전","temporary reload retains its status button")
	app.game.hide()
	time_before = glass.elapsed
	await create_timer(.2).timeout
	check(not glass.is_processing() and glass.elapsed==time_before,"hidden match stops animation work")
	app.queue_free()
	await process_frame
	print("MATCH_POLISH_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
