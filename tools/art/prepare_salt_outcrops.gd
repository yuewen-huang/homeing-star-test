extends SceneTree
## One shared export scale for the three generated terrain variants.
func _initialize() -> void:
	var source := Image.load_from_file("D:/HomingStar/homeing-star-temp-assert/Art/salt/layers/20261017-v01/salt_outcrops_source_v1.png")
	if source == null: quit(1); return
	var width := source.get_width()/3
	for i in 3:
		var cell := source.get_region(Rect2i(i*width,0,width,source.get_height()))
		cell.resize(300,roundi(300.0*cell.get_height()/cell.get_width()),Image.INTERPOLATE_LANCZOS)
		var result := cell.save_png("res://assets/sideview/environment/chapter_2_salt/salt_outcrop_%d.png" % (i+1))
		if result != OK: quit(result); return
		print("OUTCROP ",i+1," ",cell.get_size())
	quit()
