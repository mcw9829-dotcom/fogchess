extends RefCounted
## Cache an exterior-only stroke from sprite alpha, preserving translucent bush pieces.
static var strokes: Dictionary = {}
const PADDING := 3

static func draw(canvas: CanvasItem, texture: Texture2D, box: Rect2, opacity: float=1.0) -> void:
	var key := texture.get_rid()
	if not strokes.has(key):
		var source := texture.get_image()
		if source == null: return
		if source.is_compressed(): source.decompress()
		source.convert(Image.FORMAT_RGBA8)
		strokes[key] = _make_stroke(source)
	var padding := box.size/texture.get_size()*PADDING
	canvas.draw_texture_rect(strokes[key],Rect2(box.position-padding,box.size+padding*2),false,Color(1,1,1,opacity))

static func _make_stroke(source: Image) -> ImageTexture:
	var width := source.get_width()
	var height := source.get_height()
	var pixels := source.get_data()
	var image := Image.create(width+PADDING*2,height+PADDING*2,false,Image.FORMAT_RGBA8)
	var offsets: Array[Vector3i] = []
	for dy in range(-PADDING,PADDING+1):
		for dx in range(-PADDING,PADDING+1):
			var distance := dx*dx+dy*dy
			if distance<=PADDING*PADDING: offsets.append(Vector3i(dx,dy,1 if distance<=4 else 0))
	for y in range(-PADDING,height+PADDING):
		for x in range(-PADDING,width+PADDING):
			var original := pixels[(y*width+x)*4+3]/255.0 if x>=0 and y>=0 and x<width and y<height else 0.0
			if original>=1.0: continue
			var inner := original
			var outer := original
			for offset in offsets:
				var sx := x+offset.x
				var sy := y+offset.y
				if sx<0 or sy<0 or sx>=width or sy>=height: continue
				var alpha := pixels[(sy*width+sx)*4+3]/255.0
				outer = maxf(outer,alpha)
				if offset.z==1: inner = maxf(inner,alpha)
			if outer<=original: continue
			var color := Color("#574022").lerp(Color("#fff0b5"),(inner-original)/(outer-original))
			color.a = outer-original
			image.set_pixel(x+PADDING,y+PADDING,color)
	return ImageTexture.create_from_image(image)
