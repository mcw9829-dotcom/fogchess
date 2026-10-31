extends RefCounted
## One drawing definition for the on-board badges and tooltip headings.
static func exposure(canvas: CanvasItem, badge: Vector2, s: float) -> void:
	var radius := maxf(6.5,s*.15)
	canvas.draw_circle(badge,radius+1,Color("#252b2e"))
	canvas.draw_circle(badge,radius,Color("#e69f00"))
	canvas.draw_line(badge+Vector2(0,-radius*.52),badge+Vector2(0,radius*.08),Color.BLACK,maxf(1.6,radius*.25),true)
	canvas.draw_circle(badge+Vector2(0,radius*.53),maxf(.9,radius*.15),Color.BLACK)
static func draw_reload(canvas: CanvasItem, badge: Vector2, s: float) -> void:
	var radius := maxf(6.5,s*.16)
	canvas.draw_circle(badge,radius+1,Color("#252b2e"))
	canvas.draw_circle(badge,radius,Color("#286a85"))
	var badge_font := ThemeDB.fallback_font
	var badge_size := maxi(10,roundi(radius*1.7))
	var glyph_width := badge_font.get_string_size("?",HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size).x
	var baseline := (badge_font.get_ascent(badge_size)-badge_font.get_descent(badge_size))*.5
	canvas.draw_string(badge_font,badge+Vector2(-glyph_width*.5,baseline),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,badge_size,Color.WHITE)
