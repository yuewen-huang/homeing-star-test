extends SceneTree
## Export preparation only: preserve generated originals, downsample runtime pixel textures.
func _initialize() -> void:
	var source := "D:/HomingStar/homeing-star-temp-assert/Art/salt/layers/20261017-v01/"
	var destination := "res://assets/sideview/environment/chapter_2_salt/"
	for spec in [["salt_ground_source_v2.png","salt_ground_tile_v2.png",Vector2i(300,300)],
		["salt_clear_sky_source.png","salt_clear_sky_v1.png",Vector2i(1200,400)]]:
		var image := Image.load_from_file(source+spec[0])
		if image == null: quit(1); return
		var size: Vector2i = spec[2]
		image.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
		var error := image.save_png(destination+spec[1])
		if error != OK: quit(error); return
		print("EXPORTED ",spec[1]," ",size)
	quit()
