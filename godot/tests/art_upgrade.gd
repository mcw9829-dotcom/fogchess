extends SceneTree
var app: Control
var checks := 0
var failures: Array[String] = []
var shots: Array = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ")+label)
	if not ok: failures.append(label)

func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.35).timeout
	await process_frame
	RenderingServer.force_draw(false)
	var folder := OS.get_environment("FOG_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
	shots.append(name)

func theme(light: bool) -> void:
	app.prefs.set_value("settings","light",light)
	app._apply_theme()

func choose(kind: String, action: String) -> void:
	app._clear_selection()
	for r in range(12):
		for c in range(12):
			var p=app.board.tile(Vector2i(r,c)).get("p")
			if p is Dictionary and p.get("t")==kind and p.get("o")=="W":
				await app._select(Vector2i(r,c))
				app._choose_action(action)
				return

func touch(cell: Vector2i, pressed: bool, index: int=0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = app.board.center(cell)
	event.pressed = pressed
	app.board._gui_input(event)
	await process_frame

func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.4).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	app.prefs.set_value("settings","lobby_music",false)
	app._message("")
	var assist = app.ui_shell.aim_assist
	for light in [false,true]:
		theme(light)
		app._help()
		await process_frame
		var rich: Array = app.find_children("*","RichTextLabel",true,false)
		check(not rich.is_empty(),"help contains rich text")
		var colors: Dictionary = app.ui_components._palette()
		check(rich.all(func(label): return label.get_theme_color("default_color").is_equal_approx(colors.text)),"rich text follows theme "+str(light))
		await shot("help-light" if light else "help-dark")
		for child in app.get_children():
			if child is Window: child.hide(); child.queue_free()
		await process_frame
	theme(false)
	await app._join({})
	await app.api.request("/join",{"room":app.room,"name":"상대 플레이어"})
	await app._poll()
	for width in [390,320]:
		root.size = Vector2i(width,844)
		app._layout()
		app.page_scroll.scroll_vertical = 0
		await create_timer(.3).timeout
		check(assist.ready_action.is_visible_in_tree(),"mobile ready visible "+str(width))
		check(root.get_visible_rect().encloses(assist.ready_action.get_global_rect()),"mobile ready inside viewport "+str(width))
		check(app.board.get_global_rect().end.y<assist.footer.get_global_rect().position.y,"footer does not cover board "+str(width))
		await shot("setup-mobile-"+str(width))
	await assist._ready_pressed()
	check(app.view.get("ready",false),"mobile ready submits existing server action")
	await shot("setup-mobile-ready")
	await assist._ready_pressed()
	check(not app.view.get("ready",false),"mobile cancel-ready works")
	root.size = Vector2i(1280,900)
	app._layout()
	await create_timer(.2).timeout
	check(app.ready_button.is_visible_in_tree() and not assist.footer.visible,"desktop setup preserved")
	var data: Dictionary = await app.api.request("/test-focus",{})
	app._enter(data)
	await app._poll()
	app._message("")
	await choose("R","barrage")
	app.board.hover = app.board.selected+Vector2i(-1,0)
	await create_timer(.2).timeout
	var friends: Array = app.board.targeting.friendly_in_lane(app.board.hover)
	check(not friends.is_empty(),"rook marks friendly unit in selected lane")
	check(friends.all(func(cell): return app.board.tile(cell).p.o==app.view.yourColor),"warning uses only public friendly identities")
	check(assist.desktop_hint.text.contains("아군"),"rook risk appears in action card")
	check(not app.board.touch_aim_enabled,"desktop click path unchanged")
	await shot("rook-aim")
	await choose("B","fire")
	app.board.hover = Vector2i(4,8)
	await shot("bishop-valid")
	check(is_equal_approx(app.board.targeting.reticle_turn_angle(12.0),TAU),"approved twelve-second outward rotation preserved")
	check(is_zero_approx(app.board.targeting.reticle_turn_angle(24.0)),"approved twenty-four-second loop preserved")
	await choose("Q","scan")
	app.board.hover = app.board.selected+Vector2i(-4,1)
	await create_timer(.1).timeout
	check(assist.tactical_text().contains("4칸"),"scan shows true four-cell footprint")
	await shot("queen-valid")
	var saved_targets: Array = app.board.targets.duplicate(true)
	app.board.targets = [[11,10],[11,11]]
	app.board.hover = Vector2i(11,10)
	check(assist.tactical_text()=="k12–l12 · 2칸 감시","scan board edge two cells")
	app.board.hover = Vector2i(11,11)
	check(assist.tactical_text()=="l12 · 1칸 감시","scan corner one cell")
	app.board.flip = true
	check(assist.tactical_text()=="l12 · 1칸 감시","coordinates independent of screen flip")
	app.board.flip = false
	app.board.targets = saved_targets
	root.size = Vector2i(390,844)
	app._layout()
	await create_timer(.2).timeout
	check(app.board.touch_aim_enabled,"mobile ability uses touch preview")
	var target := Vector2i(7,8)
	check(app.board.contains(app.board.targets,target),"server permits test scan target")
	var turn: int = app.view.turnCount
	# Exercise the viewport dispatch too, including the engine's mouse emulation.
	Input.emulate_mouse_from_touch = true
	for pressed in [true,false]:
		var routed := InputEventScreenTouch.new()
		routed.position = app.board.global_position+app.board.center(target)
		routed.pressed = pressed
		Input.parse_input_event(routed)
		await process_frame
	check(assist.pending==target and app.view.turnCount==turn,"viewport touch routes to preview without an action")
	assist.clear_pending()
	await touch(target,true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = app.board.center(Vector2i(7,7))
	app.board._gui_input(drag)
	check(assist.pending==Vector2i(7,7),"touch drag updates preview")
	await touch(target,false)
	var mouse := InputEventMouseButton.new()
	mouse.device = InputEvent.DEVICE_ID_EMULATION
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = app.board.center(target)
	mouse.pressed = true
	app.board._gui_input(mouse)
	mouse.pressed = false
	app.board._gui_input(mouse)
	check(app.view.turnCount==turn and not app.busy,"touch plus emulated mouse never submits preview")
	check(assist.pending==target and not assist.confirm.disabled,"release keeps target until explicit confirm")
	await shot("scan-touch-390")
	assist.clear_pending()
	check(assist.pending.x<0 and app.view.turnCount==turn,"cancel preview spends no turn")
	await touch(target,true)
	var canceled := InputEventScreenTouch.new()
	canceled.position = app.board.center(target)
	canceled.canceled = true
	app.board._gui_input(canceled)
	check(assist.pending.x<0,"canceled touch clears preview")
	await touch(target,true)
	await touch(Vector2i(6,8),true,1)
	check(assist.pending==target,"second finger cannot replace active aim")
	await touch(target,false)
	assist.clear_pending()
	await touch(Vector2i(0,0),true)
	await touch(Vector2i(0,0),false)
	check(assist.confirm.disabled,"invalid raw target cannot be confirmed")
	await assist.commit()
	check(app.view.turnCount==turn,"invalid clamped preview does not fire")
	await touch(target,true)
	await touch(target,false)
	app._choose_action("move")
	assist.refresh()
	check(assist.pending.x<0,"changing action clears stale target")
	app._choose_action("scan")
	assist.refresh()
	await touch(target,true)
	await touch(target,false)
	app.view.turnCount = turn+1
	assist.refresh()
	check(assist.pending.x<0,"turn change invalidates preview")
	app.view.turnCount = turn
	root.size = Vector2i(320,844)
	app._layout()
	await create_timer(.2).timeout
	await touch(target,true)
	await touch(target,false)
	await shot("scan-touch-320")
	check(root.get_visible_rect().encloses(assist.confirm.get_global_rect()),"320px confirm stays inside viewport")
	await assist.commit()
	check(int(app.view.turnCount)==turn+1,"explicit confirmation commits exactly one action")
	check(assist.pending.x<0,"confirmed action clears pending preview")
	root.size = Vector2i(1280,900)
	app._layout()
	app.view.phase = "over"
	for winner in ["W","B","draw"]:
		app.view.winner = winner
		for light in [false,true]:
			theme(light)
			app._render()
			check(app.result_label.get_theme_color("font_color").r>.9,"result title on dark surface "+winner+str(light))
			var labels: Array = app.result_actions.find_children("*","Label",true,false)
			check(labels.all(func(label): return label.get_theme_color("font_color").r>.9),"dynamic result notes on dark surface "+winner+str(light))
			if light: await shot("result-"+winner+"-light")
	var output := FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":shots},"\t"))
	output.close()
	app.queue_free()
	await process_frame
	print("ART_UPGRADE_COMPLETE="+str(checks)+" FAIL="+str(failures.size()))
	quit(0 if failures.is_empty() else 1)

