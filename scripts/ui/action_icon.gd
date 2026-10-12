class_name ActionIcon
extends RefCounted

# Original 24px silhouettes. Shared by console, map marker, and observation cards.
# Pixel blocks stay hard edged; no state here has access to simulation pressure.
static var cache: Dictionary = {}
static func texture(kind: String, lit: bool = false) -> Texture2D:
	var key := kind+str(lit)
	if cache.has(key): return cache[key]
	var img := Image.create(24,24,false,Image.FORMAT_RGBA8)
	var ivory := Color("f1e7ca") if lit else Color("c9c3ac")
	var brass := Color("b7a375") if lit else Color("827557")
	var teal := Color("9bc7bb") if lit else Color("658c82")
	var dark := Color("101919")
	for y in 24:
		for x in 24:
			var c := Color.TRANSPARENT
			if kind == "MONITOR":
				var span: int = [0,0,0,0,0,0,5,7,9,10,11,11,11,10,9,7,5,0,0,0,0,0,0,0][y]
				if span > 0 and absi(x-12) <= span:
					c = ivory if absi(x-12) >= span-2 or y in [6,16] else dark
					if x >= 8 and x <= 16 and y >= 8 and y <= 14: c = teal
					if x >= 11 and x <= 13 and y >= 8 and y <= 14: c = dark
					if x == 10 and y in [9,10]: c = ivory
				if y in [4,18] and x in [10,11,12,13,14]: c = brass
			elif kind == "VERIFY":
				var dx := x-9
				var dy := y-9
				var d := dx*dx+dy*dy
				if d <= 70: c = brass
				if d <= 42: c = ivory
				if d <= 25: c = teal
				if x in [6,7] and y in [6,7,8,9]: c = ivory
				if x >= 14 and y >= 14 and absi(x-y) <= 2 and x+y <= 42: c = brass
				if x >= 16 and y >= 16 and x == y and x+y <= 42: c = ivory
			elif kind == "SHIELD":
				if y >= 3 and y <= 20:
					var half := 8 if y < 13 else 8-(y-12)
					if absi(x-12) <= half:
						c = ivory if absi(x-12) >= half-2 or y <= 5 else teal
						if x in [11,12] and y > 5 and y < 18: c = brass
			img.set_pixel(x,y,c)
	cache[key] = ImageTexture.create_from_image(img)
	return cache[key]

static func view(kind: String, extent: int = 24) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture(kind,true)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2.ONE*extent
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
