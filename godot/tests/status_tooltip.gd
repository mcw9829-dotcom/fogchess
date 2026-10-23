extends SceneTree
var app: Control
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, text: String) -> void:
	if value: print("PASS: "+text)
	else: failures+=1; push_error(text)
func hover(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	root.push_input(event,true)
	await create_timer(1.3).timeout
func find_card(node: Node) -> Control:
	if node.name=="BoardStatusTooltip" and node.is_visible_in_tree() and node.get_window().visible: return node
	for child in node.get_children(true):
		var found := find_card(child)
		if found!=null: return found
	return null
func capture(label: String, card: Control) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	RenderingServer.force_draw(false)
	var directory := ProjectSettings.globalize_path("res://../.dev-data/status-tooltip-captures")
	DirAccess.make_dir_recursive_absolute(directory)
	var picture := root.get_texture().get_image()
	picture.save_png(directory.path_join(label+".png"))
	if card!=null:
		var region := Rect2i(card.get_window().position-Vector2i(12,12),card.get_window().size+Vector2i(24,90)).intersection(Rect2i(Vector2i.ZERO,root.size))
		picture.get_region(region).save_png(directory.path_join(label+"-detail.png"))
func run() -> void:
	root.size = Vector2i(1280,900)
	app = load("res://main(게임 시작 씬).tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.get_children():
		if child is Timer: child.stop()
	var fixture: Dictionary = await app.api.request("/test-focus",{})
	app._enter(fixture)
	await app._poll()
	await create_timer(.3).timeout
	app._clear_selection()
	var board_size: Vector2 = app.board.size
	for flipped in [false,true]:
		app.board.flip = flipped
		app.board.queue_redraw()
		await process_frame
		var tile_size: float = app.board.geometry().size.x/12.0
		var badge: Vector2 = app.board.global_position+app.board.center(Vector2i(7,5))+Vector2(tile_size*.3,-tile_size*.3)
		await hover(badge)
		var card := find_card(root)
		check(card!=null,"native badge hover opens a custom card, flipped="+str(flipped))
		if card!=null:
			check(card.card_style.bg_color.a==1,"card surface is opaque")
			check(card.get_window().position.y+card.get_window().size.y<=badge.y-20,"tooltip stays above badge with cursor clearance")
			check(card.mouse_filter==Control.MOUSE_FILTER_IGNORE,"card does not intercept board clicks")
			await capture("exposure-"+str(flipped),card)
			var before: Array = app.board.view.exposed
			app.board.view.exposed = []
			await create_timer(.1).timeout
			check(not card.get_window().visible,"concealed piece dismisses stale status without pointer movement")
			app.board.view.exposed = before
		await hover(Vector2(4,4))
		check(find_card(root)==null,"leaving badge dismisses card")
	app.board.flip = false
	app.board.view["reloading"] = [{"pid":"W_B1"}]
	app.prefs.set_value("settings","light",true)
	app._apply_theme()
	var reload_size: float = app.board.geometry().size.x/12.0
	var reload_at: Vector2 = app.board.global_position+app.board.center(Vector2i(7,5))+Vector2(-reload_size*.3,-reload_size*.3)
	await hover(reload_at)
	var reload_card := find_card(root)
	check(reload_card!=null,"reload badge opens a card in light theme")
	if reload_card!=null:
		check(not reload_card.exposure and "이동은 가능합니다" in reload_card.message,"reload card preserves distinct movement clarification")
		check(reload_card.get_window().position.y+reload_card.get_window().size.y<reload_at.y-20,"reload card clears the pointer")
		await capture("reload-light",reload_card)
	await hover(Vector2(4,4))
	var tip = load("res://status_tooltip(상태 설명 카드).gd")
	for at in [Vector2(5,5),Vector2(315,5),Vector2(5,800),Vector2(315,800)]:
		var position: Vector2 = tip.placement(at,Vector2(246,112),Vector2(320,844))
		check(Rect2(Vector2.ZERO,Vector2(320,844)).encloses(Rect2(position,Vector2(246,112))),"card remains inside narrow viewport at "+str(at))
		check(not Rect2(position,Vector2(246,112)).has_point(at),"edge fallback does not cover pointer "+str(at))
	check(app.board.size==board_size,"tooltip does not alter board size")
	app.queue_free()
	await process_frame
	print("STATUS_TOOLTIP_FAILURES="+str(failures))
	quit(0 if failures==0 else 1)
