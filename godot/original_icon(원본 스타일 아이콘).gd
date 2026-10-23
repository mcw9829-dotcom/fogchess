extends Control
## Shared SVGs follow the inherited application theme, including new modal windows.
const ALIASES = {"play":"rank","people":"lobby","target":"practice"}
var key := "rank"
var texture: Texture2D
static var cache: Dictionary = {}
static func asset_path(value: String, light: bool=false) -> String:
	return "res://ui/icons/menu/%s%s.svg" % ["light/" if light else "",ALIASES.get(value,value)]
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_refresh_texture()
func _notification(what: int) -> void:
	if what==NOTIFICATION_THEME_CHANGED and is_node_ready(): _refresh_texture()
func _refresh_texture() -> void:
	var light := has_theme_constant("light_mode","FogMenuIcon") and get_theme_constant("light_mode","FogMenuIcon")==1
	var path := asset_path(key,light)
	if ResourceLoader.exists(path):
		if not cache.has(path): cache[path] = load(path)
		texture = cache[path]
	else: push_warning("Unknown UI icon: "+key)
	queue_redraw()
func _draw() -> void:
	if texture:
		var dimension := minf(size.x,size.y)
		draw_texture_rect(texture,Rect2((size-Vector2.ONE*dimension)/2,Vector2.ONE*dimension),false)
