extends SceneTree
var app: Control
var captured: Array = []
func _initialize() -> void: run.call_deferred()
func shot(name: String, note: String="") -> void:
	await create_timer(.38).timeout
	await raw_shot(name,note)
func raw_shot(name: String,note: String="") -> void:
	await process_frame
	RenderingServer.force_draw(false)
	var folder:=OS.get_environment("FOG_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
	captured.append({"file":name+".png","width":root.size.x,"height":root.size.y,"note":note})
	print("CAPTURE: "+name)
func close_windows() -> void:
	for child in app.get_children():
		if child is Window: child.hide();child.queue_free()
	await create_timer(.1).timeout
func theme(light: bool) -> void:
	app.prefs.set_value("settings","light",light)
	app._apply_theme()
func own_piece(kind: String) -> Vector2i:
	for r in range(12):
		for c in range(12):
			var p=app.board.tile(Vector2i(r,c)).get("p")
			if p is Dictionary and p.get("t")==kind and p.get("o")=="W": return Vector2i(r,c)
	return Vector2i(-1,-1)
func choose(kind: String, action: String) -> void:
	app._clear_selection()
	await app._select(own_piece(kind))
	app._choose_action(action)
func run() -> void:
	root.size=Vector2i(1280,900)
	app=load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled=false
	app.prefs.set_value("settings","lobby_music",false)
	await app.community._load_home_ranks()
	for light in [false,true]:
		theme(light)
		var suffix: String="light" if light else "dark"
		app._navigation_home()
		await shot("home-"+suffix,"Fresh current build; isolated server has an empty leaderboard.")
		app._help()
		await shot("help-"+suffix)
		await close_windows()
		app._settings()
		await shot("settings-"+suffix)
		app._navigation_home()
		await app._leaderboard()
		await shot("leaderboard-"+suffix,"Empty ranking state in test server, not production account data.")
		await close_windows()
		app._feedback()
		await shot("feedback-"+suffix)
		await close_windows()
	theme(false)
	for width in [390,320]:
		root.size=Vector2i(width,844)
		app._navigation_home()
		app._layout()
		app.page_scroll.scroll_vertical=0
		await shot("home-mobile-"+str(width))
		app._help()
		await shot("help-mobile-"+str(width))
		await close_windows()
	root.size=Vector2i(1280,900)
	app._layout()
	await app._join({})
	await app.api.request("/join",{"room":app.room,"name":"상대 플레이어"})
	await app._poll()
	await shot("setup-dark","Real setup in an isolated temporary room.")
	theme(true)
	await shot("setup-light")
	theme(false)
	root.size=Vector2i(390,844)
	app._layout()
	app.page_scroll.scroll_vertical=0
	await shot("setup-mobile-top")
	app.page_scroll.ensure_control_visible(app.ready_button)
	await shot("setup-mobile-controls")
	app._return_home()
	root.size=Vector2i(1280,900)
	var fixture: Dictionary=await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	app._message("")
	await shot("battle-dark","Controlled battle fixture with representative captures/history/exposure; not a live user match.")
	theme(true)
	await shot("battle-light")
	theme(false)
	await choose("N","move")
	await shot("piece-actions")
	await choose("Q","scan")
	app.board.hover=app.board.selected+Vector2i(-4,1)
	await shot("queen-valid")
	app.board.hover=Vector2i(0,0)
	await shot("queen-invalid")
	await choose("B","fire")
	app.board.hover=Vector2i(4,8)
	await shot("bishop-valid")
	app.board.hover=Vector2i(3,7)
	await shot("bishop-invalid")
	await choose("R","barrage")
	app.board.hover=app.board.selected+Vector2i(-3,0)
	await shot("rook-aim")
	app._clear_selection()
	app.board.view.scanTiles=[[3,3],[3,4],[4,3],[4,4]]
	await shot("scan-surveillance","Scan tiles injected only into review fixture to inspect the persistent radar representation.")
	app.board.view.scanTiles=[]
	for effect in ["fire","barrage","scan"]:
		app.board.fx.clear()
		var data: Dictionary={"type":effect,"from":[7,5],"cells":[[4,8]]}
		if effect=="barrage": data={"type":"barrage","from":[9,2],"cells":[[8,2],[7,2],[6,2],[5,2]]}
		if effect=="scan": data={"type":"scan","from":[11,7],"cells":[[3,3],[3,4],[4,3],[4,4]],"extra":[[3,4]]}
		app.board.play_fx(data)
		for index in range(4):
			await create_timer(.08 if index==0 else .16).timeout
			await raw_shot("fx-"+effect+"-"+str(index),"Controlled effect sample at successive frames; not proof of event order in a live match.")
	app.board.fx.clear()
	for width in [390,320]:
		root.size=Vector2i(width,844)
		app._layout()
		app._render()
		app.page_scroll.scroll_vertical=0
		await choose("B","fire")
		app.board.hover=Vector2i(4,8)
		await shot("battle-mobile-"+str(width))
		app.page_scroll.scroll_vertical=600
		await shot("records-mobile-"+str(width))
	app.page_scroll.scroll_vertical=0
	root.size=Vector2i(1280,900)
	app._layout()
	app._clear_selection()
	app.ui_components.confirm_action("기권 후 나가기","기권 패배로 종료한 뒤 홈으로 돌아갑니다.","기권 후 홈으로",func(): pass)
	await shot("confirmation")
	await close_windows()
	app.view["phase"]="over"
	app.view["winner"]="W"
	app._render()
	await shot("result-victory","Result presentation using a review fixture; no game result submitted.")
	theme(true)
	await shot("result-victory-light","Light theme result fixture; no game result submitted.")
	var output:=FileAccess.open(OS.get_environment("FOG_CAPTURE_DIR").path_join("manifest.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify(captured,"\t"))
	output.close()
	for p in app.audio.get_children():
		if p is AudioStreamPlayer: p.stop()
	app.queue_free()
	await process_frame
	print("AUDIT_CAPTURE_COMPLETE="+str(captured.size()))
	quit()
