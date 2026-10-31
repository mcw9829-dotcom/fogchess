extends SceneTree
var app
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: "+label)
	else: failures += 1; push_error(label)
func shot(name: String) -> void:
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join(name+".png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.3).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	for scenario in [["B","fire",5,7],["R","barrage",5,6],["Q","scan",5,7],["N","move",4,7]]:
		var fixture: Dictionary = await app.api.request("/test-fixture",{"scenario":"piece_"+scenario[0]})
		app._enter(fixture)
		await app._poll()
		for attempt in range(80):
			if not app.ui_motion.is_transition_busy(): break
			await create_timer(.05).timeout
		await app._select(Vector2i(6,6))
		await app._act({"type":scenario[1],"pid":"W_"+scenario[0]+"1","r":scenario[2],"c":scenario[3]})
		await app._act({"type":"resign"})
		if app.view.get("replayId")==null: check(false,"fixture saved "+scenario[1]); continue
		await app.replay.open(app.view.replayId,app.token)
		var replay = app.replay
		var target := -1
		for i in range(replay.data.frames.size()):
			var action: Variant = replay.data.frames[i].get("action")
			if action is Dictionary and action.get("action")==scenario[1]: target = i; break
		check(target>0,"recorded real action "+scenario[1])
		if target<0: replay.close(); continue
		var full: Dictionary = replay._frame_effect(target,"all")
		check(not full.is_empty(),"full-view effect exists "+scenario[1])
		var origin: Variant = full.get("from")
		check(origin is Array and origin.size()==2 and int(origin[0])==6 and int(origin[1])==6,"full-view exact origin "+scenario[1]+" "+str(origin))
		var own: Dictionary = replay._frame_effect(target,"W")
		check(own.get("confirmed_source",false),"own exact origin allowed "+scenario[1])
		var enemy: Dictionary = replay._frame_effect(target,"B")
		var saved: Variant = replay.data.frames[target].perspectives.B.get("fx")
		check(not enemy.has("from") and not enemy.has("motion_piece") and not enemy.get("confirmed_source",false),"opponent cannot reconstruct origin "+scenario[1])
		check(enemy.is_empty() if saved==null else enemy.get("cells")==saved.get("cells"),"opponent effect matches recorded visibility "+scenario[1])
		replay.seek(target-1)
		replay.next_button.pressed.emit()
		check(not app.board.fx.parts.is_empty() or not app.board.fx.timers.is_empty(),"next button plays effect "+scenario[1])
		await create_timer(.10 if scenario[1]=="fire" else .25).timeout
		await shot("replay-effect-"+scenario[1])
		replay.vision = "B"
		replay.show_frame()
		check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty() and app.board.piece_motion.is_empty(),"perspective change clears old effects "+scenario[1])
		replay.vision = "all"
		replay.seek(target-1)
		replay.toggle()
		await create_timer(1.55).timeout
		check(replay.index==target and (not app.board.fx.parts.is_empty() or not app.board.fx.timers.is_empty()),"autoplay plays effect "+scenario[1])
		replay.seek(target-1)
		check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty(),"seeking clears effects "+scenario[1])
		replay.jump_event(1)
		check(replay.index==target and (not app.board.fx.parts.is_empty() or not app.board.fx.timers.is_empty()),"major event plays selected effect "+scenario[1])
		app.board.effects = false
		replay.seek(target-1)
		replay.step(1)
		check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty(),"effects preference respected "+scenario[1])
		app.board.effects = true
		var legacy: Dictionary = replay.data.frames[target].duplicate(true)
		replay.data.frames[target].erase("perspectives")
		check(replay._frame_effect(target,"all").is_empty(),"missing historical effects handled safely "+scenario[1])
		replay.data.frames[target] = legacy
		replay.close()
		check(app.board.fx.parts.is_empty() and app.board.fx.timers.is_empty(),"closing clears replay effect "+scenario[1])
	print("REPLAY_EFFECT_CHECKS=",checks)
	print("REPLAY_FAILURES=",failures)
	quit(1 if failures else 0)
