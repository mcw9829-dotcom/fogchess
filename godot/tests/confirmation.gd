extends SceneTree
var app: Control
var failures := 0
var commands := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error(message)
func settle() -> void: await create_timer(.7).timeout
func dialog() -> Window: return app.get_node("GameConfirmation")
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := ProjectSettings.globalize_path("res://../.dev-data/confirmation-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	var picture := root.get_texture().get_image()
	picture.save_png(folder.path_join(label+".png"))
	var window := dialog()
	picture.get_region(Rect2i(window.position,window.size)).save_png(folder.path_join(label+"-detail.png"))
func open_confirmation(title: String="기권 후 나가기",message: String="기권 패배로 종료한 뒤 홈으로 돌아갑니다.") -> void:
	app.ui_components.confirm_action(title,message,"기권 후 홈으로" if title.contains("기권") else "홈으로",func(): commands+=1)
	await settle()
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await settle()
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	for light in [false,true]:
		app.prefs.set_value("settings","light",light)
		app._apply_theme()
		for width in [1280,390,320]:
			root.size = Vector2i(width,900 if width==1280 else 844)
			app._layout()
			await settle()
			await open_confirmation()
			var d := dialog()
			check(d.get_cancel_button().has_focus(),"safe action starts focused "+str([light,width]))
			check(d.size.x<=width-24 and d.size.y<=root.size.y-24,"dialog fits viewport "+str([light,width]))
			check(is_instance_valid(d.shade) and d.shade.visible,"background dim shown")
			check(not d.get_ok_button().get_global_rect().intersects(d.get_cancel_button().get_global_rect()),"actions do not overlap")
			for node in [d.get_ok_button(),d.get_cancel_button(),d.find_child("ConfirmationTitle",true,false),d.find_child("ConfirmationDescription",true,false)]:
				check(Rect2(Vector2.ZERO,Vector2(d.size)).encloses(node.get_global_rect()),"content stays inside dialog: "+node.name)
			await capture(("light" if light else "dark")+"-"+str(width))
			d.get_cancel_button().pressed.emit()
			await settle()
			check(not is_instance_valid(d),"cancel dismisses dialog")
	check(commands==0,"opening and canceling never issues action")
	await open_confirmation()
	var d := dialog()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	d.push_input(esc,true)
	await settle()
	check(not is_instance_valid(d) and commands==0,"Escape cancels without action")
	await open_confirmation()
	d = dialog()
	d.find_child("ConfirmationClose",true,false).pressed.emit()
	await settle()
	check(not is_instance_valid(d) and commands==0,"close cross cancels without action")
	await open_confirmation()
	d = dialog()
	d.get_ok_button().pressed.emit()
	d.get_ok_button().pressed.emit()
	await settle()
	check(commands==1,"rapid accept dispatches exactly once")
	root.size = Vector2i(1280,900)
	app._layout()
	await settle()
	await open_confirmation("나가기","대국을 나가 홈으로 돌아갈까요?")
	d = dialog()
	check(d.get_ok_button().get_meta("ui_role")=="secondary","safe exit is not styled as resignation")
	await capture("safe-exit")
	root.size = Vector2i(320,480)
	app._layout()
	await settle()
	check(d.size.x<=296 and d.size.y<=456,"open dialog follows window resize")
	d.get_cancel_button().pressed.emit()
	await settle()
	app.queue_free()
	await process_frame
	print("CONFIRMATION_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
