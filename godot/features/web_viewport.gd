extends Node
## Layout uses browser CSS pixels; the canvas keeps its full HiDPI resolution.
## Otherwise a 360 CSS-pixel phone with DPR 3 selects the 1080px desktop layout.
const CANVAS_SIZE_SCRIPT := """
(function () {
    var canvas = document.getElementById('canvas');
    if (!canvas) return '';
    var rect = canvas.getBoundingClientRect();
    return JSON.stringify([Math.round(rect.width), Math.round(rect.height)]);
})()
"""

var elapsed := 0.0

func _ready() -> void:
	set_process(OS.has_feature("web"))
	if not OS.has_feature("web"): return
	get_window().size_changed.connect(sync_browser_size.call_deferred)
	sync_browser_size()

func _process(delta: float) -> void:
	# Also covers browser zoom/DPR changes that leave the backing canvas unchanged.
	elapsed += delta
	if elapsed < .25: return
	elapsed = 0.0
	sync_browser_size()

func sync_browser_size() -> void:
	if not OS.has_feature("web"): return
	var value = JSON.parse_string(str(JavaScriptBridge.eval(CANVAS_SIZE_SCRIPT)))
	if value is Array and value.size() == 2:
		apply_css_size(Vector2i(int(value[0]), int(value[1])))

func apply_css_size(css_size: Vector2i) -> void:
	# A hidden canvas can temporarily report zero during startup or tab changes.
	if css_size.x <= 0 or css_size.y <= 0: return
	var window := get_window()
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and window.content_scale_size == css_size: return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	window.content_scale_size = css_size
