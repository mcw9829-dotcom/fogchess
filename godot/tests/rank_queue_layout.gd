extends SceneTree
var app
var failures := 0
var rows: Array = []
func _initialize(): run.call_deferred()
func settle():
	app._layout()
	await create_timer(.4).timeout
	app._layout()
	await create_timer(.2).timeout
func geometry() -> Dictionary:
	var lobby = app.ui_shell.lobby_home
	return {"headline_font":lobby.headline.get_theme_font_size("font_size"),"rank_font":lobby.captions.rank.get_theme_font_size("font_size"),"rank_height":lobby.headers.rank.size.y,"preview_width":lobby.preview_board.size.x,"brand_visible":lobby.brand.visible,"viewport":str(root.size),"queue_height":app.lobby_status.reserved_height()}
func shot(label: String):
	if not "--capture" in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(label+".png"))
func run():
	root.size=Vector2i(1440,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.5).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","lobby_music",false)
	app.lobby_status.set_process(false)
	app.ui_shell.lobby_home.select_section("rank",false)
	for dims in [Vector2i(1440,900),Vector2i(1120,760),Vector2i(1920,1080),Vector2i(390,844)]:
		root.size=dims
		app.matching=false
		app.lobby_status.set_queue({})
		await settle()
		var before=geometry()
		shot(str(dims.x)+"-before")
		app.matching=true
		app.lobby_status.set_queue({"state":"waiting","waited":1,"queue":1})
		await settle()
		var during=geometry()
		shot(str(dims.x)+"-waiting")
		var stable=before.headline_font==during.headline_font and before.rank_font==during.rank_font and absf(before.rank_height-during.rank_height)<.5 and (dims.x<730 or absf(before.preview_width-during.preview_width)<.5) and before.brand_visible==during.brand_visible
		if not stable: failures+=1
		var queue_fits=Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.lobby_status.queue_card.get_global_rect())
		app.page_scroll.ensure_control_visible(app.ui_shell.lobby_home.headers.account)
		await create_timer(.2).timeout
		var account_reachable=app.page_scroll.get_global_rect().encloses(app.ui_shell.lobby_home.headers.account.get_global_rect())
		if not queue_fits or not account_reachable: failures+=1
		rows.append({"before":before,"waiting":during,"stable":stable,"queue_fits":queue_fits,"account_reachable":account_reachable})
		app.page_scroll.scroll_vertical=0
		app.matching=false
		app.lobby_status.set_queue({})
		await settle()
		if geometry()!=before: failures+=1
	print("RANK_LAYOUT_RESULTS="+JSON.stringify(rows))
	print("RANK_LAYOUT_FAILURES="+str(failures))
	print("LOBBY_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
