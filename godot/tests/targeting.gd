extends SceneTree
var app: Control
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: "+message)
	else: failures += 1; push_error(message)
func capture(label: String) -> void:
	await create_timer(.18).timeout
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var folder := OS.get_environment("FOG_CAPTURE_DIR")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func own_piece(kind: String) -> Vector2i:
	for r in range(12):
		for c in range(12):
			var p: Variant = app.board.tile(Vector2i(r,c)).get("p")
			if p is Dictionary and p.get("t")==kind and p.get("o")=="W": return Vector2i(r,c)
	return Vector2i(-1,-1)
func choose(kind: String, mode: String) -> void:
	app._clear_selection()
	await app._select(own_piece(kind))
	app._choose_action(mode)
	check(app.board.targeting.active(),kind+" targeting activates")

func motion_capture(label: String, first: Vector2i, second: Vector2i) -> void:
	return # This review captures the full idle orbit below, instead of the earlier short demo.

func orbit_capture(label: String, target: Vector2i) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var layer = app.board.targeting
	layer.set_process(false)
	layer.motion_key = ""
	app.board.hover = target
	layer.advance_motion(.5)
	layer.motion_time = 0.0
	var tile_size: float = app.board.geometry().size.x/12.0
	var focus: Vector2 = layer.scan_cursor(target).center+app.board.geometry().position if label=="queen" else app.board.center(target)
	var region := Rect2(app.board.global_position+focus-Vector2.ONE*tile_size*2,Vector2.ONE*tile_size*4)
	var folder := OS.get_environment("FOG_ORBIT_FRAMES")
	DirAccess.make_dir_recursive_absolute(folder)
	for frame in range(1440):
		layer.advance_motion(1.0/60.0)
		layer.queue_redraw()
		await process_frame
		RenderingServer.force_draw(false)
		var picture := root.get_texture().get_image()
		picture.get_region(Rect2i(region)).save_png(folder.path_join("%s-orbit-%03d.png" % [label,frame]))
	layer.set_process(true)
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await create_timer(.25).timeout
	for child in app.get_children():
		if child is Timer: child.stop()
	app.audio.enabled = false
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	await choose("Q","scan")
	var layer = app.board.targeting
	check(is_zero_approx(layer.reticle_turn_angle(0)) and is_equal_approx(layer.reticle_turn_angle(12),TAU),"idle arcs complete one clockwise turn in twelve seconds")
	check(is_equal_approx(layer.reticle_turn_angle(18),PI) and is_zero_approx(layer.reticle_turn_angle(24)),"idle arcs return one full counterclockwise turn")
	check(layer.reticle_turn_angle(4)<layer.reticle_turn_angle(6) and layer.reticle_turn_angle(16)>layer.reticle_turn_angle(18),"rotation reverses direction during the second half")
	var original_view: Dictionary = app.board.view.duplicate(true)
	var original_targets: Array = app.board.targets.duplicate(true)
	var origin: Vector2i = app.board.selected
	var valid := origin+Vector2i(-4,1)
	check(app.board.contains(app.board.targets,valid),"queen preview uses a server-legal cell")
	app.board.hover = valid
	check(layer.aim_state(valid).valid,"legal scan cursor is valid")
	check(layer.scan_area(valid).size()==4,"scan cursor covers exactly four tiles")
	check(layer.scan_area(Vector2i(11,11)).size()==1,"corner scan clips to one tile")
	check(layer.scan_area(Vector2i(10,11)).size()==2,"edge scan clips to two tiles")
	check(app.board.contains(app.board.targets,origin+Vector2i(-4,4)),"server advertises newly legal circular diagonal")
	var scan_cursor: Dictionary = layer.scan_cursor(valid)
	var expected_center: Vector2 = (app.board.center(valid)+app.board.center(valid+Vector2i(1,1)))*.5-app.board.geometry().position
	check(scan_cursor.center.is_equal_approx(expected_center),"queen reticle is centered over all four tiles, not the anchor tile")
	layer.motion_key = ""
	layer.advance_motion(.06)
	check(layer.entry_amount()>0.0 and layer.entry_amount()<1.0,"creation phase progresses over time")
	layer.advance_motion(.3)
	check(is_equal_approx(layer.entry_amount(),1.0),"creation settles at exact range size")
	var old_age: float = layer.stage_age
	app.board.hover = valid+Vector2i(0,1)
	layer.advance_motion(.01)
	check(layer.stage_age>old_age and layer.hover_age<.02,"target changes react without restarting range creation")
	layer._on_target_pressed(app.board.hover)
	check(layer.press_age==0.0 and layer.response_amount()>0.0,"click starts a brief interaction response")
	layer.advance_motion(.3)
	check(is_zero_approx(layer.response_amount()),"interaction settles without lingering pulse")
	app.board.effects = false
	layer.advance_motion(.01)
	check(layer.entry_amount()==1.0 and layer.response_amount()==0.0,"effects off shows stable complete targeting")
	app.board.effects = true
	app.board.hover = valid
	await capture("queen-valid")
	var center_before: Vector2 = layer.scan_cursor(valid).center
	await orbit_capture("queen",valid)
	check(layer.scan_cursor(valid).center==center_before,"scan center remains fixed throughout the orbit")
	await motion_capture("queen",valid,valid+Vector2i(0,1))
	var outside := Vector2i(0,0)
	app.board.hover = outside
	var state: Dictionary = layer.aim_state(outside)
	check(not state.valid and state.clamped,"out-of-range scan is invalid and clamped visually")
	check(app.board.contains(app.board.targets,state.cell),"clamped cursor stays in the server range")
	check(app.board.hover==outside,"clamping never replaces the actual input cell")
	var turn: int = app.view.turnCount
	await app._tap(outside)
	check(app.view.turnCount==turn and not app.game_session.awaiting_state,"invalid click submits no action and spends no turn")
	check(app.board.targets==original_targets,"preview does not mutate server target list")
	check(app.board.view==original_view,"preview does not change fog or piece visibility")
	await capture("queen-invalid")
	app.board.hover = valid
	var white_footprint: Dictionary = layer.scan_area(valid)
	app.board.flip = true
	check(app.board.cell_at(app.board.center(valid))==valid,"black orientation preserves logical targeting")
	check(layer.scan_area(valid)==white_footprint,"scan coverage stays in board coordinates")
	await capture("queen-black")
	app.board.flip = false
	await choose("R","barrage")
	var last := Vector2i(-1,-1)
	for rc in app.board.targets:
		var cell := Vector2i(rc[0],rc[1])
		if cell.x<app.board.selected.x: last=cell
	if last.x<0: last=Vector2i(app.board.targets[0][0],app.board.targets[0][1])
	app.board.hover = last
	check(layer.aim_state(last).valid,"rook accepts server-valid firing direction")
	await capture("rook-lane")
	await motion_capture("rook",last,app.board.selected+Vector2i(0,1))
	app.board.hover = Vector2i(0,11)
	await capture("rook-outside")
	# A blocked ray may not clamp to another direction or cross the forest.
	var saved: Array = app.board.targets
	app.board.targets = [[app.board.selected.x-1,app.board.selected.y],[app.board.selected.x-2,app.board.selected.y]]
	state = layer.aim_state(app.board.selected+Vector2i(-5,0))
	check(state.cell==app.board.selected+Vector2i(-2,0) and not state.valid,"rook clamps at the last reachable tile")
	state = layer.aim_state(app.board.selected+Vector2i(0,3))
	check(state.cell==Vector2i(-1,-1) and not state.valid,"fully blocked direction has no false preview")
	app.board.targets = saved
	await choose("B","fire")
	check(not app.board.ranges.is_empty(),"bishop radius is available independently of visible targets")
	var enemy := Vector2i(app.board.targets[0][0],app.board.targets[0][1])
	app.board.hover = enemy
	check(layer.aim_state(enemy).valid,"bishop marks a visible server-approved enemy valid")
	await capture("bishop-valid")
	await orbit_capture("bishop",enemy)
	await motion_capture("bishop",enemy,Vector2i(0,0))
	var empty := Vector2i(-1,-1)
	for rc in app.board.ranges:
		var candidate := Vector2i(rc[0],rc[1])
		if not app.board.contains(app.board.targets,candidate): empty=candidate; break
	app.board.hover = empty
	check(not layer.aim_state(empty).valid,"empty in-range tile remains invalid for bishop")
	await capture("bishop-no-target")
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	app.board.colorblind = true
	app.board.hover = enemy
	check(layer.ink()!=layer.ink(false),"colorblind mode distinguishes valid and invalid states")
	await capture("bishop-light-colorblind")
	app.prefs.set_value("settings","light",false)
	app._apply_theme()
	app.board.colorblind = false
	app._clear_selection()
	check(not layer.active(),"clearing selection removes range dimming")
	app.board.view.scanTiles = [[3,3],[3,4],[4,3],[4,4]]
	check(layer.scan_groups(layer.cell_set([[3,3],[3,4],[4,3],[8,8]])).size()==2,"separate scans keep separate radar regions")
	check(layer.scan_groups(layer.cell_set([[3,3],[3,4],[4,3]]))[0].size()==3,"L-shaped scan never includes its unscanned corner")
	await capture("scan-coverage")
	app.board.fx.clear()
	app.board.fx.play({"type":"scan","cells":[[3,3],[3,4],[4,3],[4,4]]})
	check(app.board.fx.parts.all(func(part): return part.kind!="scan_frame"),"scan activation contains no four-tile square frames")
	await capture("scan-activation")
	if "--capture" in OS.get_cmdline_user_args():
		for frame in range(64):
			app.board.clock = frame*TAU/.75/64.0
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			var picture := root.get_texture().get_image()
			var tile_size: float = app.board.geometry().size.x/12.0
			var region := Rect2(app.board.global_position+app.board.center(Vector2i(3,3))-Vector2.ONE*tile_size,Vector2.ONE*tile_size*3)
			picture.get_region(Rect2i(region)).save_png(OS.get_environment("FOG_CAPTURE_DIR").path_join("scan-detail-%02d.png" % frame))
	app.board.effects = false
	await capture("scan-static")
	app.board.effects = true
	app.board.view.scanTiles = [[3,3],[3,4],[4,3],[11,11]]
	app.board.flip = true
	await capture("scan-clipped-black")
	app.board.flip = false
	app.board.view.scanTiles = []
	await choose("Q","scan")
	app.board.hover = app.board.selected+Vector2i(-3,0)
	root.size = Vector2i(390,844)
	app._layout()
	app._render()
	await capture("mobile-scan")
	check(layer.clip_contents and layer.mouse_filter==Control.MOUSE_FILTER_IGNORE,"overlay is clipped and never intercepts board input")
	app._choose_action("move")
	check(not layer.active(),"normal movement retains its original indicators without dimming")
	app.board.effects = true
	app.board.fx.reduced = false
	app.board.play_fx({"type":"barrage","confirmed_source":true,"from":[8,2],"cells":[[7,2],[6,2]]})
	check(not layer.ground_decal.is_empty() and not app.board.fx.timers.is_empty(),"confirmed rook shot draws ground decal before scheduled effect")
	await create_timer(.25).timeout
	check(layer.ground_decal.is_empty(),"confirmed ground decal expires automatically")
	layer.prepare_barrage([[7,2]])
	var other_room: Dictionary = app.board.view.duplicate(true)
	other_room.room = "another-room"
	app.board.set_view(other_room,false)
	check(layer.ground_decal.is_empty(),"room change clears previous firing footprint")
	app.queue_free()
	await process_frame
	print("TARGETING_CHECKS="+str(checks))
	print("TARGETING_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
