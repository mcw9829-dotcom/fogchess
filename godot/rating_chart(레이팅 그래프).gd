extends Control
var values: Array[float] = []
func _ready() -> void:
	custom_minimum_size = Vector2(200,44)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
func _draw() -> void:
	if values.size()<2: return
	var low: float = values.min()
	var span := maxf(float(values.max())-low,20)
	var line := PackedVector2Array()
	for i in range(values.size()): line.append(Vector2(float(i)/(values.size()-1)*size.x,size.y-(values[i]-low)/span*(size.y-10)-5))
	draw_polyline(line,Color("388c3a") if values.back()>=values.front() else Color("d6302c"),2,true)
	for point in line: draw_circle(point,2.2,Color("c69a5e"))
	var last := line[line.size()-1]
	draw_string(get_theme_default_font(),Vector2(minf(last.x,size.x-30),last.y+14 if last.y<14 else last.y-6),str(int(values.back())),HORIZONTAL_ALIGNMENT_LEFT,-1,11,get_theme_color("font_color","Label"))
