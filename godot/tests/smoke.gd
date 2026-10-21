extends SceneTree
var app: Control
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
	else: print("PASS: " + message)

func _run() -> void:
	root.size = Vector2i(1280,720)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	check(app.home.visible,"home created")
	await create_timer(.3).timeout
	await capture("home")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(390,844)
		await capture("home_mobile")
		root.size = Vector2i(1280,720)
		await process_frame
	app._settings()
	check(app.subpage.visible and not app.home.visible,"settings is a page, not a popup")
	await capture("settings")
	var theme_buttons: Array = []
	for button in app.subpage.find_children("*","Button",true,false):
		if button.has_meta("theme_choice"): theme_buttons.append(button)
	theme_buttons[1].pressed.emit()
	check(app.prefs.get_value("settings","light",false) and theme_buttons[1].button_pressed and not theme_buttons[0].button_pressed,"theme choice applies and marks only the selected option")
	var colorblind: CheckButton = app.subpage.find_child("Setting_colorblind",true,false)
	colorblind.button_pressed = true
	check(app.board.colorblind and app.board.signal_color("move")==Color("009fca"),"colorblind switch applies the preview palette to the board")
	for card in app.subpage.get_children():
		if card.get_meta("settings_card",false):
			check(card.get_theme_stylebox("panel").bg_color==app.ui_components._palette().surface,"theme switch refreshes existing setting card backgrounds")
	await capture("settings_light")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(390,844)
		await capture("settings_mobile")
		root.size = Vector2i(1280,720)
	colorblind.button_pressed = false
	theme_buttons[0].pressed.emit()
	app._navigation_home()
	app._friend_menu()
	check(app.subpage.visible,"friend join page opens")
	await capture("friend")
	app._navigation_home()
	app._help()
	await process_frame
	var demos: Array = []
	for node in app.find_children("*","Control",true,false):
		if node.get_script()==preload("res://guide_demo(설명용 시연).gd"): demos.append(node)
	demos[0].start()
	check("재생 중" in demos[0].host.find_child("PlaybackStatus",true,false).text,"guide card announces playback")
	demos[1].start()
	check(not demos[0].running and demos[0].host.find_child("PlaybackStatus",true,false).text=="시연 대기","switching guide cards clears the previous highlight and status")
	await capture("guide")
	demos[2].start()
	demos[2].apply_frame(demos[2].frames.size()-1)
	check("능력" in demos[2].host.find_child("PlaybackStatus",true,false).text,"guide status follows the demonstrated phase")
	if "--capture" in OS.get_cmdline_user_args():
		await close_windows()
		root.size = Vector2i(390,844)
		await process_frame
		app._help()
		await capture("guide_mobile")
		await close_windows()
		root.size = Vector2i(1280,720)
		await process_frame
	for child in app.get_children():
		if child is Window: child.queue_free()
	await process_frame
	app._intro(0)
	await capture("intro")
	for child in app.get_children():
		if child is Window: child.queue_free()
	await process_frame
	await preload("res://tests/remaining.gd").new().run(app,self,check)
	app._tutorial()
	await process_frame
	for child in app.get_children():
		if child is Window:
			var tutorial: Control = child.get_child(0)
			check(tutorial.board.tile(Vector2i(4,7)).get("p")==null,"tutorial bush enemy initially hidden")
			tutorial._tap(Vector2i(6,2))
			tutorial.action_menu.buttons[2].pressed.emit()
			tutorial._tap(Vector2i(4,1))
			check(tutorial.board.tile(Vector2i(4,7)).get("p") is Dictionary,"tutorial connected bush reveals distant enemy")
			tutorial._tap(Vector2i(6,4))
			tutorial.action_menu.buttons[1].pressed.emit()
			tutorial._tap(Vector2i(1,5))
			tutorial._tap(Vector2i(5,2))
			tutorial.action_menu.buttons[1].pressed.emit()
			tutorial._tap(Vector2i(1,5))
			check(tutorial.step==3,"guided tutorial completes")
			child.queue_free()
	await process_frame
	app._account()
	await capture("login")
	for child in app.get_children():
		if child is Window and child.visible:
			for button in child.find_children("*","Button",true,false):
				if button.text=="회원가입": button.pressed.emit(); break
	await process_frame
	for child in app.get_children():
		if child is Window and child.visible:
			var fields: Array = child.find_children("*","LineEdit",true,false)
			if fields.size()==2:
				fields[0].text="FormUser"
				fields[1].text="FormPass123!"
				for button in child.find_children("*","Button",true,false):
					if button.get_meta("auth_submit",false): button.pressed.emit(); break
	for attempt in range(100):
		if not app.session.is_empty(): break
		await create_timer(.05).timeout
	await process_frame
	check(not app.session.is_empty(),"signup form establishes session")
	var recovery_visible := false
	for child in app.get_children():
		if child is Window:
			if child.title.begins_with("복구 코드") and child.visible: recovery_visible=true
			child.queue_free()
	check(recovery_visible,"signup form hands off to recovery dialog")
	await process_frame
	await preload("res://tests/fidelity.gd").new().run(app,self,check)
	await preload("res://tests/admin_flow.gd").new().run(app,self,check)
	app._bot_menu()
	await process_frame
	await capture("difficulty")
	var difficulty_found := false
	for button in app.subpage.find_children("*","Button",true,false):
		if button.get_meta("action_title","")=="쉬움":
			difficulty_found = true
			button.pressed.emit()
	check(difficulty_found,"original-style difficulty card is actionable")
	for attempt in range(100):
		if app.view.get("phase")=="setup": break
		await create_timer(.05).timeout
	check(app.view.get("phase")=="setup","bot setup loaded")
	check(not app.subpage.visible and app.game.visible,"difficulty selection opens game page")
	check(app.view.get("grid",[]).size()==12,"12x12 server board")
	check(not app.chat.card.get_parent().visible,"bot game hides the entire unavailable chat panel")
	await capture("setup")
	await app._select(Vector2i(11,2))
	await app._tap(Vector2i(11,3))
	check(app.board.tile(Vector2i(11,3)).get("p",{}).get("t")=="R","setup swaps own pieces")
	await app._act({"type":"autoplace","mode":"default"})
	await app._act({"type":"ready","value":true})
	check(app.view.get("phase")=="play","ready starts actual game")
	await app._select(Vector2i(10,2))
	check(not app.moves.get("moves",[]).is_empty(),"legal moves loaded")
	check(app.action_menu.opened and app.board.targets.is_empty(),"piece selection opens action fan before showing targets")
	check(app.action_menu.buttons[1].disabled,"pawn has no active special ability")
	await create_timer(.35).timeout
	await capture("action_menu")
	app._choose_action("move")
	check(not app.action_menu.opened and not app.board.targets.is_empty(),"movement icon closes fan and shows legal destinations")
	if not app.moves.get("moves",[]).is_empty():
		var target: Array = app.moves.moves[0]
		await app._tap(Vector2i(int(target[0]),int(target[1])))
	check(int(app.view.get("turnCount",0))>=2,"human move and AI response")
	await capture("play")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(390,844)
		await process_frame
		await process_frame
		await capture("mobile")
		var original_view: Dictionary = app.view.duplicate(true)
		app.view["oppName"] = "이름이아주긴상대플레이어"
		app.view["series"] = {"me":1,"opp":1,"complete":false,"final":true}
		app.view["turn"] = app.view.get("yourColor")
		app.view["turnSecondsLeft"] = 7
		app._render()
		await capture("header_warning_mobile")
		root.size = Vector2i(320,700)
		await capture("header_compact")
		check(app.ui_shell.match_header.get_global_rect().end.x<=root.size.x,"compact header keeps menus and audience inside viewport")
		app.prefs.set_value("settings","light",true)
		app._apply_theme()
		await capture("header_light")
		app.prefs.set_value("settings","light",false)
		app.view = original_view
		app._apply_theme()
		root.size = Vector2i(1280,720)
		await process_frame
	# Finish the account-owned bot game before switching into isolated rule fixtures.
	await app._act({"type":"resign"})
	check(app.view.get("phase")=="over","bot game closed before rule fixtures")
	# Deterministic fixture server is only available to this test runner.
	for kind in ["P","N","B","R","Q","K"]:
		var piece_data: Dictionary = await app.api.request("/test-fixture",{"scenario":"piece_"+kind})
		app._enter(piece_data)
		await app._poll()
		await app._select(Vector2i(6,6))
		check(not app.action_menu.buttons[2].disabled,kind+" has movement icon in open position")
		check(not app.action_menu.buttons[0].disabled,kind+" has capture icon for legal visible target")
		var expected: String = {"B":"fire","R":"barrage","Q":"scan"}.get(kind,"none")
		check(app.action_menu.buttons[1].kind==expected,kind+" correct unique ability mapping")
		app._choose_action("move")
		var dest: Array = app.board.targets[0]
		await app._tap(Vector2i(int(dest[0]),int(dest[1])))
		check(app.view.get("turnCount",0)>0,kind+" movement executes on server")
		piece_data = await app.api.request("/test-fixture",{"scenario":"piece_"+kind})
		app._enter(piece_data)
		await app._poll()
		await app._select(Vector2i(6,6))
		app._choose_action("attack")
		dest = app.board.targets[0]
		await app._tap(Vector2i(int(dest[0]),int(dest[1])))
		check(not app.view.get("feed",[]).is_empty(),kind+" capture executes on server")
		await app.api.request("/test-return-turn",{"room":app.room})
		await app._poll()
		check("잡은 기물" in app.enemy_counts.text and not app.view.get("captured",[]).is_empty(),"captured pieces shown instead of hidden opponent composition")
		check(app.history_label.visible and not app.view.get("moveHistory",[]).is_empty(),"own move record visible below kill feed")
		if kind=="Q": await capture("icon_killlog")
	var trophy_data: Dictionary = await app.api.request("/test-fixture",{"scenario":"trophies"})
	app._enter(trophy_data)
	await app._poll()
	check(app.view.get("captured",[]).count("P")==3,"trophies count only captured pawns")
	check(app.enemy_icons.get_child_count()==5,"pawns grouped and four major pieces displayed individually")
	var pawn_icon = app.enemy_icons.get_child(0).get_child(0).get_child(0)
	var major_icon = app.enemy_icons.get_child(1).get_child(0)
	check(pawn_icon.custom_minimum_size.x<major_icon.custom_minimum_size.x,"pawn trophy smaller than major piece trophy")
	check(app.history_label.get_parent().get_parent().get_index()>app.feed_box.get_parent().get_parent().get_index(),"move record positioned below kill feed")
	await capture("trophies")
	root.size = Vector2i(390,844)
	await process_frame
	await capture("trophies_mobile")
	check(app.controls_scroll.size.y>=400,"mobile kill log and trophies have a nonzero scrollable panel")
	app.page_scroll.scroll_vertical = 1000
	await capture("trophies_mobile_log")
	app.page_scroll.scroll_vertical = 0
	root.size = Vector2i(1280,720)
	await process_frame
	var blocked: Dictionary = await app.api.request("/test-fixture",{"scenario":"blocked_bishop"})
	app._enter(blocked)
	await app._poll()
	await app._select(Vector2i(10,6))
	check(app.action_menu.buttons[2].disabled and app.action_menu.buttons[0].disabled,"blocked bishop cannot move or capture")
	check("저격 표적 없음" in app.action_hint.text,"blocked bishop explains range-preview-only ability")
	var before_invalid: int = app.view.turnCount
	await app._tap(Vector2i(0,0))
	check(not app.selection.is_empty() and app.view.turnCount==before_invalid and "턴 소모 없음" in app.action_hint.text,"invalid target preserves selection and explains no turn spent")
	app._choose_action("fire")
	check(app.board.targets.is_empty() and not app.board.ranges.is_empty(),"sniper without target displays range but cannot fire")
	await capture("blocked_bishop")

	for scenario in ["scan","fire","barrage","capture","promotion"]:
		var data: Dictionary = await app.api.request("/test-fixture",{"scenario":scenario})
		app._enter(data)
		await app._poll()
		if scenario=="scan":
			check(app.board.tile(Vector2i(3,4)).get("p")==null,"bush king is hidden before scan")
			await app._select(Vector2i(6,4))
			check(app.action_menu.buttons[1].kind=="scan","queen center icon selects scan")
			await create_timer(.35).timeout
			await capture("queen_actions")
			for corner in [Vector2(20,20),Vector2(490,20),Vector2(20,490),Vector2(490,490)]:
				app.action_menu.open_at(corner,"scan",[true,true,true],false,false)
				await process_frame
				for button in app.action_menu.buttons:
					check(button.position.x>=0 and button.position.y>=0 and button.position.x+46<=app.action_menu.size.x+.1 and button.position.y+46<=app.action_menu.size.y+.1,"fan stays inside board at edge")
			app._show_actions()
			app._set_mode("scan")
			await capture("scan")
			await app._tap(Vector2i(3,4))
			# Return a nonmoving opposing turn for the fixture only.
			await app.api.request("/test-return-turn",{"room":app.room})
			await app._poll()
			check(app.board.tile(Vector2i(3,4)).get("p",{}).get("t")=="K","scan reveals hidden king")
		elif scenario in ["fire","barrage"]:
			await app._select(Vector2i(4,4))
			app._set_mode(scenario)
			await app._tap(Vector2i(3,4))
			check(app.view.get("winner")=="W",scenario+" captures king")
			check(app.feed_box.get_child(0).get_child(0).get_child(1).get_child(0) is TextureRect,"kill feed uses real attacker piece icon")
			check("잡은 기물" in app.enemy_counts.text,"captured pieces shown below kill feed")
			check(app.result_label.visible and app.result_panel.visible,"result UI visible")
		elif scenario=="capture":
			await app._select(Vector2i(4,4))
			check(not app.action_menu.buttons[0].disabled,"attack icon available for visible legal capture")
			app._choose_action("attack")
			check(app.board.contains(app.board.targets,Vector2i(3,4)),"attack filters legal moves to visible enemy targets")
			await app._tap(Vector2i(3,4))
			check(app.view.get("winner")=="W","attack icon executes existing server capture action")
		elif scenario=="promotion":
			await app._select(Vector2i(1,4))
			app._choose_action("move")
			await app._tap(Vector2i(0,4))
			check(app.view.get("promote") != null,"promotion pauses turn")
			check(is_instance_valid(app.promote_window),"promotion window shown")
			await app._act({"type":"promote","choice":"R"})
			check(app.view.get("promote")==null,"promotion resolved")
	await app._act({"type":"resign"})
	check(app.view.get("phase")=="over","resign ends game")
	app._return_home()
	await app._join({})
	var friend: Dictionary = await app.api.request("/join",{"room":app.room,"name":"Friend"})
	await app._poll()
	check(app.view.get("bothJoined",false),"friend joins private room")
	check(app.chat.card.visible,"participant chat is visible")
	check(not app.chat.body.visible,"new room chat starts collapsed")
	app.chat.toggle.pressed.emit()
	app.chat.entry.grab_focus()
	app.chat.entry.edit()
	app.chat.entry.text = "작성 중인 한글"
	app.chat.entry.caret_column = 4
	for _refresh in range(3): await app._poll()
	check(app.chat.entry.text=="작성 중인 한글" and app.chat.entry.caret_column==4 and app.chat.entry.is_editing(),"poll preserves chat draft caret and editing")
	check(app.chat.entry.keep_editing_on_text_submit,"chat retains editing after Enter")
	app.chat._native_result("안녕 세상아",app.room,app.token)
	check(app.chat.entry.text=="안녕 세상아","native draft callback retains every Hangul syllable")
	app.chat._native_result("다른 방", "OTHER",app.token)
	check(app.chat.entry.text=="안녕 세상아","stale native draft cannot overwrite another room")
	app.chat.entry.text = "안녕하세요 [b]literal[/b]"
	await app.chat.send()
	var friend_view: Dictionary = await app.api.request("/state?room=%s&token=%s" % [app.room,friend.token])
	check(friend_view.get("chat",[]).size()==1,"chat reaches other participant")
	check(not app.chat.transcript.bbcode_enabled,"chat does not interpret player markup")
	check(app.chat.entry.text.is_empty(),"successful send clears input")
	await app.api.request("/chat",{"room":app.room,"token":friend.token,"text":"반가워요!","nonce":"friend-1"})
	await app._poll()
	check("반가워요!" in app.chat.transcript.text,"incoming chat renders")
	app.chat.toggle.pressed.emit()
	await create_timer(1.05).timeout
	await app.api.request("/chat",{"room":app.room,"token":friend.token,"text":"즐거운 대국 해요","nonce":"friend-2"})
	await app._poll()
	check(app.chat.unread==1 and not app.chat.body.visible,"collapsed chat counts new messages")
	app.chat.toggle.pressed.emit()
	check(app.chat.unread==0 and app.chat.body.visible,"expanding chat clears unread count")

	var reconnect: Dictionary = await app.api.request("/join",{"room":app.room,"token":app.token})
	check(reconnect.get("token")==app.token and reconnect.get("color")==app.seat,"reconnect retains seat")
	await app._act({"type":"ready","value":true})
	await app.api.request("/action",{"room":app.room,"token":friend.token,"type":"ready","value":true})
	await app._poll()
	check(app.view.get("phase")=="play","two player ready flow")
	await process_frame
	check(app.clock_label.get_line_count()==1 and app.turn_meta.get_line_count()==1,"clock and move count remain a single line")
	check(app.chat.card.get_parent().get_parent()==app.side_panel,"chat input outside scrolling match records")
	var old_history: Array = app.view.get("moveHistory",[]).duplicate()
	var long_history: Array = []
	for n in range(80): long_history.append("%d. Nf4" % (n+1))
	app.view["moveHistory"] = long_history
	app.game_display._render()
	await process_frame
	await process_frame
	check(not app.history_label.text.contains("\n") and app.history_label.text.contains("80. Nf4") and not app.history_label.text.contains("77. Nf4"),"collapsed history shows only the last three compact moves")
	app.match_ui.history_toggle.pressed.emit()
	check(app.history_label.text.split("\n").size()==10 and app.history_button.visible,"expanded history is bounded to ten moves with full history access")
	check(app.chat.entry.get_global_rect().end.y<=app.side_panel.get_global_rect().end.y,"chat input remains inside sidebar with long history")
	check(app.game_display._compact_history("1. resign")=="1. 기권","internal resignation event has player-facing notation")
	app.view["moveHistory"] = old_history
	app.game_display._render()
	await capture("social_chat")
	await app._act({"type":"resign"})
	await app._act({"type":"rematch"})
	check(app.view.get("phase")=="over","rematch waits for opponent")
	await app.api.request("/action",{"room":app.room,"token":friend.token,"type":"rematch"})
	await app._poll()
	check(app.view.get("phase")=="setup","mutual rematch creates setup")
	# Direct navigation does not resign: close the rematch before the next scenario.
	await app._act({"type":"resign"})
	check(app.view.get("phase")=="over","private rematch closed before ranked scenario")
	app._return_home()
	var signup: Dictionary = await app.api.request("/signup",{"name":"GodotTestA","pw":"TestPass123!"})
	check(signup.get("ok",false),"signup through Godot HTTP")
	if signup.get("ok"):
		app.session = signup.session
		app.me = signup.user
	var other: Dictionary = await app.api.request("/signup",{"name":"GodotTestB","pw":"TestPass123!"})
	await app._match_command("join")
	await app.api.request("/match/join",{"session":other.get("session","")})
	await app._poll()
	check(app.match_data.get("state")=="found","rank match found")
	await app.api.request("/match/accept",{"session":other.get("session","")})
	await app._match_command("accept")
	await app._poll()
	check(app.view.get("match",false),"accepted match opens room")
	check(app.board.flip==(app.seat=="B"),"black board orientation")
	await app._act({"type":"resign"})
	check(app.view.series.me==0 and app.view.series.opp==1,"first ranked result updates series")
	var opponent_match: Dictionary = await app.api.request("/match/status",{"session":other.session})
	await app.api.request("/action",{"room":app.room,"token":opponent_match.token,"type":"rematch"})
	await app._poll()
	check(app.view.rematch.opp,"opponent rematch invitation received")
	await app._act({"type":"rematch"})
	check(app.view.get("phase")=="setup" and app.view.series.opp==1,"accepted rematch preserves series score")
	await app.api.request("/action",{"room":app.room,"token":opponent_match.token,"type":"resign"})
	await app._poll()
	check(app.view.series.me==1 and app.view.series.opp==1 and app.view.series.final,"one each unlocks final round")
	check("최종전" in app.result_sub.text,"one each result announces final")
	await app._act({"type":"rematch"})
	await app.api.request("/action",{"room":app.room,"token":opponent_match.token,"type":"rematch"})
	await app._poll()
	check(app.view.get("phase")=="setup" and "최종전" in app.series_label.text,"final setup keeps series score")
	await app._act({"type":"resign"})
	check(app.view.series.complete and app.view.series.opp==2,"second victory completes ranked series")
	check(not app.over_controls.visible,"completed series hides sidebar rematch")
	var has_rematch := false
	for control in app.result_actions.get_children():
		if control is Button and "재대결" in control.text: has_rematch = true
	check(not has_rematch,"completed series has no result rematch button")
	check("시리즈 패배" in app.result_sub.text,"result explains final series outcome")
	app.view["settlementPending"] = true
	app._render_result()
	check("자동으로 다시 시도" in app.result_sub.text,"result explains pending settlement without claiming a saved rating")
	app.view["settlementPending"] = false
	app._render_result()
	var denied: Dictionary = await app.api.request("/action",{"room":app.room,"token":app.token,"type":"rematch"})
	check(not denied.get("ok",false),"server refuses post-series rematch")
	await capture("social_series_complete")

	var history: Dictionary = await app.api.request("/me/history",{"session":app.session})
	check(not history.get("rows",[]).is_empty(),"ranked result recorded")
	await app._history()
	await process_frame
	for child in app.get_children():
		if child is Window: child.queue_free()
	await process_frame
	await app._leaderboard()
	await process_frame
	var rank_grid = app.find_child("LeaderboardGrid",true,false)
	check(rank_grid!=null and rank_grid.columns==5 and rank_grid.get_child_count()>=10,"leaderboard renders headers and player data in a five-column grid")
	await capture("leaderboard")
	if "--capture" in OS.get_cmdline_user_args():
		await close_windows()
		root.size = Vector2i(390,844)
		await process_frame
		await app._leaderboard()
		await capture("leaderboard_mobile")
		await close_windows()
		root.size = Vector2i(1280,720)
		await process_frame
	for child in app.get_children():
		if child is Window: child.queue_free()
	app._return_home()
	await app._join({"solo":true})
	check(app.view.get("solo",false),"solo mode")
	app.reveal = true
	await app._poll()
	check(app.board.tile(Vector2i(0,2)).get("f")==0,"solo reveal toggle")
	# Web build also loads this client, but excludes test scripts.
	print("GODOT_SMOKE_FAILURES="+str(failures))
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)

func capture(name: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() and not ("--social-capture" in OS.get_cmdline_user_args() and name.begins_with("social_")): return
	await process_frame
	await create_timer(1.0).timeout
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://").path_join("../.dev-data/qa-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(name+".png"))


func close_windows() -> void:
	for child in app.get_children():
		if child is Window:
			child.hide()
			child.queue_free()
	await process_frame
	await process_frame
