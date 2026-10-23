extends SceneTree
const Icon = preload("res://original_icon(원본 스타일 아이콘).gd")
var app: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if ok: print("PASS: "+message)
	else: failures+=1; push_error(message)
func capture(label: String) -> void:
	await create_timer(.4).timeout
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := ProjectSettings.globalize_path("res://../.dev-data/icon-theme-captures")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func verify_tree(parent: Node, light: bool) -> int:
	var count := 0
	for child in parent.get_children():
		if child.get_script()==Icon:
			count+=1
			check(child.texture!=null and child.texture.resource_path==Icon.asset_path(child.key,light),"visible icon follows theme: "+child.key+" / "+str(light))
		count+=verify_tree(child,light)
	return count
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	for light in [false,true]:
		for key in ["rank","lobby","replay","watch","join","computer","practice","settings","book","trophy","chat","user","easy","normal","hard","accept","decline"]:
			var texture = load(Icon.asset_path(key,light))
			check(texture is Texture2D and texture.get_width()==96,key+" variant loads: "+str(light))
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	await process_frame
	check(verify_tree(app,false)>8,"menu and sidebar icons are covered")
	await capture("menu-dark")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	await process_frame
	verify_tree(app,true)
	await capture("menu-light")
	var pair: Array = app._small_window("아이콘 크기 비교 · 64 / 40 / 26px",1000,360)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation",12)
	pair[1].add_child(grid)
	for spec in [["rank","랭크"],["practice","혼자 연습"],["replay","리플레이"],["join","친구 방 참가"],["settings","설정"]]:
		var box: VBoxContainer = app._card(grid,"")
		app._label(box,spec[1],16)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",6)
		box.add_child(row)
		for dimension in [64,40,26]: app._icon(row,spec[0],dimension)
	await process_frame
	check(verify_tree(pair[0],true)==15,"new modal icons inherit the light theme")
	await capture("detail-light")
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	await process_frame
	check(verify_tree(pair[0],false)==15,"open modal icons switch back to dark")
	verify_tree(app,false)
	await capture("detail-dark")
	pair[0].queue_free()
	await process_frame
	root.size = Vector2i(390,844)
	app._layout()
	await capture("menu-mobile")
	for card in app.mode_cards:
		check(card.size.y>=card.get_node("ModeCardContent").get_combined_minimum_size().y,"mobile card contains description: "+str(card.get_meta("action_title")))
	app.queue_free()
	await process_frame
	print("ICON_THEME_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
