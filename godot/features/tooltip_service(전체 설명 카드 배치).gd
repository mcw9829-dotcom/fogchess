extends Node
## Rich tooltips belong to the visible match; ordinary screens do not show hover popups.
const Design = preload("res://tooltip_design(공통 설명 카드 디자인).gd")
const StatusCard = preload("res://status_tooltip(상태 설명 카드).gd")
var app: Control
func _init(context: Control) -> void:
	app = context
func _in_match() -> bool:
	return is_instance_valid(app.game) and app.game.is_visible_in_tree() and not app.home.visible and not app.subpage.visible
var pending: Array[PopupPanel] = []
var active: Array = []
var mouse_points: Dictionary = {}
class PointerTracker extends Node:
	var sink: Callable
	func _input(event: InputEvent) -> void:
		if event is InputEventMouseMotion: sink.call(get_viewport(),event.position)
func _ready() -> void:
	get_tree().node_added.connect(_node_added)
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion: _remember_pointer(get_viewport(),event.position)
func _node_added(node: Node) -> void:
	if node is PopupPanel:
		pending.append(node)
		_adopt.call_deferred(node)
	elif node is Window: _watch_window.call_deferred(node)
func _watch_window(window: Window) -> void:
	if not is_instance_valid(window) or window.has_node("TooltipPointerTracker"): return
	var tracker := PointerTracker.new()
	tracker.name = "TooltipPointerTracker"
	tracker.sink = _remember_pointer
	window.add_child(tracker)
func _remember_pointer(viewport: Viewport, point: Vector2) -> void:
	mouse_points[viewport.get_instance_id()] = point
func _suppressed(popup: PopupPanel) -> bool:
	if not _in_match(): return true
	var ancestor: Node = popup.get_parent()
	while ancestor!=null:
		if ancestor.get_meta("suppress_hover_tooltips",false): return true
		ancestor = ancestor.get_parent()
	return false
func _adopt(popup: PopupPanel) -> void:
	pending.erase(popup)
	if not is_instance_valid(popup) or popup.theme_type_variation!="TooltipPanel": return
	if _suppressed(popup):
		# Keep authored tooltip text available for accessibility and shared controls,
		# but suppress the native hover window outside the match.
		popup.hide()
		return
	# A custom board tooltip already has a header, icon and its own positioner.
	for child in popup.get_children():
		if child.name=="BoardStatusTooltip": return
	var label: Label
	for child in popup.get_children():
		if child is Label: label = child; break
	if label==null: return
	popup.add_theme_stylebox_override("panel",Design.surface())
	label.add_theme_font_override("font",Design.font())
	label.add_theme_font_size_override("font_size",16)
	label.add_theme_color_override("font_color",Design.INK)
	label.add_theme_constant_override("line_spacing",3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := popup.get_parent().get_viewport()
	var max_width: float = minf(264,viewport.get_visible_rect().size.x-52)
	var measured: float = Design.font().get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
	label.custom_minimum_size.x = minf(max_width,maxf(20,measured))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Godot's native tooltip cached its original unwrapped minimum before adoption.
	popup.min_size = Vector2i.ZERO
	popup.size = Vector2i.ZERO
	var at: Vector2 = mouse_points.get(viewport.get_instance_id(),viewport.get_mouse_position())
	# Nested Windows render their tooltips in the ancestor viewport that embeds subwindows.
	while not viewport.gui_embed_subwindows and viewport.get_parent()!=null:
		if viewport is Window: at += Vector2(viewport.position)
		var parent_viewport: Viewport = viewport.get_parent().get_viewport()
		if parent_viewport==viewport: break
		viewport = parent_viewport
	active.append({"popup":popup,"viewport":viewport,"anchor":at})
	_position.call_deferred()
func _position() -> void:
	for entry in active.duplicate():
		if not is_instance_valid(entry.popup): active.erase(entry); continue
		var popup: PopupPanel = entry.popup
		if not _in_match():
			popup.hide()
			active.erase(entry)
			continue
		if not popup.visible: continue
		popup.position = Vector2i(StatusCard.placement(entry.anchor,Vector2(popup.size),entry.viewport.get_visible_rect().size))
func _process(_delta: float) -> void:
	_position()
