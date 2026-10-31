extends SceneTree
var app: Control
var checks := 0
var failed: Array[String] = []
var captures: Array[String] = []
func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ")+message)
	if not ok: failed.append(message)

func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.15).timeout
	await process_frame
	RenderingServer.force_draw(false)
	var folder := OS.get_environment("FOG_CAPTURE_DIR")
	if folder.is_empty(): return
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
	captures.append(name)

func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	app.prefs.set_value("settings","lobby_music",false)
	app._help()
	await create_timer(.2).timeout
	var window: Window = app.get_node("PieceGuide")
	var guide: Control = window.find_child("FocusedPieceGuide",true,false)
	check(is_instance_valid(guide),"focused guide opens")
	for width in [1280,390,320]:
		root.size = Vector2i(width,900 if width==1280 else 844)
		app._layout()
		await create_timer(.2).timeout
		check(guide.piece_tabs.columns==(6 if width==1280 else 3),"piece selector columns "+str(width))
		check(window.get_visible_rect().encloses(guide.piece_tabs.get_global_rect()),"all piece selectors fit "+str(width))
		check(window.get_visible_rect().encloses(guide.replay.get_global_rect()),"replay control stays visible "+str(width))
		for kind in ["P","N","B","R","Q","K"]:
			guide.select_piece(kind,false)
			await create_timer(.05).timeout
			check(guide.demo.spec.t==kind,"demo uses existing scene "+kind+" / "+str(width))
			check(guide.piece_buttons[kind].button_pressed,"piece selected state "+kind+" / "+str(width))
			check(guide.stage_buttons.ability.disabled==(kind not in ["B","R","Q"]),"ability availability "+kind+" / "+str(width))
			for phase in ["move","attack","ability"]:
				if not guide.demo.has_stage(phase): continue
				guide.select_stage(phase)
				check(guide.demo.running,"stage selection plays "+kind+" / "+phase+" / "+str(width))
				var stage_name: String = {"move":"행마","attack":"공격","ability":"능력"}[phase]
				check(guide.demo.frames.all(func(frame): return frame.get("phase")==stage_name),"stage never plays another phase "+kind+" / "+phase)
				var raw: String = str(guide.spec[{"move":"move","attack":"atk","ability":"abil"}[phase]])
				var expected := raw.replace("<b>","[b]").replace("</b>","[/b]").replace(". ",".\n\n")
				check(guide.rule_body.text==expected,"full original rules preserved "+kind+" / "+phase)
				guide.demo.stop()
				check(not guide.demo.running and guide.demo.index==0,"stop resets only current phase")
			guide.replay.pressed.emit()
			check(guide.demo.running,"replay button starts "+kind)
			guide.demo.stop()
			guide.demo.mouse_entered.emit()
			check(not guide.demo.running,"pointer does not restart explicit playback "+kind)
			if kind in ["B","Q"]:
				guide.select_stage("ability")
				await shot("guide-"+kind+"-"+str(width))
		check(guide.columns.vertical==(width!=1280),"single column on mobile "+str(width))
		if width!=1280:
			guide.body_scroll.scroll_vertical = 500
			await process_frame
			check(window.get_visible_rect().encloses(guide.stage_tabs.get_global_rect()),"stage tabs stay visible while reading "+str(width))
			check(window.get_visible_rect().encloses(guide.piece_tabs.get_global_rect()),"piece tabs stay visible while reading "+str(width))
			guide.body_scroll.scroll_vertical = 0
	root.size = Vector2i(1280,900)
	app._layout()
	guide.select_piece("B",false)
	guide.select_stage("ability")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await create_timer(.2).timeout
	check(guide.rule_body.get_theme_color("default_color").is_equal_approx(app.ui_components._palette().text),"light theme body readable")
	await shot("guide-B-light")
	window.close_requested.emit()
	await create_timer(.5).timeout
	check(not is_instance_valid(window),"close dismisses guide")
	var folder := OS.get_environment("FOG_CAPTURE_DIR")
	if not folder.is_empty():
		DirAccess.make_dir_recursive_absolute(folder)
		var file := FileAccess.open(folder.path_join("guide-checks.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"failures":failed,"captures":captures},"\t"))
		file.close()
	app.queue_free()
	await process_frame
	print("FOCUSED_GUIDE_CHECKS="+str(checks))
	print("FOCUSED_GUIDE_FAILURES="+str(failed.size()))
	quit(0 if failed.is_empty() else 1)
