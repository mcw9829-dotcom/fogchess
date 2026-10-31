extends SceneTree
var app
var failures=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error("FAIL: "+message)
func run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	var auth = await app.api.request("/login",{"name":"LocalTester","pw":"Fixture-Password-492!"})
	app.session=auth.session; app.me=auth.user
	await preload("res://tests/admin_flow.gd").new().run(app,self,check)
	var support=preload("res://support(공지·제보·이의제기).gd").new(app)
	await support.announcements()
	check(is_instance_valid(support.window),"published notices open in game")
	support.window.queue_free()
	await process_frame
	await support.show_support()
	check(is_instance_valid(support.window),"own sanctions and appeals open")
	support.window.queue_free()
	print("ADMIN_FAILURES="+str(failures))
	quit(1 if failures else 0)
