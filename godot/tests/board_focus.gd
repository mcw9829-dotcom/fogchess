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
	await app._select(Vector2i(5,8))
	check("상대에게 위치가 보이는 중" in app.action_hint.text,"ordinary sight exposure is explained for the selected knight")
	check("적 시야에 노출" in app.self_line.text,"footer summarizes all exposed own pieces without a false countdown")
	await capture("exposure_notice")
	var exposed_cell := Vector2i(5,8)
	var original_badge_flip: bool = app.board.flip
	for flipped in [false,true]:
		app.board.flip = flipped
		var tile_size: float = app.board.geometry().size.x/12.0
		var badge_at: Vector2 = app.board.center(exposed_cell)+Vector2(tile_size*.3,-tile_size*.3)
		check(app.board.get_tooltip(badge_at)=="상대에게 위치가 보이는 중입니다.","exposure badge tooltip follows board orientation "+str(flipped))
		check(app.board.get_tooltip(app.board.center(exposed_cell)).is_empty(),"piece center does not trigger badge tooltip")
		var exposures: Array = app.board.view.exposed
		app.board.view.exposed = []
		check(app.board.get_tooltip(badge_at).is_empty(),"concealed piece no longer advertises exposure tooltip")
		app.board.view.exposed = exposures
	app.board.flip = original_badge_flip
	check(app.action_details_button.tooltip_text=="기물 능력과 주의사항을 확인합니다.","piece help icon has a one-line explanation")
	if "--capture" in OS.get_cmdline_user_args():
		var motion := InputEventMouseMotion.new()
		var badge_size: float = app.board.geometry().size.x/12.0
		motion.position = app.board.global_position+app.board.center(exposed_cell)+Vector2(badge_size*.3,-badge_size*.3)
		motion.global_position = motion.position
		root.push_input(motion,true)
		await create_timer(.9).timeout
		await capture("exposure_tooltip")
		motion.position = Vector2(4,4)
		motion.global_position = motion.position
		root.push_input(motion,true)
	app._clear_selection()
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
	await capture("stable_baseline")
	var stable_board: Vector2 = app.board.size
	for scenario in ["notice","warning","exposure","opponent","ended"]:
		app._message("요청을 처리하지 못했습니다. 연결을 확인한 뒤 다시 시도해주세요. ".repeat(5) if scenario=="notice" else "")
		app.view["turnSecondsLeft"] = 5 if scenario=="warning" else 26
		app.view["exposed"] = [{"pid":"W_B1","type":"B","remaining":2},{"pid":"W_R1","type":"R","remaining":2}] if scenario=="exposure" else []
		app.view["turn"] = "B" if scenario=="opponent" else "W"
		app.view["phase"] = "over" if scenario=="ended" else "play"
		app._render()
		await capture("stable_"+scenario)
		check(app.board.size.is_equal_approx(stable_board),"board size stays fixed during "+scenario)
	app.view["phase"] = "play"
	app.view["turn"] = "W"
	app._render()
	await app._select(Vector2i(7,5))
	app.moves["canFire"] = false
	app.moves["reloading"] = true
	app.moves["fireCells"] = []
	app.view["reloading"] = [{"pid":"W_B1","type":"B","remaining":1}]
	app.board.view["reloading"] = app.view.reloading
	app.piece_input._show_actions(false)
	app._update_selection_ui()
	check(app.action_menu.buttons[1].disabled and not app.action_menu.buttons[2].disabled,"reload disables only the ability icon and retains movement")
	check("재장전" in app.action_hint.text and "재장전" in app.action_menu.buttons[1].tooltip_text,"reload status explains the disabled ability")
	var reload_flip: bool = app.board.flip
	app.board.view["exposed"] = [{"pid":"W_B1","type":"B","remaining":0}]
	for flipped in [false,true]:
		app.board.flip = flipped
		var cell_size: float = app.board.geometry().size.x/12.0
		var piece_center: Vector2 = app.board.center(Vector2i(7,5))
		check(app.board.get_tooltip(piece_center+Vector2(-cell_size*.3,-cell_size*.3))=="사격 후 내 차례 한 턴 동안 재장전합니다. 이동은 가능합니다.","reload question mark tooltip follows orientation "+str(flipped))
		check(app.board.get_tooltip(piece_center+Vector2(cell_size*.3,-cell_size*.3))=="상대에게 위치가 보이는 중입니다.","simultaneous exposure remains distinct from reload "+str(flipped))
	app.board.flip = reload_flip
	app.board.queue_redraw()
	app._choose_action("fire")
	check(app.mode=="choose","reloading cannot enter firing mode")
	await capture("reloading")
	app._game_menu()
	await capture("menu")
	var match_menu: Window = app.get_node("MatchMenu")
	check(is_instance_valid(match_menu.find_child("ResignMatch",true,false)),"live match menu offers confirmed resignation")
	check(match_menu.find_child("LeaveMatch",true,false).text=="기권 후 나가기","live exit label states the consequence")
	app.view["turnSecondsLeft"] = 9
	app._render()
	check(match_menu.find_child("MenuClock",true,false).text=="00:09","open menu clock updates from the live server view")
	check(match_menu.find_child("MenuClock",true,false).get_theme_color("font_color")==app.clock_label.get_theme_color("font_color"),"menu clock shares low-time emphasis")
	app.view["turnSecondsLeft"] = 26
	app._render()
	var resume_button: Button = match_menu.find_child("ResumeMatch",true,false)
	check(resume_button.get_theme_stylebox("hover").bg_color==Color("#f0d9b5"),"menu hover uses the light board tile color")
	var sound_button: Button = match_menu.find_child("MatchSound",true,false)
	var sound_before: bool = app.audio.enabled
	sound_button.pressed.emit()
	check(app.audio.enabled!=sound_before and sound_button.text==( "효과음: 켜짐" if app.audio.enabled else "효과음: 꺼짐"),"menu audio label reflects the actual setting")
	sound_button.pressed.emit()
	for width in [390,320]:
		root.size = Vector2i(width,844)
		await capture("menu_"+str(width))
		check(match_menu.size.x<=width-24,"match menu fits mobile width "+str(width))
		for button in match_menu.find_children("*","Button",true,false):
			check(button.get_global_rect().end.x<=match_menu.size.x,"menu button fits dialog: "+button.text+" at "+str(width))
			check(button.get_global_rect().end.y<=match_menu.size.y,"menu button is not clipped vertically: "+button.text+" at "+str(width))
	resume_button.pressed.emit()
	await process_frame
	app.view["phase"] = "over"
	app._game_menu()
	await process_frame
	match_menu = app.get_node("MatchMenu")
	check(not is_instance_valid(match_menu.find_child("ResignMatch",true,false)),"finished match menu omits resignation")
	check(match_menu.find_child("LeaveMatch",true,false).text=="나가기","completed games do not imply a resignation")
	check(not match_menu.find_child("MenuClockRow",true,false).visible,"completed menu hides the expired clock")
	match_menu.queue_free()
	await process_frame
	app.view["phase"] = "play"
	app.seat = "spectator"
	app._game_menu()
	await process_frame
	match_menu = app.get_node("MatchMenu")
	check(not is_instance_valid(match_menu.find_child("ResignMatch",true,false)),"spectator menu omits resignation")
	check(match_menu.find_child("LeaveMatch",true,false).text=="관전 나가기","spectator exit is explicitly harmless")
	match_menu.queue_free()
	await process_frame
	app.seat = "W"
	var original_view: Dictionary = app.view.duplicate(true)
	for spec in [{"solo":true},{"bothJoined":false},{"phase":"setup","match":false}]:
		app.view = original_view.duplicate(true)
		app.view.merge(spec,true)
		check(not app.game_session.leave_is_resignation() and app.game_session.leave_label()=="나가기","safe exit keeps its meaning: "+str(spec))
	app.view = original_view
	app.view["reloading"] = []
	for width in [390,320]:
		root.size = Vector2i(width,844)
		await capture("mobile_"+str(width))
		check(app.game.get_global_rect().end.x<=width+1,"match fits mobile width "+str(width))
		check(app.controls_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"mobile avoids nested panel scrolling")
		check(app.match_ui.mobile_actions.visible,"mobile selection summary is visible")
		check(app.match_ui.exposure_summary.visible and "노출" in app.match_ui.exposure_summary.text,"mobile exposure state is independent of clipped player names")
		check(app.match_ui.mobile_actions.get_global_rect().position.y>=app.board.get_global_rect().end.y,"mobile action summary follows the board")
		check(app.match_ui.mobile_actions.get_global_rect().end.y<=root.size.y,"mobile action summary fits the initial viewport")
		check(not app.coach_label.get_parent().get_parent().visible,"mobile avoids duplicate selection cards")
		check("재장전" in app.match_ui.mobile_status.text,"mobile summary preserves reload state")
		var before_selection: Vector2 = app.board.size
		var saved_selection: Dictionary = app.selection.duplicate(true)
		var saved_moves: Dictionary = app.moves.duplicate(true)
		app._clear_selection()
		await process_frame
		check(app.board.size.is_equal_approx(before_selection),"clearing mobile selection does not resize the board")
		app.selection = saved_selection
		app.moves = saved_moves
		app._update_selection_ui()
		app.view["turnSecondsLeft"] = 7
		app.view["oppName"] = "아주긴상대이름을표시하는플레이어"
		app._render()
		await capture("warning_"+str(width))
		check(app.clock_label.get_line_count()==1 and app.turn_meta.get_line_count()==1,"clock remains single-line at "+str(width))
		check(app.warning_label.get_theme_font("font").get_string_size(app.warning_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,app.warning_label.get_theme_font_size("font_size")).x<=app.warning_label.size.x,"mobile low-time warning fits without clipping")
		check(app.ui_shell.match_header.get_global_rect().end.x<=width+1,"warning does not widen mobile layout "+str(width))
		app.page_scroll.scroll_vertical=2000
		await capture("records_"+str(width))
		app.page_scroll.scroll_vertical=0
	root.size = Vector2i(1280,900)
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await capture("light")
	check(app.feed_box.get_child(0).get_theme_stylebox("panel").bg_color==app.ui_components._palette().button,"kill feed recolors with the light theme")
	var feed_row: Node = app.feed_box.get_child(0).get_child(0)
	var method_icon: Control = feed_row.get_child(2).get_child(0)
	var panel_color: Color = app.ui_components._palette().button
	check(contrast_ratio(method_icon.ink,panel_color)>=4.5,"light-theme attack icon has readable contrast")
	check(contrast_ratio(feed_row.get_child(0).get_theme_color("font_color"),panel_color)>=4.5,"light-theme owner label has readable contrast")
	check(not app.match_ui.mobile_actions.visible and app.coach_label.get_parent().get_parent().visible,"desktop selection card returns after resizing")
	app._clear_selection()
	check(not app.selection_icon.get_parent().visible,"empty selection hides the piece header")
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

func linear_channel(value: float) -> float:
	return value/12.92 if value<=0.04045 else pow((value+0.055)/1.055,2.4)

func luminance(color: Color) -> float:
	return .2126*linear_channel(color.r)+.7152*linear_channel(color.g)+.0722*linear_channel(color.b)

func contrast_ratio(a: Color,b: Color) -> float:
	return (maxf(luminance(a),luminance(b))+.05)/(minf(luminance(a),luminance(b))+.05)
