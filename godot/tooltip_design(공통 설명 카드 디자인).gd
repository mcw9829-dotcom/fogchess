extends RefCounted
## Shared by native UI hints and the board's structured status cards.
const INK = Color("302a23")
const TITLE_INK = Color("211c16")
static var fonts: Dictionary = {}
static func font(weight: int=500) -> Font:
	if not fonts.has(weight):
		var face := FontVariation.new()
		face.base_font = load("res://fonts/NotoSansKR.ttf")
		face.variation_opentype = {2003265652:weight}
		fonts[weight] = face
	return fonts[weight]
static func surface() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f0e2c6")
	style.border_color = Color("957342")
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.shadow_color = Color(0,0,0,.3)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0,3)
	for edge in ["left","right"]: style.set("content_margin_"+edge,14.0)
	for edge in ["top","bottom"]: style.set("content_margin_"+edge,11.0)
	return style
static func apply(design: Theme) -> void:
	design.set_stylebox("panel","TooltipPanel",surface())
	design.set_font("font","TooltipLabel",font())
	design.set_font_size("font_size","TooltipLabel",16)
	design.set_color("font_color","TooltipLabel",INK)
	design.set_color("font_shadow_color","TooltipLabel",Color.TRANSPARENT)
	design.set_constant("line_spacing","TooltipLabel",3)
