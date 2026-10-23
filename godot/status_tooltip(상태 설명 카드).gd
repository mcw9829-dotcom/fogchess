extends PanelContainer
const Design = preload("res://tooltip_design(공통 설명 카드 디자인).gd")
const Badges = preload("res://status_badge(공통 상태 배지).gd")
## Opaque status card. Godot owns tooltip creation, hover timing and dismissal.
var source: Control
var message := ""
var cell := Vector2i(-1,-1)
var exposure := true
var anchor := Vector2.ZERO
var card_style: StyleBoxFlat
var title_label: Label
var body_label: Label

class BadgeView extends Control:
	var exposed := true
	func _draw() -> void:
		if exposed: Badges.exposure(self,size*.5,22.0/.30)
		else: Badges.draw_reload(self,size*.5,22.0/.32)

func _init(board: Control, text: String) -> void:
	source = board
	message = text
	exposure = not "재장전" in text
	cell = source.hover
	name = "BoardStatusTooltip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_style = Design.surface()
	add_theme_stylebox_override("panel",card_style)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation",7)
	add_child(content)
	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_theme_constant_override("separation",8)
	content.add_child(heading)
	var badge := BadgeView.new()
	badge.name = "SharedStatusBadge"
	badge.exposed = exposure
	badge.custom_minimum_size = Vector2(24,24)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(badge)
	var title := Label.new()
	title_label = title
	title.text = "위치 노출" if exposure else "재장전"
	title.add_theme_font_override("font",Design.font(700))
	title.add_theme_font_size_override("font_size",18)
	title.add_theme_color_override("font_color",Design.TITLE_INK)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(title)
	var body := Label.new()
	body_label = body
	body.text = "상대에게 이 기물의\n위치가 보입니다." if exposure else "사격 후 내 차례 한 턴 동안\n재장전합니다. 이동은 가능합니다."
	body.add_theme_font_override("font",Design.font(500))
	body.add_theme_font_size_override("font_size",16)
	body.add_theme_color_override("font_color",Design.INK)
	body.add_theme_constant_override("line_spacing",3)
	var cap: float = minf(264,source.get_viewport_rect().size.x-52)
	body.custom_minimum_size.x = minf(cap,maxf(168,Design.font().get_multiline_string_size(body.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(body)
	accessibility_name = ("위치 노출. " if exposure else "재장전. ")+text

func _ready() -> void:
	# Remove the native dark wrapper; this card supplies the opaque surface.
	get_window().add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	_place.call_deferred()

static func placement(at: Vector2, dimensions: Vector2, viewport_size: Vector2) -> Vector2:
	var point := Vector2(at.x-dimensions.x*.5,at.y-dimensions.y-28)
	if point.y<12: point.y = at.y+38
	point.x = clampf(point.x,12,maxf(12,viewport_size.x-dimensions.x-12))
	point.y = clampf(point.y,12,maxf(12,viewport_size.y-dimensions.y-12))
	return point.round()

func _place() -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree() or cell.x<0: return
	var tile_size: float = source.geometry().size.x/12.0
	var badge: Vector2 = source.center(cell)+Vector2(tile_size*(.3 if exposure else -.3),-tile_size*.3)
	anchor = source.get_global_transform_with_canvas()*badge
	var popup := get_window()
	popup.position = Vector2i(placement(anchor,Vector2(popup.size),source.get_viewport_rect().size))

func _process(_delta: float) -> void:
	if not is_instance_valid(source) or not source.is_visible_in_tree():
		get_window().hide()
		return
	var tile_size: float = source.geometry().size.x/12.0
	var badge: Vector2 = source.center(cell)+Vector2(tile_size*(.3 if exposure else -.3),-tile_size*.3)
	if source.hover!=cell or source.get_tooltip(badge)!=message:
		get_window().hide()
		return
	_place()
