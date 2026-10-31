extends SceneTree
var app
var checks := 0
var failures: Array[String] = []
func _initialize(): run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures.append(label)
func settle(seconds: float=.4): await create_timer(seconds).timeout
func shot(name: String):
	await settle(); RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func button(parent: Node, text: String) -> Button:
	for child in parent.find_children("*","Button",true,false):
		if child.text==text: return child
	return null
func close_windows():
	for child in app.get_children():
		if child is Window: child.queue_free()
	await process_frame
func run():
	root.size=Vector2i(1280,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await settle(.7)
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","light",false);app._apply_theme()
	var fixture: Dictionary=await app.api.request("/test-fixture",{"scenario":"promotion"})
	app._enter(fixture);await app._poll();await settle(2)
	await app._act({"type":"move","pid":"W_P1","r":0,"c":4});await settle()
	var queen=button(app.promote_window,"퀸")
	check(is_instance_valid(queen),"queen promotion has a real selectable button")
	await shot("queen-promotion")
	if is_instance_valid(queen): queen.pressed.emit()
	await settle(.8)
	check(not app.view.get("promote"),"queen selection completes promotion over HTTP")
	check(app.view.grid[0][4].p.t=="Q","promoted pawn appears as queen")
	app._return_home();await settle(1.6)
	fixture=await app.api.request("/test-focus",{})
	app._enter(fixture);await app._poll();await settle(2)
	app.board.effects=true;app.board.fx.reduced=false
	app.board.view.scanTiles=[[5,7],[5,8],[6,7],[6,8]]
	app.board.view.scanZones=[{"cells":app.board.view.scanTiles,"owner":"B","remaining":1}]
	check(is_equal_approx(app.board.targeting.surveillance_angle(12),TAU),"surveillance makes one slow revolution in twelve seconds")
	await shot("enemy-scan-dark")
	app.prefs.set_value("settings","light",true);app._apply_theme();await shot("enemy-scan-light")
	app.prefs.set_value("settings","light",false);app._apply_theme()
	for i in range(36):
		app.board.clock=float(i)/3.0
		await process_frame;RenderingServer.force_draw(false)
		var region: Rect2=app.board.get_global_rect()
		root.get_texture().get_image().get_region(Rect2i(region)).save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join("radar-%02d.png" % i))
	# A stale movement packet must not create a hidden occupant effect.
	app.board.view.grid[3][3].p=null
	app.board.fx.clear()
	app.board.play_fx({"type":"move","cells":[[3,3]],"actor":"B"})
	check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty(),"client drops hidden movement packets")
	app.board.view.grid[3][3].p={"o":"B","t":"P"}
	app.board.play_fx({"type":"move","cells":[[3,3]],"actor":"B"})
	check(not app.board.fx.parts.is_empty(),"visible enemy movement still has effects")
	var hidden: Dictionary=app.board.view.duplicate(true);hidden.grid[3][3].p=null
	app.board.set_view(hidden,false)
	check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty(),"concealment cancels lingering movement particles")
	app._return_home();await settle(1.6)
	var signup: Dictionary=await app.api.request("/signup",{"name":"PolishMember","pw":"FixturePass123!"})
	app.session=signup.session;app.me=signup.user
	await app._join({"vs_bot":true,"level":"easy"});await settle(2)
	check(app.seat=="B" and app.board.flip,"black assignment flips the live board")
	check(app.view.yourColor=="B" and app.view.oppReady,"white computer is ready while human places black")
	await shot("black-player")
	await app._act({"type":"ready"})
	for attempt in range(20):
		await settle(.3);await app._poll()
		if int(app.view.get("turnCount",0))>0: break
	check(int(app.view.get("turnCount",0))>0 and app.view.get("turn")=="B","white computer plays first and hands turn to black human")
	await app._act({"type":"resign"});app._return_home();await settle(2)
	var session: String=app.session
	app.account._delete_form();await settle()
	check(button(app,"계정 영구 삭제").disabled,"desktop deletion starts disabled")
	await shot("delete-desktop")
	await close_windows()
	root.size=Vector2i(390,844);await settle()
	app.account._delete_form();await settle()
	var remove=button(app,"계정 영구 삭제")
	check(remove.disabled,"account deletion requires explicit confirmation and password")
	var win: Window=remove.get_window()
	var password: LineEdit
	var agree: CheckBox
	for field in win.find_children("*","LineEdit",true,false): password=field
	for field in win.find_children("*","CheckBox",true,false): agree=field
	check(password.secret,"deletion password is masked")
	await shot("delete-mobile")
	password.text="wrong";agree.button_pressed=true;remove.pressed.emit();await settle(.7)
	check(not app.session.is_empty() and password.text.is_empty(),"wrong password preserves account and clears field")
	password.text="FixturePass123!";password.text_changed.emit(password.text);remove.pressed.emit();await settle(.8)
	check(app.session.is_empty() and app.me.is_empty(),"successful deletion returns client to guest")
	var gone: Dictionary=await app.api.request("/me",{"session":session})
	check(not gone.get("ok",true),"deleted session is rejected by real server")
	var file=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("native-checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("ACCOUNT_POLISH_CHECKS=",checks," FAILURES=",failures.size())
	app.queue_free();await process_frame;await process_frame;quit(failures.size())
