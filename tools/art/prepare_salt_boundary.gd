extends SceneTree

func _initialize() -> void:
	var source := Image.load_from_file("D:/HomingStar/homeing-star-temp-assert/Art/salt/layers/20261017-v01/salt_boundary_source_v1.png")
	if source == null: quit(1); return
	# Ignore isolated transparent-edge specks; retain the continuous ridge and full tile width.
	var first := source.get_height()
	var last := 0
	for y in source.get_height():
		var solid := 0
		for x in source.get_width():
			if source.get_pixel(x,y).a > 0.5: solid += 1
		if solid > source.get_width()*0.08:
			first = mini(first,y)
			last = maxi(last,y)
	var cropped := source.get_region(Rect2i(0,first,source.get_width(),last-first+1))
	cropped.resize(384,roundi(384.0*cropped.get_height()/cropped.get_width()),Image.INTERPOLATE_LANCZOS)
	var error := cropped.save_png("res://assets/sideview/environment/chapter_2_salt/salt_boundary_v1.png")
	print("BOUNDARY EXPORT ",cropped.get_size()," ",error)
	quit(error)
