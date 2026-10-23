extends SceneTree
var app: Control
var failures := 0
var activations := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if value: print("PASS: "+message)
	else: failures += 1; push_error(message)
func wait_frames() -> void:
	await process_frame
	await process_frame
	await create_timer(.08).timeout
func capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var dir := ProjectSettings.globalize_path("res://../.dev-data/material-captures")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join(label+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await wait_frames()
	for child in app.get_children():
		if child is Timer: child.stop()
	var button: Button = app.game_ux.learn_button
	var effect = button.get_node("MaterialMotion")
	check(effect!=null,"home CTA has Standard motion")
	check(effect.mouse_filter==Control.MOUSE_FILTER_IGNORE,"decoration never intercepts input")
	var before: Rect2 = button.get_global_rect()
	var board_before: Vector2 = app.board.size
	var initial_min: Vector2 = button.get_combined_minimum_size()
	button.pressed.connect(func(): activations+=1)
	effect._down()
	effect.add_ripple(Vector2(8,8))
	await create_timer(.09).timeout
	check(effect.amount>.5,"press spring visibly responds")
	check(button.get_theme_stylebox("normal").expand_margin_left<0,"only drawn surface compresses")
	check(button.get_global_rect()==before,"press leaves native hit rectangle fixed")
	check(button.get_combined_minimum_size()==initial_min,"press does not reflow its container")
	check(app.board.size==board_before,"UI motion does not resize the board")
	check(activations==0,"decoration cannot execute a game command")
	await capture("pressed")
	effect.cancel()
	await create_timer(.7).timeout
	check(is_zero_approx(effect.amount) and effect.ripples.is_empty(),"cancel settles shape and removes ripple")
	check(not effect.is_processing(),"settled buttons stop processing")
	check(is_zero_approx(button.get_theme_stylebox("normal").expand_margin_left),"surface returns to original bounds")
	effect._down()
	button.disabled = true
	await wait_frames()
	check(effect.amount==0 and effect.ripples.is_empty(),"disable during press clears decoration")
	button.disabled = false
	effect._down()
	effect._up()
	effect._down()
	effect._up()
	await create_timer(.7).timeout
	check(effect.amount==0 and activations==0,"rapid press reversal neither sticks nor fires callbacks")
	effect.confirm()
	check(effect.confirmation>0,"confirmed action has a one-shot accent")
	await create_timer(.3).timeout
	check(effect.confirmation==0,"confirmation settles without a repeated pulse")
	var native_a := Button.new()
	var native_b := Button.new()
	app.add_child(native_a)
	app.add_child(native_b)
	var shared_style := StyleBoxFlat.new()
	native_a.add_theme_stylebox_override("normal",shared_style)
	native_b.add_theme_stylebox_override("normal",shared_style)
	native_a.size = Vector2(100,44)
	app.ui_motion.attach(native_a)
	native_a.get_node("MaterialMotion")._down()
	await create_timer(.1).timeout
	check(native_b.get_theme_stylebox("normal").expand_margin_left==0,"press never mutates another button's shared theme")
	native_a.queue_free()
	native_b.queue_free()
	var target: Button
	for nav in app.nav_buttons:
		if nav.get_meta("nav_label")=="설정": target = nav
	app._nav_active("설정")
	check(app.ui_motion.selected==target,"navigation logical selection changes immediately")
	await create_timer(.6).timeout
	check(app.ui_motion.indicator.global_position.distance_to(target.global_position)<.1,"selection indicator settles at selected item")
	check(app.ui_motion.indicator is Node2D,"selection indicator has no GUI hit target")
	check(app.ui_motion.indicator.get_index()<target.get_index(),"selection indicator draws behind button text")
	app._nav_active("플레이")
	app._nav_active("설정")
	await create_timer(.6).timeout
	check(app.ui_motion.indicator.global_position.distance_to(target.global_position)<.1,"fast navigation retarget keeps latest destination")
	app._nav_active("플레이")
	await create_timer(.6).timeout
	await capture("home")
	var pair: Array = app._window("Material 모션 검증")
	app._label(pair[1],"정돈된 Material · 버튼과 팝업",16)
	app._button(pair[1],"계속하기",func(): pair[0].queue_free(),"primary")
	await create_timer(.08).timeout
	check(not app.ui_motion.panels.is_empty(),"popup begins a spatial transition")
	check(pair[0].visible,"popup is available during its transition")
	await capture("menu-entering")
	await create_timer(.7).timeout
	await capture("menu-settled")
	pair[0].queue_free()
	await wait_frames()
	pair = app._window("즉시 닫기 검증")
	await create_timer(.03).timeout
	pair[0].queue_free()
	await wait_frames()
	check(not is_instance_valid(pair[0]),"closing never waits for entrance completion")
	await create_timer(.7).timeout
	check(app.ui_motion.panels.is_empty(),"closed popup leaves no stale animation")
	root.size = Vector2i(390,844)
	app._layout()
	await create_timer(.7).timeout
	check(app.ui_motion.indicator.size.x<=root.size.x,"mobile navigation indicator fits viewport")
	check(app.ui_motion.indicator.global_position.distance_to(app.ui_motion.selected.global_position)<.2,"indicator follows mobile reflow")
	await capture("mobile")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await wait_frames()
	check(button.get_theme_stylebox("normal").bg_color==app.ui_components._palette().accent,"theme refresh retains button role")
	await capture("light")
	root.size = Vector2i(1280,900)
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	app._settings()
	await create_timer(.7).timeout
	var toggle = app.find_child("Setting_sound",true,false)
	var toggle_rect: Rect2 = toggle.get_global_rect()
	var initial: bool = toggle.button_pressed
	toggle.button_pressed = not initial
	check(app.prefs.get_value("settings","sound")==not initial,"switch updates actual setting immediately")
	await create_timer(.6).timeout
	check(toggle.travel==(0.0 if initial else 1.0),"switch thumb settles at actual setting")
	check(toggle.get_global_rect()==toggle_rect,"switch motion keeps hit area fixed")
	toggle.button_pressed = initial
	toggle.button_pressed = not initial
	toggle.button_pressed = initial
	await create_timer(.6).timeout
	check(toggle.travel==(1.0 if initial else 0.0) and not toggle.is_processing(),"rapid switch toggles settle and stop processing")
	await capture("settings-dark")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await wait_frames()
	await capture("settings-light")
	app.queue_free()
	await process_frame
	print("MATERIAL_UI_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
