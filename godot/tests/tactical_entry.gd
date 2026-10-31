extends SceneTree
var app
var failures:=0
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+title)
func shot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func wait_playing() -> void:
	var deadline:=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if is_instance_valid(app.ui_motion.transition) and app.ui_motion.transition.phase=="playing": return
	check(false,"transition reaches playback")
func wait_done() -> void:
	var deadline:=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not app.ui_motion.is_transition_busy():
			await process_frame;await process_frame
			return
	check(false,"transition completes and releases input")
func own_piece() -> Vector2i:
	for r in range(12):
		for c in range(12):
			var p: Variant=app.view.grid[r][c].get("p")
			if p is Dictionary and p.o==app.view.yourColor: return Vector2i(r,c)
	return Vector2i(-1,-1)
func run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false;app._message("")
	var lobby=app.ui_shell.lobby_home
	for light in [false,true]:
		var name: String="light" if light else "dark"
		app.prefs.set_value("settings","light",light);app._apply_theme()
		lobby.select_section("practice",false);await create_timer(.2).timeout
		check(lobby.headers.records.global_position.y>lobby.headers.practice.global_position.y and lobby.headers.options.global_position.y>lobby.headers.records.global_position.y and lobby.headers.account.global_position.y>lobby.headers.options.global_position.y,"utility menus are vertical under main menus "+name)
		var source: Rect2=lobby.preview_board.get_global_rect()
		shot("lobby-"+name)
		await app._join({"solo":true})
		await wait_playing()
		var trans=app.ui_motion.transition
		var destination: Rect2=app.board.get_global_rect()
		check(trans.is_busy() and trans.direction=="entry","native entry owns presentation "+name)
		check(trans.from_rect.is_equal_approx(source),"entry starts at actual lobby board "+name)
		check(absf(destination.get_center().x-720)<1,"actual game board centered "+name)
		check(destination.size.x>source.size.x,"actual board grows from lobby size "+name)
		var piece:=own_piece()
		await app._tap(piece)
		await app._act({"type":"ready"})
		check(app.selection.is_empty() and not app.busy,"board/action input blocked while moving "+name)
		check(trans.side_cards.all(func(item):return not item.node.visible),"HUD starts hidden "+name)
		await create_timer(.35).timeout
		check(trans.lobby_board.position.x<source.position.x and trans.lobby_board.position.x>destination.position.x,"one board travels between screen locations "+name)
		check(app.board.get_global_rect().is_equal_approx(destination),"underlying live board stays stationary "+name)
		check(trans.menu.position.x<0,"menu exits left "+name)
		shot("moving-"+name)
		# A newly concealed square must not retain the old authorized picture.
		var fresh: Dictionary=app.view.duplicate(true)
		fresh.grid[0][0]={"f":1,"t":0}
		app._apply_state(fresh)
		check(trans.match_board.view.grid[0][0].get("f")==1 and not trans.match_board.view.grid[0][0].has("p"),"moving proxy accepts newest concealed view "+name)
		await wait_done()
		check(trans.get_child_count()==0 and app.board.scale==Vector2.ONE,"entry releases proxies and restores normal scene "+name)
		await app._tap(piece)
		check(not app.selection.is_empty(),"first normal piece selection works after landing "+name)
		app._clear_selection()
		var count: int=app.ui_motion.match_entry_count
		app._apply_state(app.view.duplicate(true));await process_frame
		check(not app.ui_motion.is_transition_busy() and app.ui_motion.match_entry_count==count,"poll never replays entrance "+name)
		shot("game-"+name)
		var end: Dictionary=app.view.duplicate(true);end.phase="over";end.winner="W"
		app._apply_state(end);await create_timer(.4).timeout
		check(app.result_panel.visible and not app.ui_motion.is_transition_busy(),"result remains until home is chosen "+name)
		app._return_home();await wait_playing()
		check(trans.direction=="return" and app.room.is_empty() and app.view.is_empty(),"return visual keeps no live room/session state "+name)
		await create_timer(.65).timeout
		check(trans.map.modulate.a>.99 and trans.lobby_board.position.x>destination.position.x,"return restores map then moves board right "+name)
		shot("returning-"+name)
		await wait_done()
		check(app.home.visible and lobby.backdrop.visible and trans.get_child_count()==0,"return completes in interactive lobby "+name)
		check(lobby.preview_board.get_global_rect().is_equal_approx(source),"return lands at actual lobby position "+name)
	# Interrupted entry never leaves a stale overlay or previous room on screen.
	await app._join({"solo":true});app._return_home();await create_timer(.2).timeout
	check(app.home.visible and not app.ui_motion.is_transition_busy(),"immediate return cancels pending entry")
	await app._join({"solo":true});await wait_playing()
	root.size=Vector2i(1120,760);app._layout();await create_timer(.15).timeout
	check(not app.ui_motion.is_transition_busy() and app.board.get_global_rect().end.x<=1120,"resize safely finishes at real layout")
	app._return_home();await wait_done()
	for width in [390,320]:
		root.size=Vector2i(width,844);app._layout();await create_timer(.25).timeout
		await app._join({"solo":true});await wait_playing()
		check(not app.ui_motion.transition.source_visible,"mobile uses no imaginary lobby board "+str(width))
		await wait_done()
		check(app.board.get_global_rect().end.x<=width and app.board.size.x==app.board.size.y,"mobile board lands within viewport "+str(width))
		app._return_home();await wait_done()
		check(app.home.visible and not app.ui_motion.is_transition_busy(),"mobile reverse unlocks lobby "+str(width))
	print("LOBBY_CHECKS=",checks);print("LOBBY_FAILURES=",failures)
	app.queue_free();await process_frame;await process_frame;quit(failures)
