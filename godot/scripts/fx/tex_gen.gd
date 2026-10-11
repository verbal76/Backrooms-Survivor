class_name TexGen
extends RefCounted
## Procedural textures for lights and particles (generated once, cached). Cheap and resolution independent.

static var _cache := {}


## White radial blob: value = (1 - d)^power. Used for soft glows, smoke puffs and ambient lights.
static func radial(size := 128, power := 1.6) -> ImageTexture:
	var key := "radial_%d_%s" % [size, str(power)]
	if _cache.has(key):
		return _cache[key]
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var half := size * 0.5
	var i := 0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half
			var v := pow(maxf(0.0, 1.0 - d), power)
			var b := int(clampf(v, 0.0, 1.0) * 255.0)
			data[i] = 255; data[i + 1] = 255; data[i + 2] = 255; data[i + 3] = b
			i += 4
	var t := ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data))
	_cache[key] = t
	return t


## Headlamp texture matching getLightAtWorld() in main.lua. The image covers a square of
## +-radius_tiles around the lamp, beam pointing along +x (rotate the light node to aim).
##   value = (1 - dist/R)^1.3 * coneFactor, with a 0.7 hot spot inside 3 tiles.
## cone_factor is 1 inside +-cone radians then falls (x0.35) outside, like the Lua; the step is softened.
static func headlamp(radius_tiles := 14.0, cone := 0.85, size := 256) -> ImageTexture:
	var key := "lamp_%s_%s_%d" % [str(radius_tiles), str(cone), size]
	if _cache.has(key):
		return _cache[key]
	var data := PackedByteArray()
	data.resize(size * size * 4)
	var half := size * 0.5
	var i := 0
	for y in size:
		for x in size:
			var dx := (x + 0.5 - half) / half * radius_tiles
			var dy := (y + 0.5 - half) / half * radius_tiles
			var dist := sqrt(dx * dx + dy * dy)
			var v := 0.0
			if dist < radius_tiles:
				var ad := absf(atan2(dy, dx))
				# smooth version of: ad <= cone -> 1.0 else max(0, 1-(ad-cone)) * 0.35
				var outside := maxf(0.0, 1.0 - maxf(0.0, ad - cone)) * 0.35
				var cf := lerpf(1.0, outside, smoothstep(cone - 0.10, cone + 0.10, ad))
				var df := 1.0 - dist / radius_tiles
				v = pow(df, 1.3) * cf
				if dist < 3.0:
					v = maxf(v, 0.7 * (1.0 - dist / 3.0))
				# fade out the very edge to avoid a visible square/circle rim
				v *= smoothstep(0.0, 0.06, df)
			var b := int(clampf(v, 0.0, 1.0) * 255.0)
			data[i] = 255; data[i + 1] = 255; data[i + 2] = 255; data[i + 3] = b
			i += 4
	var t := ImageTexture.create_from_image(Image.create_from_data(size, size, false, Image.FORMAT_RGBA8, data))
	_cache[key] = t
	return t


## Light textures use luminance, so PointLight2D reads the RGB channels: build an RGB copy of an alpha ramp.
## (PointLight2D multiplies texture RGB * color * energy; alpha is ignored for the light value.)
static func as_light(tex: ImageTexture) -> ImageTexture:
	var key := "light_%d" % tex.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		data[i] = a; data[i + 1] = a; data[i + 2] = a; data[i + 3] = 255
	var t := ImageTexture.create_from_image(Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data))
	_cache[key] = t
	return t


static func light_radial(size := 128, power := 1.6) -> ImageTexture:
	return as_light(radial(size, power))


static func light_headlamp(radius_tiles := 14.0, cone := 0.85, size := 256) -> ImageTexture:
	return as_light(headlamp(radius_tiles, cone, size))
