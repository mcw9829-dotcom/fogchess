extends SceneTree
var app: Control
var failures := 0
var confirmed := false

class DelayedAPI extends Node:
	var base_url := "http://127.0.0.1"
	var actions := 0
	var recover := false
	var snapshot: Dictionary
	var delay := .55
	func request(path: String,_body: Dictionary={}) -> Dictionary:
		if path=="/action":
			actions += 1
			await get_tree().create_timer(delay).timeout
			return {"ok":true} if recover else {"network_error":true,"msg":"테스트 연결 끊김"}
		if path.begins_with("/state"):
			return snapshot.duplicate(true) if recover else {"network_error":true}
		return {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,message: String) -> void:
	if value: print("PASS: "+message)
	else: failures+=1; push_error("FAIL: "+message)

func settle() -> void:
	await process_frame
	await process_frame
	await create_timer(.12).timeout

func capture(label: String) -> void:
	await settle()
	if not "--capture" in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://../.dev-data/qa-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join("expert-"+label+".png"))

func _run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await settle()
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	check("직접 배우기" in app.game_ux.learn_button.text,"new player sees direct learning entry")
	await capture("home")
	root.size=Vector2i(390,844)
	await capture("home_mobile")
	app.prefs.set_value("settings","tutorial_step",3)
	app.game_ux.refresh_learning()
	check("쉬움 봇" in app.game_ux.learn_button.text,"completed tutorial leads to easy bot")
	var tutorial = load("res://tutorial(튜토리얼 진행).gd").new()
	root.add_child(tutorial)
	await settle()
	check(tutorial.board.view.grid[8][2].f==0 and tutorial.board.view.grid[9][2].f==1,"tutorial knight sight boundary is two, not three")
	check("2칸" in tutorial.hint.text,"tutorial explains current knight radius")
	for spec in [[Vector2i(6,2),Vector2i(4,1),"move"],[Vector2i(6,4),Vector2i(1,5),"scan"],[Vector2i(5,2),Vector2i(1,5),"fire"]]:
		tutorial._tap(spec[0])
		tutorial.action_menu.chosen.emit(spec[2])
		tutorial._tap(spec[1])
	check(tutorial.step==3 and tutorial.finish.visible,"all tutorial missions still complete")
	tutorial.queue_free()
	var fixture: Dictionary=await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	app._message("")
	await app._select(Vector2i(7,5))
	app.moves.reloading = true
	app.moves.moves = []
	app._choose_action("move")
	check("없습니다" in app.coach_label.text and not "이동/포획 가능" in app.match_ui.mobile_status.text,"empty moves and reload status do not contradict")
	check("제한하지 않습니다" in app.action_details.text,"general reload rule remains in details")
	app.piece_input._invalid_target(Vector2i(0,0))
	check("×" in app.action_hint.text and not "우클릭" in app.action_hint.text,"mobile invalid-target recovery uses actual cancel control")
	app._update_selection_ui()
	var selected: Dictionary=app.selection.duplicate(true)
	for width in [390,320]:
		root.size=Vector2i(width,844)
		app.page_scroll.scroll_vertical=0
		app._layout()
		app._render()
		await settle()
		var board_size: Vector2=app.board.size
		check(not app.game_ux.scroll_bar.visible,"return bar hidden with visible original clock "+str(width))
		for button in [app.match_ui.mobile_help,app.match_ui.mobile_cancel,app.match_ui.top_sound]:
			check(button.size.x>=44 and button.size.y>=44,"outside-board touch target at least 44 logical units: "+button.accessibility_name)
		check(not app.match_ui.mobile_help.get_global_rect().intersects(app.match_ui.mobile_cancel.get_global_rect()),"mobile help and cancel targets do not overlap")
		await capture("mobile_"+str(width))
		app.page_scroll.scroll_vertical=600
		await settle()
		check(app.game_ux.scroll_bar.visible,"records scroll preserves live clock "+str(width))
		check(app.game_ux.scroll_bar.get_global_rect().end.y<=app.page_scroll.global_position.y,"return bar reserves space outside scrolling content")
		check(app.board.size.is_equal_approx(board_size),"return bar does not resize board")
		await capture("records_"+str(width))
		app.game_ux.return_button.pressed.emit()
		await settle()
		check(app.page_scroll.scroll_vertical==0 and app.selection==selected,"one-tap return preserves selected piece")
	app.match_ui.mobile_help.grab_focus()
	app.match_ui._mobile_details()
	await settle()
	var details: Window
	for child in app.get_children():
		if child is Window and child.visible: details=child
	check(is_instance_valid(details),"touch detail path opens without hover")
	var texts := ""
	for child in details.find_children("*","Label",true,false): texts += child.text
	check("Tab" in texts and "공격은" in texts,"detail path explains keyboard and attack/capture terms")
	var esc := InputEventKey.new()
	esc.keycode=KEY_ESCAPE
	esc.pressed=true
	details.push_input(esc,true)
	await create_timer(.26).timeout
	await settle()
	check(not is_instance_valid(details),"Esc closes detail modal")
	check(app.match_ui.mobile_help.has_focus(),"detail modal restores the invoking focus")
	app.ui_components.confirm_action("기권 테스트","테스트에서는 서버 명령을 보내지 않습니다.","기권",func(): confirmed=true)
	await settle()
	var dialog: Window
	for child in app.get_children():
		if child is Window and child.name=="GameConfirmation": dialog=child
	check(dialog.get_cancel_button().has_focus(),"destructive confirmation initially focuses cancel")
	var enter := InputEventKey.new()
	enter.keycode=KEY_ENTER
	enter.pressed=true
	dialog.push_input(enter,true)
	var release: InputEventKey=enter.duplicate()
	release.pressed=false
	dialog.push_input(release,true)
	await create_timer(.26).timeout
	await settle()
	check(not confirmed,"opening confirmation then Enter does not resign")
	check(not is_instance_valid(dialog),"Enter on default cancel closes confirmation")
	if is_instance_valid(dialog): dialog.queue_free()
	await settle()
	app._promotion()
	var promotion: Window=app.promote_window
	promotion.push_input(esc,true)
	await settle()
	check(is_instance_valid(promotion) and promotion.visible,"Esc cannot dismiss required promotion choice")
	promotion.queue_free()
	await settle()
	app._game_menu()
	await capture("menu_320")
	var menu: Window=app.get_node("MatchMenu")
	check(menu.find_child("LeaveMatch",true,false).get_meta("ui_role")=="danger","committed leave shares resignation danger styling")
	check("홈으로" in menu.find_child("ExitConsequences",true,false).text,"menu distinguishes result screen from home")
	menu.find_child("ResignMatch",true,false).grab_focus()
	menu.find_child("ResignMatch",true,false).pressed.emit()
	await settle()
	check(not menu.visible,"resignation prompt suspends underlying menu")
	for child in app.get_children():
		if child is Window and child.name=="GameConfirmation" and child.visible: dialog=child
	dialog.get_cancel_button().pressed.emit()
	await create_timer(.26).timeout
	await settle()
	check(menu.visible and menu.find_child("ResignMatch",true,false).has_focus(),"cancel restores menu and the invoking resignation button")
	menu.queue_free()
	await settle()
	root.size=Vector2i(1280,900)
	app._layout()
	app._render()
	await capture("desktop")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await capture("light")
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	app.view.bot = true
	app.view.reloading=[{"pid":"W_B1","type":"B"}]
	app.game_ux.active_tip=""
	app._render()
	check("再" not in app.game_ux.practice_label.text and "재장전" in app.game_ux.practice_label.text,"practice explains a public reload occurrence")
	app.game_ux.practice_next.pressed.emit()
	check(app.game_ux.seen_tips.has("reload"),"practice acknowledgement prevents repeating the same lesson")
	await capture("practice")
	app.view.bot=false
	app._render()
	check(not app.game_ux.practice_card.get_parent().visible,"ranked/friend play does not auto-display practice lessons")
	var public_feed: Array=app.view.feed.duplicate(true)
	app.view.feed.append_array(public_feed)
	app._render()
	check(app.feed_box.get_child_count()==3,"record overview preserves recent three events")
	app.game_ux.feed_toggle.pressed.emit()
	check(app.feed_box.get_child_count()==6,"expand shows all received public feed events")
	app.game_ux.feed_toggle.pressed.emit()
	check(app.feed_box.get_child_count()==3,"collapse restores overview without nested scrolling")
	var speech: String=app.game_ux.announcement.text
	app.view.turnSecondsLeft=24
	app._render()
	check(app.game_ux.announcement.text==speech,"clock tick does not repeat a live announcement")
	app.view.turnSecondsLeft=7
	app._render()
	check("시간" in app.game_ux.announcement.text,"low time has a semantic live announcement")
	var live: Dictionary=app.view.duplicate(true)
	app.view.phase="over"
	app.view.winner="B"
	app.view.series={"me":1,"opp":2,"complete":true,"final":false,"winner":"B"}
	app._render()
	check(app.result_label.text=="시리즈 패배","completed series title names series outcome")
	await capture("series")
	root.size=Vector2i(320,844)
	app._layout()
	await capture("series_mobile")
	check(app.result_actions.get_global_rect().end.y<=root.size.y,"mobile series result actions remain in the viewport")
	check(app.result_actions.get_global_rect().end.x<=root.size.x,"mobile series result actions fit the width")
	root.size=Vector2i(1280,900)
	app._layout()
	app.view.series={"me":1,"opp":0,"complete":false,"final":false}
	app.view.winner="W"
	app._render()
	check(app.result_label.text=="이번 판 승리" and "먼저 2승" in app.result_sub.text,"individual win remains distinct from series win")
	app._apply_state(live)
	var selection_before_clear: Dictionary=app.selection.duplicate(true)
	app._clear_selection()
	app._show_actions()
	check(not app.action_menu.opened,"stale detail action cannot reopen actions after selection clears")
	app.selection=selection_before_clear
	var real_api: Node=app.api
	var slow:=DelayedAPI.new()
	root.add_child(slow)
	slow.snapshot=live.duplicate(true)
	slow.snapshot.turnCount=int(live.turnCount)+1
	slow.snapshot.turn="B"
	app.api=slow
	app._act({"type":"move","pid":"W_B1","r":7,"c":6})
	await create_timer(.42).timeout
	check(app.game_session.request_status=="행동 전달 중…","slow request reports sending after delay threshold")
	app._act({"type":"move","pid":"W_B1","r":7,"c":6})
	check(slow.actions==1,"repeated action during transmission is blocked")
	await create_timer(.25).timeout
	check(app.game_session.awaiting_state and app.game_session.request_status=="결과 확인 중…","lost response remains unknown until authoritative state arrives")
	app._act({"type":"move","pid":"W_B1","r":7,"c":6})
	check(slow.actions==1,"uncertain result never auto-retries or accepts a duplicate")
	slow.recover=true
	await app._poll()
	check(not app.game_session.awaiting_state and app.game_session.request_status.is_empty(),"state recovery releases pending result lock")
	check(app.view.turnCount==slow.snapshot.turnCount,"recovery uses authoritative updated turn")
	slow.delay=.02
	await app._act({"type":"ready","value":true})
	check(app.game_session.request_status.is_empty(),"fast response avoids transient waiting message")
	app.api=real_api
	slow.queue_free()
	await create_timer(.4).timeout
	print("EXPERT_UI_FAILURES="+str(failures))
	app.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
