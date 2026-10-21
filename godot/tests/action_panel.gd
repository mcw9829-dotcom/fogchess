extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1280,850)
	var app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	var fixture: Dictionary=await app.api.request("/test-fixture",{"scenario":"piece_Q"})
	app._enter(fixture)
	await app._poll()
	await app._select(Vector2i(6,6))
	await app._act({"type":"move","pid":"W_Q1","r":5,"c":7})
	await app.api.request("/test-return-turn",{"room":fixture.room})
	await app._poll()
	await app._select(Vector2i(5,7))
	if not "Qxh6" in app.history_label.text: push_error("compact history missing")
	if app.action_details.visible: push_error("rules should start collapsed")
	app.action_details_button.pressed.emit()
	if not app.action_details.visible: push_error("rules disclosure failed")
	app.action_details_button.pressed.emit()
	if app.game_display._compact_history("2. 나이트 f5 이동 → h3")!="2. Nh3": push_error("old replay compatibility failed")
	await create_timer(.5).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/action_panel.png")
	for child in app.audio.get_children():
		if child is AudioStreamPlayer: child.stop()
	await create_timer(.3).timeout
	print("ACTION_PANEL_DONE")
	quit()
