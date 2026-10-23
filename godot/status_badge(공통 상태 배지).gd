extends RefCounted
## One drawing definition for the on-board badges and tooltip headings.
static func exposure(canvas: CanvasItem, badge: Vector2, s: float) -> void:
	canvas.draw_circle(badge,s*.15,Color("#e69f00"))
	canvas.draw_line(badge+Vector2(0,-s*.075),badge+Vector2(0,s*.02),Color.BLACK,maxf(2,s*.04),true)
	canvas.draw_circle(badge+Vector2(0,s*.08),maxf(1,s*.022),Color.BLACK)
static func draw_reload(canvas: CanvasItem, badge: Vector2, s: float) -> void:
	canvas.draw_circle(badge,s*.16,Color("#286a85"))
	var badge_font := ThemeDB.fallback_font
	var badge_size := maxi(10,roundi(s*.30))
	var glyph_width := badge_font.get_string_size("?",HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size).x
	var baseline := (badge_font.get_ascent(badge_size)-badge_font.get_descent(badge_size))*.5
	canvas.draw_string(badge_font,badge+Vector2(-glyph_width*.5,baseline),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size,Color.WHITE)
