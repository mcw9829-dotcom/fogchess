extends SceneTree
var app
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ")+title)
func panels() -> Array:
	return app.find_children("*","VBoxContainer",true,false).filter(func(n): return n.get_script()==preload("res://admin(관리자 화면).gd"))
func open_settings() -> Button:
	app._settings()
	await create_timer(.35).timeout
	var button: Button=app.subpage.find_child("SettingsVersion",true,false)
	app.page_scroll.ensure_control_visible(button)
	await process_frame
	return button
func close_admin() -> void:
	for panel in panels(): panel.get_window().queue_free()
	await process_frame
func click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.position=button.get_global_rect().get_center()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate();event.pressed=false
	root.push_input(event)
	await process_frame
func touch(button: Button) -> void:
	var event := InputEventScreenTouch.new()
	event.position=button.get_global_rect().get_center()
	event.index=0;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=event.duplicate();event.pressed=false
	Input.parse_input_event(event)
	await process_frame
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	await create_timer(.2).timeout
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func run() -> void:
	root.size=Vector2i(1120,760)
	app=load("res://main(게임 시작 씬).tscn").instantiate();root.add_child(app)
	await create_timer(.6).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	var button: Button=await open_settings()
	app.rail_version.text="v1.55 · 패치노트"
	app.settings._refresh_version_footer()
	check(button.text=="v1.55","footer follows the available server version")
	check(not app.subpage.find_children("*","Button",true,false).any(func(b): return b.text=="관리자"),"public admin button removed")
	check(button.size.y>=44 and button.size.x>=120,"version has usable tap area")
	for i in range(4): await click(button)
	check(panels().is_empty(),"four clicks do not reveal login")
	await click(button)
	check(panels().size()==1,"fifth mouse click reveals one login")
	if panels().size()==1:
		check(panels()[0].key.is_empty(),"hidden entry grants no administrator authentication")
	await shot("admin-login")
	await close_admin()
	for i in range(4): await click(button)
	await create_timer(5.1).timeout
	await click(button)
	check(panels().is_empty(),"expired sequence starts again at one")
	for i in range(3): await click(button)
	check(panels().is_empty(),"expired sequence cannot open early")
	app._navigation_home();await process_frame
	# Show the same settings node again: visibility changes must clear its sequence.
	app.home.hide();app.subpage.show();await process_frame
	app.page_scroll.ensure_control_visible(button);await process_frame
	await click(button)
	check(panels().is_empty(),"leaving settings clears an incomplete sequence")
	button=await open_settings()
	for i in range(4): await click(button)
	button=await open_settings()
	await click(button)
	check(panels().is_empty(),"rebuilt settings never inherit tap count")
	for light in [false,true]:
		app.prefs.set_value("settings","light",light);app._apply_theme()
		check(button.get_theme_stylebox("hover") is StyleBoxEmpty,"version stays unadorned after theme change")
		await shot("settings-"+("light" if light else "dark"))
	root.size=Vector2i(390,844);app._layout()
	button=await open_settings()
	check(button.get_global_rect().end.y<=844-20,"mobile version reachable at bottom")
	Input.emulate_mouse_from_touch=true
	for i in range(4): await touch(button)
	check(panels().is_empty(),"four touches count once each")
	await touch(button)
	check(panels().size()==1,"fifth touch opens one login")
	await close_admin()
	await shot("settings-mobile")
	print("LOBBY_CHECKS="+str(checks))
	print("LOBBY_FAILURES="+str(failures))
	app.queue_free();await process_frame;await process_frame
	quit(failures)
