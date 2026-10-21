extends SceneTree
var app
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, text: String) -> void:
	if not ok:
		failures += 1
		push_error(text)
	else: print("PASS: "+text)
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.3).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/"+name+".png")
func run() -> void:
	root.size = Vector2i(1280,850)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	app.spectating.menu()
	check(app.subpage.visible,"watch code entry")
	await shot("watch_entry")
	var fixture: Dictionary = await app.api.request("/test-fixture",{"scenario":"trophies"})
	app._enter(fixture)
	await app._poll()
	check(app.spectating.audience.text.contains("0명"),"players see zero audience")
	var joined: Dictionary = await app.api.request("/watch/join",{"room":fixture.room})
	await app._poll()
	check(app.spectating.audience.text.contains("1명"),"players see audience join live")
	app._enter(joined)
	await app._poll()
	check(app.spectating.waiting.visible and not app.board.visible,"waiting hides live board")
	check(app.view.get("capturedBy",{}).is_empty(),"waiting hides trophies")
	await shot("watch_waiting")
	await app.api.request("/test-age",{"room":fixture.room})
	await app._poll()
	check(not app.spectating.waiting.visible and app.board.visible,"delayed broadcast opens")
	check(app.view.yourColor=="spectator","neutral spectator perspective")
	check(not app.setup_controls.visible and not app.resign_button.visible,"no spectator actions")
	check(app.history_label.text.contains("B!"),"delayed history rendered")
	check(app.enemy_icons.get_child_count()==2,"both trophy groups rendered")
	check(app.spectating.flip_button.visible,"flip control visible")
	app.spectating.flip_button.pressed.emit()
	check(app.spectating.flipped,"flip works")
	check(app.opponent_line.text.begins_with("백"),"flipped player names match board")
	var denied: Dictionary = await app.api.request("/action",{"room":fixture.room,"token":joined.token,"type":"resign"})
	check(not denied.get("ok"),"spectator cannot resign")
	await shot("watch_board")
	root.size = Vector2i(390,844)
	await process_frame
	await shot("watch_mobile")
	root.size = Vector2i(1280,850)
	await app.api.request("/test-end",{"room":fixture.room})
	await app._poll()
	check(app.view.phase=="play","live result remains hidden")
	await app.api.request("/test-age",{"room":fixture.room})
	await app._poll()
	check(app.result_label.text=="백 승리","delayed neutral result")
	await shot("watch_result")
	await app.spectating.leave()
	var player_view: Dictionary = await app.api.request("/state?room=%s&token=%s" % [fixture.room,fixture.token])
	check(player_view.spectatorCount==0,"leaving removes audience immediately")
	print("WATCH_FAILURES=",failures)
	quit(1 if failures else 0)
