extends SceneTree
var app
var checks:=0
var failures: Array[String]=[]
func _initialize(): run.call_deferred()
func check(ok: bool,message: String):
	checks+=1;print(("PASS " if ok else "FAIL ")+message)
	if not ok:failures.append(message)
func settle(seconds: float=.4): await create_timer(seconds).timeout
func shot(name: String):
	await settle();RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func run():
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await settle(.5)
	for child in app.get_children():
		if child is Timer:child.stop()
	app.audio.enabled=false
	var signup: Dictionary=await app.api.request("/signup",{"name":"FlowOwner","pw":"FixturePass123!"})
	check(signup.get("ok",false),"fixture member created")
	app.session=signup.session;app.me=signup.user
	await app._join({"vs_bot":true,"level":"easy"});await settle(2)
	var room: String=app.room;var token: String=app.token
	check(not room.is_empty(),"owned bot room exists")
	app._return_home();await settle(2)
	await app.lobby_status.refresh_active()
	check(app.lobby_status.active.get("room")==room,"lost local room recovered from account")
	await app._match_command("join");await settle()
	check(app.lobby_status.resume_card.visible and not app.matching,"blocked rank request offers resume")
	for width in [1440,390,320]:
		root.size=Vector2i(width,900 if width==1440 else 740);await settle()
		var card: Rect2=app.lobby_status.resume_card.get_global_rect()
		check(absf(card.get_center().x-root.size.x/2)<12 and card.end.y<=root.size.y and root.size.y-card.end.y<34,"resume stays bottom-center "+str(width))
		check(card.position.x>=0 and card.end.x<=app.size.x,"resume fits width "+str(width))
		await shot("resume-"+str(width))
	app.lobby_status.resume.pressed.emit();await settle(2)
	check(app.room==room and app.token==token and app.game.visible,"resume restores original seat")
	check(not app.lobby_status.resume_card.visible,"resume hides inside match")
	await app._act({"type":"resign"});app._return_home();await settle(2)
	await app.lobby_status.refresh_active()
	check(app.lobby_status.active.is_empty() and not app.lobby_status.resume_card.visible,"finished match removes resume")
	await app._match_command("join");await settle()
	check(app.matching and app.lobby_status.queue_card.visible,"real rank queue shown")
	check(not is_instance_valid(app.match_window),"waiting queue has no modal window")
	for width in [1440,390,320]:
		root.size=Vector2i(width,900 if width==1440 else 740);await settle()
		var card: Rect2=app.lobby_status.queue_card.get_global_rect()
		check(absf(card.get_center().x-app.size.x/2)<12 and card.position.y<26,"queue stays top-center "+str(width))
		check(card.end.x<=app.size.x and card.end.y<=app.page_scroll.get_global_rect().position.y,"queue does not cover menu "+str(width))
		await shot("queue-"+str(width))
	app.lobby_status.cancel.pressed.emit();await settle()
	check(not app.matching and not app.lobby_status.queue_card.visible,"cancel leaves queue")
	# A found match still requires an explicit acceptance dialog.
	await app._match_update({"ok":true,"state":"found","opp":{"name":"Other","rating":1000},"secondsLeft":15,"accepted":false,"oppAccepted":false})
	await settle()
	check(is_instance_valid(app.match_window) and app.match_window.visible and app.lobby_status.queue_card.visible,"found match preserves acceptance dialog and queue slot")
	await app._match_command("cancel");await settle()
	# Authored learning frames, direct practice input and resume progress agree.
	app._help();await settle()
	var guide=app.find_child("FocusedPieceGuide",true,false)
	guide.select_piece("P",false);guide.select_stage("attack");guide.demo.stop()
	check("정면" in guide.rule_body.text and guide.demo.frames.any(func(frame):return frame.get("hit",[])==[[2,3]]),"guide demonstrates forward capture")
	await shot("pawn-guide")
	for child in app.get_children():
		if child is Window:child.queue_free()
	await process_frame
	app.prefs.set_value("settings","tutorial_step_v2",0);app._tutorial();await settle()
	var tutorial
	for child in app.get_children():
		if child is Window and child.get_child_count()>0 and child.get_child(0).has_signal("progress_changed"):tutorial=child.get_child(0)
	check(is_instance_valid(tutorial) and "정면" in tutorial.hint.text,"practice begins with pawn capture")
	await shot("pawn-practice")
	for spec in [[Vector2i(7,8),Vector2i(6,8),0],[Vector2i(6,2),Vector2i(4,1),2],[Vector2i(6,4),Vector2i(1,5),1],[Vector2i(5,2),Vector2i(1,5),1]]:
		tutorial._tap(spec[0]);tutorial.action_menu.buttons[spec[2]].pressed.emit();tutorial._tap(spec[1])
	check(tutorial.step==4 and tutorial.finish.visible,"all four practice stages complete")
	check(int(app.prefs.get_value("settings","tutorial_step_v2",0))==4,"updated learning progress saved")
	var f=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("checks.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close()
	print("LOBBY_FLOW_CHECKS=",checks," FAILURES=",failures.size())
	app.queue_free();await process_frame;await process_frame;quit(failures.size())
