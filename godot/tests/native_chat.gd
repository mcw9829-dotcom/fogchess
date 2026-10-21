extends SceneTree
var app
var ticks := 0
var opened := false
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	app.room="NATIVE_QA"
	app.token="native-test"
	app.view={"chatEnabled":true}
	app.chat.open_native_editor()
	opened=app.chat.native_open
	for i in range(100):
		await create_timer(.1).timeout
		ticks+=1
		if not app.chat.native_open: break
	var success: bool = opened and not app.chat.native_open and ticks>=5 and app.chat.entry.text=="안녕 세상아"
	print("NATIVE_DIALOG_PASS="+str(success)+" MAIN_LOOP_TICKS="+str(ticks))
	if app.chat.native_open: return
	app.queue_free()
	await process_frame
	quit(0 if success else 1)
