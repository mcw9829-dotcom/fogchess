extends SceneTree
var app: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if value: print("PASS: "+message)
	else: failures+=1; push_error(message)
func settle() -> void:
	await process_frame
	await process_frame
	await create_timer(.3).timeout
func capture(label: String) -> void:
	await settle()
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://../.dev-data/setup-visual-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var picture := root.get_texture().get_image()
	picture.save_png(directory.path_join(label+".png"))
	var card: Control = app.ready_button.get_parent().get_parent()
	var rect := Rect2i(card.get_global_rect()).intersection(Rect2i(Vector2i.ZERO,root.size))
	if rect.size.x>0 and rect.size.y>0: picture.get_region(rect).save_png(directory.path_join(label+"-card.png"))
func action(button: Button) -> void:
	button.pressed.emit()
	await create_timer(.1).timeout
	for i in range(100):
		if not app.busy: break
		await create_timer(.03).timeout
	await settle()
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await settle()
	for child in app.get_children():
		if child is Timer: child.stop()
	await app._join({})
	var friend: Dictionary = await app.api.request("/join",{"room":app.room,"name":"상대 플레이어"})
	await app._poll()
	await settle()
	var ui = app.ui_shell.setup_ui
	check(ui.guide.is_visible_in_tree(),"placement diagram is shown during actual setup")
	check(not app.coach_label.visible,"redundant setup paragraph is removed")
	check(app.sound_button.text.is_empty() and not app.sound_button.accessibility_name.is_empty(),"sound icon keeps an accessible action name")
	check(app.sound_button.size.x>=44 and app.sound_button.size.y>=44,"sound icon retains a 44px hit target")
	check(app.resign_button.text=="기권" and not app.utility_actions.get_node("LeaveMatch").text.is_empty(),"destructive actions retain text labels")
	await capture("setup-dark")
	var initial: String = JSON.stringify(app.view.grid)
	await action(ui.placement_buttons[1])
	check(JSON.stringify(app.view.grid)!=initial,"shuffle icon button changes real server placement")
	await action(ui.placement_buttons[0])
	check(JSON.stringify(app.view.grid)==initial,"default layout button restores actual placement")
	await action(app.ready_button)
	check(app.view.get("ready",false) and app.view.get("phase")=="setup","ready button submits actual ready state and waits")
	check(ui.art.prepared and ui.title.text=="준비 완료","check illustration follows authoritative ready state")
	check(app.ready_button.accessibility_name=="준비 취소","ready action name changes to cancel")
	await capture("setup-ready")
	await action(app.ready_button)
	check(not app.view.get("ready",true) and not ui.art.prepared,"cancel restores editable placement guide")
	var audio_before: bool = app.audio.enabled
	app.sound_button.pressed.emit()
	check(app.audio.enabled!=audio_before and app.sound_button.text.is_empty(),"sound icon toggles actual audio without restoring long text")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	app.match_ui.render()
	await capture("setup-light")
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	for width in [390,320]:
		root.size = Vector2i(width,844)
		app._layout()
		await settle()
		app.controls_scroll.ensure_control_visible(app.ready_button)
		app.page_scroll.ensure_control_visible(app.ready_button)
		await settle()
		check(ui.guide.size.x<=width,"placement guide fits mobile width "+str(width))
		for button in ui.placement_buttons:
			check(button.get_global_rect().end.x<=width+1,"placement action remains in mobile viewport "+str(width))
		await capture("setup-mobile-"+str(width))
	root.size = Vector2i(1280,900)
	app._layout()
	await action(app.ready_button)
	await app.api.request("/action",{"room":app.room,"token":friend.token,"type":"ready","value":true})
	await app._poll()
	await settle()
	check(app.view.get("phase")=="play" and not ui.guide.visible,"placement illustration disappears when real match starts")
	check(app.coach_label.visible,"gameplay action guidance is restored")
	app.queue_free()
	await process_frame
	print("SETUP_VISUAL_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
