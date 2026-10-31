extends CanvasLayer
## Presentation only. Original containers, live board and server state never move.
signal preparation_timed_out
const PREPARATION_TIMEOUT := 10.0
const DURATION := 1.3
const BOARD_START := .2
const BOARD_END := .7666667
const MAP_END := .9333333
const RETURN_FOG_START := .06
const RETURN_FOG_END := .40
const RETURN_RESULT_END := .18
var app
var phase := "idle"
var direction := ""
var progress := 0.0
var completed_count := 0
var serial := 0
var stage: Control
var capture_view: SubViewport
var freeze: TextureRect
var queue_badge: TextureRect
var return_result: TextureRect
var map: Control
var menu: TextureRect
var caption: TextureRect
var caption_base := Vector2.ZERO
var lobby_board: Control
var match_board: Control
var board_surround: Control
var coordinate_board: Control
var capture_material: CanvasItemMaterial
var from_rect := Rect2()
var to_rect := Rect2()
var viewport_size := Vector2.ZERO
var source_visible := false
var menu_distance := 0.0
var hud: Array = []
var side_cards: Array = []
var elapsed := 0.0
var preparation_elapsed := 0.0
var skip_first_tick := false
var expected_room := ""
var saved_game_view: Dictionary = {}
var saved_flip := false
var saved_fog_strength := 1.0

func _init(context: Control) -> void:
	app = context
	layer = 90

func _ready() -> void:
	set_process(false)
	set_process_input(false)

func is_busy() -> bool:
	return phase != "idle"

func _input(_event: InputEvent) -> void:
	if is_busy(): get_viewport().set_input_as_handled()

func _clean_view(value: Dictionary) -> Dictionary:
	var data := value.duplicate(true)
	for key in ["token", "session", "password", "adminKey"]: data.erase(key)
	return data

func _rect(node: Control) -> Rect2:
	# Same root canvas, no transformed live containers. Geometry retains board margins.
	var transform := node.get_global_transform_with_canvas()
	return Rect2(transform.origin, transform.basis_xform(node.size)).abs()

func _capture_world(include_queue: bool = false) -> Image:
	# The queue is global status, not part of the moving lobby or game HUD.
	# Modulate preserves its layout slot while excluding its pixels from captures.
	var queue: Control = app.lobby_status.queue_card
	var queue_ink: Color = queue.modulate
	if not include_queue: queue.modulate.a = 0.0
	capture_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.force_draw(false)
	var pixels := capture_view.get_texture().get_image()
	queue.modulate = queue_ink
	return pixels

func _image_rect(pixels: Image, box: Rect2) -> Rect2:
	# Preserve capture pixels at rest; fractional crops must not scale the texture.
	var snapped := Rect2(box.position.floor(), box.end.ceil() - box.position.floor())
	return snapped.intersection(Rect2(Vector2.ZERO, Vector2(pixels.get_size())))

func _art(pixels: Image, box: Rect2, parent: Node = null) -> TextureRect:
	var clipped := _image_rect(pixels, box)
	if clipped.size.x < 1 or clipped.size.y < 1: return null
	var node := TextureRect.new()
	if capture_material == null:
		capture_material = CanvasItemMaterial.new()
		capture_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	node.material = capture_material
	node.texture = ImageTexture.create_from_image(pixels.get_region(Rect2i(clipped)))
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else stage).add_child(node)
	node.position = clipped.position
	node.size = clipped.size
	return node

func _capture_opacity(node: CanvasItem, opacity: float) -> void:
	# Captures contain premultiplied RGB. Fade RGB and alpha together.
	node.modulate = Color(opacity, opacity, opacity, opacity)

func _screen_art(pixels: Image, box: Rect2) -> TextureRect:
	# Root captures contain physical pixels on HiDPI web screens. Crop in those
	# pixels, then place the image in the same logical coordinates as the live UI.
	var density := Vector2(pixels.get_size()) / viewport_size
	var node := _art(pixels, Rect2(box.position * density, box.size * density))
	if is_instance_valid(node):
		node.position /= density
		node.size /= density
	return node

func _draw_board_surround() -> void:
	if is_instance_valid(coordinate_board): coordinate_board.draw_surround(board_surround)

func _setup() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	# Capture BEFORE creating our CanvasLayer contents. This masks all preparation.
	RenderingServer.force_draw(false)
	var initial: Image = get_viewport().get_texture().get_image()
	stage = Control.new()
	stage.name = "MatchTransitionSurface"
	stage.size = viewport_size
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.theme = app.theme
	add_child(stage)
	var fill := ColorRect.new()
	fill.color = RenderingServer.get_default_clear_color()
	fill.color.a = 1.0
	fill.size = viewport_size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fill)
	var lobby = app.ui_shell.lobby_home
	map = lobby.backdrop.get_script().new()
	stage.add_child(map)
	map.size = viewport_size
	map.set_light(bool(app.prefs.get_value("settings", "light", false)))
	map.phase = lobby.backdrop.phase
	map.set_process(false)
	map.motion_layer.queue_redraw()
	board_surround = Control.new()
	board_surround.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_surround.draw.connect(_draw_board_surround)
	stage.add_child(board_surround)
	freeze = _screen_art(initial, Rect2(Vector2.ZERO, viewport_size))
	capture_view = SubViewport.new()
	capture_view.size = Vector2i(viewport_size)
	capture_view.transparent_bg = true
	capture_view.world_2d = get_viewport().world_2d
	capture_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(capture_view)
	capture_view.canvas_transform = get_viewport().canvas_transform
	if app.lobby_status.queue_card.is_visible_in_tree():
		# A separate stationary, transparent capture survives the whole round trip.
		var backdrop_visible: bool = lobby.backdrop.visible
		lobby.backdrop.hide()
		queue_badge = _art(_capture_world(true), _rect(app.lobby_status.queue_card))
		lobby.backdrop.visible = backdrop_visible
		if is_instance_valid(queue_badge): queue_badge.z_index = 100
	set_process(true)
	set_process_input(true)

func _new_board(data: Dictionary, flipped: bool) -> Control:
	var board = app.Board.new()
	stage.add_child(board)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.effects = false
	board.show_surround = false
	board.colorblind = bool(app.prefs.get_value("settings", "colorblind", false))
	board.set_view(_clean_view(data), flipped)
	board.fog_display_strength = 0.0 if direction == "entry" else 1.0
	board.fog_alpha.clear()
	board.set_process(false)
	board.fx.set_process(false)
	board.targeting.set_process(false)
	board.fx.clear()
	board.targeting.clear_decal()
	return board

func _capture_lobby() -> void:
	var lobby = app.ui_shell.lobby_home
	source_visible = lobby.preview_board.is_visible_in_tree()
	menu_distance = _rect(lobby.menu_column).end.x + 28.0 if source_visible else viewport_size.x
	if source_visible: from_rect = _rect(lobby.preview_board)
	var was_visible: bool = lobby.backdrop.visible
	lobby.backdrop.hide()
	var old_modulate: Color = lobby.preview_column.modulate
	lobby.preview_column.modulate.a = 0.0
	var pixels := _capture_world()
	lobby.preview_column.modulate = old_modulate
	menu = _art(pixels, Rect2(Vector2.ZERO, viewport_size))
	# Menu's full viewport texture is transparent outside the menu region.
	if is_instance_valid(menu): stage.move_child(menu, 2)
	if source_visible:
		var menu_modulate: Color = lobby.menu_column.modulate
		lobby.menu_column.modulate.a = 0.0
		# The frame shadow extends below the board control. Exclude it from
		# caption capture; the shared surround already renders it once.
		var preview_modulate: Color = lobby.preview_board.modulate
		lobby.preview_board.modulate.a = 0.0
		pixels = _capture_world()
		lobby.preview_board.modulate = preview_modulate
		lobby.menu_column.modulate = menu_modulate
		var box := Rect2(Vector2(from_rect.position.x, from_rect.end.y), Vector2(from_rect.size.x, minf(90, viewport_size.y - from_rect.end.y)))
		caption = _art(pixels, box)
		if is_instance_valid(caption):
			caption_base = caption.position
			stage.move_child(caption, 3)
	lobby.backdrop.visible = was_visible

func _masked(pixels: Image, box: Rect2, start: float, finish: float, fade_only: bool = false) -> void:
	var clipped := _image_rect(pixels, box)
	if clipped.size.x < 1 or clipped.size.y < 1: return
	var mask := Control.new()
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.clip_contents = true
	stage.add_child(mask)
	mask.position = clipped.position
	mask.size = clipped.size
	var node := _art(pixels, clipped, mask)
	node.position = Vector2.ZERO
	hud.append({"node": node, "mask": mask, "base": clipped.position, "extent": clipped.size, "start": start, "finish": finish, "fade_only": fade_only})

func _bands(pixels: Image) -> Array:
	var bands: Array = []
	var first := -1
	var last := -1
	for y in range(pixels.get_height()):
		var occupied := false
		for x in range(2, pixels.get_width() - 2, 4):
			if pixels.get_pixel(x, y).a > .02:
				occupied = true
				break
		if occupied:
			if first < 0: first = y
			last = y
		elif first >= 0 and y - last >= 9:
			var top := maxi(0, first - 2)
			bands.append(Rect2(0, top, pixels.get_width(), mini(pixels.get_height(), last + 3) - top))
			first = -1
	if first >= 0:
		var top := maxi(0, first - 2)
		bands.append(Rect2(0, top, pixels.get_width(), mini(pixels.get_height(), last + 3) - top))
	return bands

func _capture_game() -> void:
	to_rect = _rect(app.board)
	var lobby = app.ui_shell.lobby_home
	var map_visible: bool = lobby.backdrop.visible
	lobby.backdrop.hide()
	var board_modulate: Color = app.board.modulate
	app.board.modulate.a = 0.0
	var pixels := _capture_world()
	app.board.modulate = board_modulate
	lobby.backdrop.visible = map_visible
	var left := _rect(app.game_left)
	_masked(pixels, Rect2(left.position, Vector2(left.size.x, maxf(0, to_rect.position.y - left.position.y))), MAP_END, 74.0 / 60.0)
	_masked(pixels, _rect(app.match_ui.chrome), 58.0 / 60.0, 76.0 / 60.0)
	_masked(pixels, _rect(app.ui_shell.self_panel), 1.0, DURATION)
	if app.notice.is_visible_in_tree():
		_masked(pixels, _rect(app.notice), 1.0, DURATION, true)
	var side := _image_rect(pixels, _rect(app.side_panel))
	if side.size.x < 1 or side.size.y < 1: return
	var side_pixels := pixels.get_region(Rect2i(side))
	var bands := _bands(side_pixels)
	for i in range(bands.size()):
		var band: Rect2 = bands[i]
		var box := Rect2(side.position + band.position, band.size)
		var node := _art(pixels, box)
		var delay := minf(i * 2.0 / 60.0, .1)
		side_cards.append({"node": node, "base": node.position, "start": MAP_END + delay, "finish": 1.2 + delay})

func prepare_entry() -> bool:
	cancel()
	if DisplayServer.get_name() == "headless": return false
	if not app.home.is_visible_in_tree() or app.game.visible: return false
	phase = "preparing"
	direction = "entry"
	expected_room = str(app.room)
	_setup()
	_capture_lobby()
	lobby_board = _new_board(app.ui_shell.lobby_home._illustration(), false)
	stage.move_child(freeze, stage.get_child_count() - 1)
	return true

func start_entry() -> void:
	if phase != "preparing" or direction != "entry": return
	phase = "layout"
	var stamp := serial
	await get_tree().process_frame
	await get_tree().process_frame
	if stamp != serial or not is_instance_valid(stage): return
	if not app.game.visible or not app.view.has("grid") or str(app.room) != expected_room:
		cancel()
		return
	_capture_game()
	match_board = _new_board(app.view, app.seat == "B")
	# Both native boards must remain below the HUD proxy layers.
	stage.move_child(lobby_board, mini(4, stage.get_child_count() - 1))
	stage.move_child(match_board, mini(5, stage.get_child_count() - 1))
	if not source_visible:
		from_rect = Rect2(to_rect.get_center() - to_rect.size * .47 + Vector2(0, 12), to_rect.size * .94)
		lobby_board.set_view(_clean_view(app.view), app.seat == "B")
		lobby_board.fog_display_strength = 0.0
		lobby_board.fog_alpha.clear()
	_start()

func prepare_return() -> bool:
	cancel()
	if DisplayServer.get_name() == "headless": return false
	if not app.game.is_visible_in_tree() or not app.view.has("grid"): return false
	phase = "preparing"
	direction = "return"
	saved_game_view = _clean_view(app.view)
	saved_flip = app.seat == "B"
	saved_fog_strength = app.board.fog_display_strength
	_setup()
	_capture_game()
	lobby_board = _new_board(app.ui_shell.lobby_home._illustration(), false)
	lobby_board.fog_display_strength = 0.0
	match_board = _new_board(saved_game_view, saved_flip)
	match_board.fog_display_strength = saved_fog_strength
	# Retain the visible result on the stationary board, then let it fade away.
	# Cropping just this region avoids ghosting the outgoing HUD.
	if app.result_panel.is_visible_in_tree():
		return_result = _screen_art(freeze.texture.get_image(), _rect(app.result_panel))
	stage.move_child(lobby_board, 2)
	stage.move_child(match_board, 3)
	stage.move_child(freeze, stage.get_child_count() - 1)
	return true

func begin_return() -> void:
	if phase != "preparing" or direction != "return": return
	phase = "layout"
	var stamp := serial
	await get_tree().process_frame
	await get_tree().process_frame
	if stamp != serial or not is_instance_valid(stage): return
	if not app.home.visible:
		cancel()
		return
	_capture_lobby()
	if not source_visible:
		from_rect = Rect2(to_rect.get_center() - to_rect.size * .47 + Vector2(0, 12), to_rect.size * .94)
		lobby_board.set_view(saved_game_view, saved_flip)
		lobby_board.fog_display_strength = saved_fog_strength
		lobby_board.fog_alpha.clear()
	_start()

func _start() -> void:
	elapsed = 0.0
	preparation_elapsed = 0.0
	progress = 0.0
	phase = "playing"
	# One frame/shadow surrounds the two crossfading board contents throughout.
	stage.move_child(board_surround, 2)
	stage.move_child(lobby_board, 3)
	stage.move_child(match_board, 4)
	skip_first_tick = true
	_pose(DURATION if direction == "return" else 0.0)
	if is_instance_valid(freeze):
		freeze.hide()
		freeze.queue_free()
	freeze = null

func refresh_view() -> void:
	if direction != "entry" or not is_instance_valid(match_board) or not app.view.has("grid"): return
	if str(app.room) != expected_room:
		cancel()
		return
	match_board.set_view(_clean_view(app.view), app.seat == "B")
	match_board.fog_display_strength = 0.0
	match_board.fog_alpha.clear()
	match_board.queue_redraw()

func _curve(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _bezier(value: float, x1: float, y1: float, x2: float, y2: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	if x <= 0.0 or x >= 1.0: return x
	var lo := 0.0
	var hi := 1.0
	for i in range(14):
		var t := (lo + hi) * .5
		var bx := 3.0 * (1.0 - t) * (1.0 - t) * t * x1 + 3.0 * (1.0 - t) * t * t * x2 + t * t * t
		if bx < x: lo = t
		else: hi = t
	var t := (lo + hi) * .5
	return 3.0 * (1.0 - t) * (1.0 - t) * t * y1 + 3.0 * (1.0 - t) * t * t * y2 + t * t * t

func _pose(time: float) -> void:
	if direction == "return":
		var return_time := DURATION - time
		if source_visible:
			# Restore brightness before swapping match contents for lobby artwork.
			# This is independent from the approved entry timing and board path.
			var clear_t := _curve((return_time - RETURN_FOG_START) / (RETURN_FOG_END - RETURN_FOG_START))
			match_board.fog_display_strength = saved_fog_strength * (1.0 - clear_t)
		if is_instance_valid(return_result):
			_capture_opacity(return_result, 1.0 - _curve(return_time / RETURN_RESULT_END))
			return_result.visible = return_time < RETURN_RESULT_END
		# The real map is already running behind the transition; use its clock.
		map.phase = app.ui_shell.lobby_home.backdrop.phase
		map.motion_layer.queue_redraw()
	var menu_t := _bezier(time / .2, .45, 0.0, .70, .45)
	var board_t := _bezier((time - BOARD_START) / (BOARD_END - BOARD_START), .40, 0.0, .22, 1.0)
	if is_instance_valid(menu):
		menu.position.x = -menu_distance * menu_t
	if is_instance_valid(caption):
		var caption_t := _curve(time / (10.0 / 60.0))
		_capture_opacity(caption, 1.0 - caption_t)
		caption.position = caption_base + Vector2(-12.0 * caption_t, 0)
	var box := Rect2(from_rect.position.lerp(to_rect.position, board_t), from_rect.size.lerp(to_rect.size, board_t))
	for board in [lobby_board, match_board]:
		if not is_instance_valid(board): continue
		board.position = box.position
		board.size = box.size
		board.queue_redraw()
	# Crossfade contents only. Frame, shadow and coordinates are drawn once.
	var content_t := _curve((time - BOARD_END) / .08)
	match_board.modulate.a = content_t
	lobby_board.visible = content_t < 1.0
	match_board.visible = content_t > 0.0
	coordinate_board = match_board if content_t >= .5 else lobby_board
	board_surround.position = box.position
	board_surround.size = box.size
	board_surround.modulate.a = 1.0
	board_surround.queue_redraw()
	var map_t := _curve((time - BOARD_END) / (MAP_END - BOARD_END))
	map.modulate.a = 1.0 - map_t
	if not source_visible:
		var visible_t := _curve((time - BOARD_START) / .18)
		lobby_board.modulate.a = visible_t
		match_board.modulate.a *= visible_t
		board_surround.modulate.a = visible_t
	for part in side_cards:
		var t := _bezier((time - part.start) / (part.finish - part.start), .20, 0.0, .20, 1.0)
		part.node.position = part.base + Vector2((viewport_size.x + 24.0 - part.base.x) * (1.0 - t), 0)
		part.node.visible = t > 0.0
	for part in hud:
		var t := _bezier((time - part.start) / (part.finish - part.start), .20, 0.0, .20, 1.0)
		if part.fade_only:
			part.mask.position = part.base
			part.mask.size = part.extent
			part.node.position = Vector2.ZERO
			_capture_opacity(part.node, t)
			part.mask.visible = t > 0.0
			continue
		var width: float = part.extent.x * t
		part.mask.position = part.base + Vector2(part.extent.x - width, 0)
		part.mask.size = Vector2(maxf(.01, width), part.extent.y)
		part.node.position = Vector2(-part.extent.x + width + 24.0 * (1.0 - t), 0)
		_capture_opacity(part.node, lerpf(.35, 1.0, t))
		part.mask.visible = t > 0.0

func _process(delta: float) -> void:
	if not is_busy(): return
	if get_viewport().get_visible_rect().size != viewport_size:
		cancel()
		return
	if phase != "playing":
		preparation_elapsed += delta
		if preparation_elapsed >= PREPARATION_TIMEOUT:
			cancel()
			preparation_timed_out.emit()
		return
	# Capture preparation can be expensive; never charge that frame to motion.
	if skip_first_tick:
		skip_first_tick = false
		return
	elapsed = minf(DURATION, elapsed + delta)
	progress = elapsed / DURATION
	_pose(DURATION - elapsed if direction == "return" else elapsed)
	if elapsed >= DURATION: _complete()

func _complete() -> void:
	var arrived: bool = direction == "entry" and app.game.visible and app.view.has("grid") and str(app.room) == expected_room
	completed_count += 1
	cancel()
	# Movement/HUD handoff is finished. The live board now brings in its fog.
	if arrived: app.board.begin_fog_arrival()
	progress = 1.0

func cancel() -> void:
	serial += 1
	set_process(false)
	set_process_input(false)
	if is_instance_valid(stage):
		stage.hide()
		stage.queue_free()
	if is_instance_valid(capture_view):
		capture_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		capture_view.queue_free()
	stage = null
	capture_view = null
	freeze = null
	queue_badge = null
	return_result = null
	map = null
	menu = null
	caption = null
	lobby_board = null
	match_board = null
	board_surround = null
	coordinate_board = null
	hud.clear()
	side_cards.clear()
	saved_game_view.clear()
	expected_room = ""
	phase = "idle"
	direction = ""
	elapsed = 0.0
	preparation_elapsed = 0.0
	progress = 0.0
