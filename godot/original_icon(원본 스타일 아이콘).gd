extends Control
## Keep the original Unicode icon. The browser supplies its own emoji artwork.
const SYMBOLS = {"play":"⚔️","book":"📖","trophy":"🏆","chat":"💬","settings":"⚙️","user":"🙂","people":"👥","join":"🤝","computer":"💻","target":"🎯","easy":"🌱","normal":"⚔️","hard":"🔥","accept":"✅","decline":"✕"}
var key := "play"
var texture: Texture2D
var emoji_font: SystemFont
static var cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var symbol: String = SYMBOLS.get(key,"•")
	if OS.has_feature("web"):
		if not cache.has(key):
			var encoded: Variant = JavaScriptBridge.eval("(()=>{const c=document.createElement('canvas');c.width=c.height=128;const x=c.getContext('2d');x.font='96px system-ui';x.textAlign='center';x.textBaseline='middle';x.fillText("+JSON.stringify(symbol)+",64,68);return c.toDataURL('image/png').split(',')[1]})()")
			if encoded is String:
				var image := Image.new()
				if image.load_png_from_buffer(Marshalls.base64_to_raw(encoded))==OK: cache[key] = ImageTexture.create_from_image(image)
		texture = cache.get(key)
	else:
		emoji_font = SystemFont.new()
		emoji_font.font_names = PackedStringArray(["Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji","Segoe UI Symbol"])
	queue_redraw()

func _draw() -> void:
	if texture: draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false)
	elif emoji_font:
		var font_size := int(minf(size.x,size.y)*.7)
		var symbol: String = SYMBOLS.get(key,"•")
		var advance := emoji_font.get_string_size(symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
		draw_string(emoji_font,Vector2((size.x-advance.x)/2,(size.y-advance.y)/2+emoji_font.get_ascent(font_size)),symbol,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
