extends SceneTree
var app: Control
var failures := 0
var commands := 0
const Motion = preload("res://calm_motion(차분한 깊이 모션 기준).gd")
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error(message)
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := ProjectSettings.globalize_path("res://../.dev-data/calm-motion-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func open_dialog() -> Window:
	app.ui_components.confirm_action("기권 후 나가기","기권 패배로 종료한 뒤 홈으로 돌아갑니다.","기권 후 홈으로",func(): commands+=1)
	return app.get_node("GameConfirmation")
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	var last := 0.0
	var monotonic := true
	for i in range(101):
		var value := Motion.ease(i/100.0)
		if value<last or value<0 or value>1: monotonic=false
		last=value
	check(monotonic and Motion.ease(0)==0 and Motion.ease(1)==1,"approved easing has no bounce or overshoot")
	var d := open_dialog()
	await create_timer(.06).timeout
	check(d.visible and d.panel.modulate.a>.2 and d.panel.modulate.a<1,"popup enters with visible spatial motion")
	await capture("entering")
	await create_timer(.4).timeout
	check(d.panel.scale==Vector2.ONE and d.panel.modulate.a==1,"popup settles to full size and opacity")
	check(d.panel.position.is_equal_approx(Vector2.ZERO),"popup finishes at layout origin")
	await capture("settled")
	d.get_cancel_button().pressed.emit()
	check(d.finished and d.is_input_disabled(),"closing immediately locks duplicate input")
	await create_timer(.05).timeout
	check(is_instance_valid(d) and d.visible and d.panel.modulate.a<1,"popup has a visible exit phase")
	await capture("leaving")
	await create_timer(.25).timeout
	check(not is_instance_valid(d) and commands==0,"cancel finishes without issuing command")
	d = open_dialog()
	d.get_ok_button().pressed.emit()
	d.get_ok_button().pressed.emit()
	check(commands==1,"accept dispatches immediately and exactly once")
	await create_timer(.3).timeout
	check(not is_instance_valid(d),"accept disposes dialog after exit")
	d = open_dialog()
	await create_timer(.02).timeout
	d.get_cancel_button().pressed.emit()
	await create_timer(.35).timeout
	check(not is_instance_valid(d) and app.ui_motion.panels.is_empty(),"exit interrupts unfinished entrance cleanly")
	var pair: Array = app._window("대국 안내")
	await create_timer(.03).timeout
	pair[0].close_requested.emit()
	pair[0].close_requested.emit()
	await create_timer(.3).timeout
	check(not is_instance_valid(pair[0]),"shared popup close is animated and idempotent")
	app._settings()
	app._navigation_home()
	app._settings()
	await create_timer(.4).timeout
	check(app.subpage.visible and not app.home.visible,"rapid screen changes keep the latest screen")
	check(app.subpage.scale==Vector2.ONE and app.subpage.modulate.a==1 and app.ui_motion.panels.is_empty(),"screen motion settles without stale transitions")
	for width in [390,320]:
		root.size = Vector2i(width,844)
		app._layout()
		d = open_dialog()
		await create_timer(.08).timeout
		root.size.y = 780
		app._layout()
		await create_timer(.4).timeout
		check(d.size.x<=width-24 and d.panel.position.is_equal_approx(Vector2.ZERO),"popup follows resize during motion "+str(width))
		d.get_cancel_button().pressed.emit()
		await create_timer(.3).timeout
	check(app.ui_motion.panels.is_empty(),"all motion work is cleared after dismissal")
	app.queue_free()
	await process_frame
	print("CALM_MOTION_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
