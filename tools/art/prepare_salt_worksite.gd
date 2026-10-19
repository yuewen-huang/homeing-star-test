extends SceneTree
const SOURCE := "D:/HomingStar/homeing-star-temp-assert/Art/salt/worksite/20261017-v01/"
const DEST := "res://assets/levels/chapter_2_salt/environment/worksite/"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DEST)
	var names := ["loading_ground","raked_bed","shallow_brine","wooden_trough","salt_rake"]
	var widths := [240,320,420,96,72]
	for i in names.size():
		var source := Image.load_from_file(SOURCE+names[i]+"_source.png")
		if source==null: quit(1); return
		var used := source.get_used_rect()
		var image := source.get_region(used)
		image.resize(widths[i],maxi(1,roundi(image.get_height()*float(widths[i])/image.get_width())),Image.INTERPOLATE_NEAREST)
		var error := image.save_png(DEST+names[i]+".png")
		if error!=OK: quit(error); return
		print("WORKSITE ASSET ",names[i]," ",image.get_size())
	quit()
