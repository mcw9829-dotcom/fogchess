extends SceneTree
var app: Control
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if value: print("PASS: "+message)
	else: failures+=1; push_error("FAIL: "+message)

func _run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	app._message("")
	await app._select(Vector2i(7,5))
	check(app.mode=="choose" and app.board.targets.is_empty(),"fan opens without executing a move")
	var original_turn: int = app.view.turnCount
	app.action_menu.buttons[1].mouse_entered.emit()
	check(app.mode=="choose" and not app.board.ranges.is_empty(),"hover previews sniper range without selecting action")
	check("저격" in app.coach_label.text,"hover updates the contextual action guide")
	await app._tap(Vector2i(4,8))
	check(app.view.turnCount==original_turn and not app.selection.is_empty(),"preview target click cannot fire before choosing an action")
	app.action_menu.buttons[1].mouse_exited.emit()
	check(app.board.targets.is_empty() and app.board.ranges.is_empty(),"leaving icon clears preview marks")
	app.action_menu.buttons[2].focus_entered.emit()
	check(not app.board.targets.is_empty() and app.mode=="choose","keyboard focus previews movement")
	app.action_menu.buttons[2].focus_exited.emit()
	check(app.board.targets.is_empty(),"keyboard blur clears movement preview")
	app.view["series"] = {"me":1,"opp":1,"complete":false,"final":true}
	app.view["rated"] = true
	app.view["spectatorCount"] = 3
	app.view["turnSecondsLeft"] = 26
	app._render()
	await capture("desktop")
	for viewport_size in [Vector2i(1366,768),Vector2i(1440,1000),Vector2i(1920,1080)]:
		root.size = viewport_size
		app.board.annotations = [[Vector2i(7,5),Vector2i(9,6)],[Vector2i(7,5),Vector2i(9,7)],[Vector2i(6,6),Vector2i(6,6)],[Vector2i(1,1),Vector2i(1,3)]]
		await capture("large_"+str(viewport_size.x))
		var rect: Rect2 = app.board.geometry()
		print("BOARD_SIZE %s: %.0f px control / %.0f px cells" % [viewport_size,app.board.size.x,rect.size.x])
		check(is_equal_approx(rect.size.x,rect.size.y),"square art proportions at "+str(viewport_size))
		check(app.ui_shell.self_panel.get_global_rect().end.y<=root.size.y-15,"board and player footer fit desktop height "+str(viewport_size))
		check(app.game.get_global_rect().end.x<=root.size.x,"sidebar fits desktop width "+str(viewport_size))
		if viewport_size.y>=1000: check(app.board.size.x>700,"large viewport expands beyond old board cap")
		var mapped := true
		var original_flip: bool = app.board.flip
		for flipped in [false,true]:
			app.board.flip = flipped
			for row in range(12):
				for col in range(12):
					var cell := Vector2i(row,col)
					mapped = mapped and app.board.cell_at(app.board.center(cell))==cell
		app.board.flip = original_flip
		check(mapped,"all 144 click targets map correctly in both orientations at "+str(viewport_size))
		check(app.board.fx.size.is_equal_approx(rect.size),"effects follow board geometry at "+str(viewport_size))
	app.board.colorblind = true
	await capture("annotation_colorblind")
	app.board.colorblind = false
	app.board.annotations.clear()
	root.size = Vector2i(1280,900)
	await capture("desktop")
	check(app.match_ui.chrome.get_global_rect().end.y<=app.ui_shell.match_header.get_global_rect().position.y,"app chrome sits above the match content")
	check(app.ui_shell.presence_cell.get_global_rect().position.y>=app.board.get_global_rect().end.y,"spectator count sits under the board")
	check(app.ui_shell.match_header.get_theme_stylebox("panel").get_border_width(SIDE_LEFT)==0,"turn banner has no structural grid border")
	root.size = Vector2i(1120,760)
	await capture("standard")
	check(app.board.get_global_rect().end.y<=root.size.y,"board remains inside standard desktop height")
	app.chat.toggle.pressed.emit()
	app.chat.entry.text = "작성 중인 메시지"
	app.chat.entry.caret_column = 3
	app._render()
	await capture("chat")
	check(app.chat.entry.text=="작성 중인 메시지" and app.chat.entry.caret_column==3,"presentation refresh preserves the chat draft")
	check(app.chat.entry.get_global_rect().end.y<=root.size.y,"expanded chat remains in desktop viewport")
	app.chat.toggle.pressed.emit()
	for width in [390,320]:
		root.size = Vector2i(width,844)
		await capture("mobile_"+str(width))
		check(app.game.get_global_rect().end.x<=width+1,"match fits mobile width "+str(width))
		app.view["turnSecondsLeft"] = 7
		app.view["oppName"] = "아주긴상대이름을표시하는플레이어"
		app._render()
		await capture("warning_"+str(width))
		check(app.clock_label.get_line_count()==1 and app.turn_meta.get_line_count()==1,"clock remains single-line at "+str(width))
		check(app.ui_shell.match_header.get_global_rect().end.x<=width+1,"warning does not widen mobile layout "+str(width))
		app.page_scroll.scroll_vertical=2000
		await capture("records_"+str(width))
		app.page_scroll.scroll_vertical=0
	root.size = Vector2i(1280,900)
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await capture("light")
	check(app.feed_box.get_child(0).get_theme_stylebox("panel").bg_color==app.ui_components._palette().button,"kill feed recolors with the light theme")
	app._clear_selection()
	check(not app.match_ui.selection_reopen.get_parent().visible,"empty selection hides the piece header")
	print("BOARD_FOCUS_FAILURES="+str(failures))
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)

func capture(label: String) -> void:
	await process_frame
	await create_timer(.35).timeout
	if not "--capture" in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://../.dev-data/qa-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("board-focus-"+label+".png"))
