extends SceneTree
var board: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
	else: print("PASS: "+message)
func snapshot(kind: String="N") -> Dictionary:
	var grid: Array = []
	for r in range(12):
		var row: Array = []
		for c in range(12): row.append({"t":0,"f":0,"p":null})
		grid.append(row)
	grid[6][6].p = {"t":kind,"o":"W","id":"W_test"}
	return {"room":"motion-test","yourColor":"W","phase":"play","turn":"W","grid":grid}
func shot(name: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://tests/"+name+".png")
func run() -> void:
	root.size = Vector2i(640,640)
	board = load("res://board(보드·기물·이동 연출).gd").new()
	root.add_child(board)
	board.position = Vector2(30,30)
	board.size = Vector2(580,580)
	await process_frame
	board.set_view(snapshot(),false)
	var action := {"type":"move","cells":[[6,6]],"from":[8,5],"to":[6,6],"motion_piece":{"t":"N","o":"W"},"confirmed_source":true}
	board.play_fx(action)
	check(not board.piece_motion.is_empty(),"confirmed knight move animates sprite")
	check(board.fx.parts.is_empty() and not board.fx.timers.is_empty(),"landing waits for piece arrival")
	await create_timer(.10).timeout
	check(board._moving_at(Vector2i(6,6)),"destination sprite suppressed during flight")
	await shot("motion_knight")
	await create_timer(.30).timeout
	check(board.piece_motion.is_empty(),"piece settles at authoritative destination")
	check(not board.fx.parts.is_empty(),"landing pulse emitted after arrival")
	board.fx.clear()
	board.play_fx(action)
	var hidden := snapshot(); hidden.grid[6][6].p = null; hidden.grid[6][6].f = 1
	board.set_view(hidden,false)
	check(board.piece_motion.is_empty(),"new hidden snapshot immediately removes moving sprite")
	board.play_fx(action)
	check(board.piece_motion.is_empty(),"concealed destination cannot start sprite motion")
	board.set_view(snapshot(),false)
	board.effects = false
	board.play_fx(action)
	check(board.piece_motion.is_empty(),"effects disabled preserves immediate state")
	board.effects = true; board.fx.reduced = true
	board.play_fx(action)
	check(board.piece_motion.is_empty(),"reduced motion disables sprite travel")
	board.fx.reduced = false
	for kind in ["capture","fire","barrage","scan"]:
		board.fx.clear()
		board.play_fx({"type":kind,"cells":[[5,6],[5,7],[6,6],[6,7]] if kind=="scan" else [[6,6]],"from":[8,6],"confirmed_source":true})
		await create_timer(.10).timeout
		check(not board.fx.parts.is_empty(),kind+" produces visible effect")
		await shot("enhanced_"+kind)
	board.fx.clear()
	check(board.fx.parts.is_empty() and board.fx.timers.is_empty(),"clear removes particles and deferred impact callbacks")
	var brush := snapshot()
	brush.grid[6][6].t = 3
	brush.grid[8][5].t = 3
	board.set_view(brush,false)
	board.play_fx(action)
	check(board.brush_reactions.has(Vector2i(6,6)) and board.brush_reactions.has(Vector2i(8,5)),"confirmed bush entry and exit animate foliage")
	board.effects = false
	await create_timer(.05).timeout
	check(board.brush_reactions.is_empty(),"effects off removes foliage motion")
	board.effects = true
	var unconfirmed := action.duplicate(true)
	unconfirmed.confirmed_source = false
	board.play_fx(unconfirmed)
	check(board.brush_reactions.is_empty(),"unconfirmed source cannot reveal bush movement")
	board.queue_free()
	await process_frame
	print("MOTION_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
