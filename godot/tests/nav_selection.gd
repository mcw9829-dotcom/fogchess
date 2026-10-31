extends SceneTree
var app: Control
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,text: String) -> void:
	checks+=1
	if ok: print("PASS: "+text)
	else: failures+=1;push_error(text)
func label() -> String:
	return str(app.ui_motion.selected.get_meta("nav_label"))
func nav(text: String) -> Button:
	for b in app.nav_buttons:
		if b.get_meta("nav_label")==text: return b
	return null
func dialog() -> Window:
	for c in app.get_children():
		if c is Window and c.visible: return c
	return null
func capture(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var path:=OS.get_environment("FOG_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(path)
	root.get_texture().get_image().save_png(path.path_join(name+".png"))
func close_dialog() -> void:
	dialog().close_requested.emit()
	await create_timer(.3).timeout
func run() -> void:
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.4).timeout
	for c in app.get_children():
		if c is Timer: c.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","lobby_music",false)
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	app._navigation_home()
	await create_timer(.35).timeout
	check(label()=="플레이","home selects play")
	var start: Vector2=app.ui_motion.nav_position
	app._help()
	await create_timer(.06).timeout
	check(label()=="기물 설명","opening help selects the help navigation item")
	var target: Vector2=nav("기물 설명").global_position
	var moving: Vector2=app.ui_motion.nav_position
	check(moving.y>start.y and moving.y<target.y,"play-to-help moves through the space between adjacent items")
	capture("help-entering")
	await create_timer(.35).timeout
	check(app.ui_motion.indicator.global_position.distance_to(target)<.5,"help indicator settles precisely on help")
	capture("help-selected")
	app._layout()
	await create_timer(.1).timeout
	check(label()=="기물 설명","layout cannot reset active help selection to play")
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	await create_timer(.1).timeout
	check(label()=="기물 설명","theme refresh retains help selection")
	await close_dialog()
	check(label()=="플레이","closing help returns selection to play")
	app._settings()
	await create_timer(.35).timeout
	check(label()=="설정","play-to-settings selection still works")
	app._help()
	await create_timer(.35).timeout
	check(label()=="기물 설명","opening help from settings selects help")
	await close_dialog()
	check(label()=="설정","closing help returns selection to settings")
	app._help()
	await create_timer(.02).timeout
	dialog().close_requested.emit()
	await create_timer(.4).timeout
	check(label()=="설정" and app.ui_motion.panels.is_empty(),"closing during help entrance leaves no stale selection or animation")
	app._navigation_home()
	var pair: Array=app._window("리더보드")
	await create_timer(.35).timeout
	check(label()=="리더보드","shared leaderboard dialog selects its own navigation item")
	var nested: Array=app._window("레이팅 규칙")
	await create_timer(.1).timeout
	check(label()=="리더보드","nested dialog inherits its navigation section")
	nested[0].hide()
	nested[0].queue_free()
	pair[0].show()
	await create_timer(.15).timeout
	check(label()=="리더보드","restored parent dialog retains its section")
	await close_dialog()
	check(label()=="플레이","closing leaderboard restores home selection")
	for width in [760,390]:
		root.size=Vector2i(width,844)
		await create_timer(.2).timeout
		app._help()
		await create_timer(.4).timeout
		check(label()=="기물 설명" and app.ui_motion.indicator.global_position.distance_to(nav("기물 설명").global_position)<.5,"help navigation remains aligned after resize "+str(width))
		await close_dialog()
	root.size=Vector2i(1440,900)
	await create_timer(.2).timeout
	app._settings()
	await create_timer(.35).timeout
	capture("settings-selected")
	check(label()=="설정","settings selection survives restoring desktop layout")
	for p in app.audio.get_children():
		if p is AudioStreamPlayer: p.stop()
	app.queue_free()
	await process_frame
	print("NAV_CHECKS=%d"%checks)
	print("NAV_FAILURES=%d"%failures)
	quit(0 if failures==0 else 1)
