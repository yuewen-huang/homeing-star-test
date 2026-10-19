extends SceneTree
## Preserve generated original; export one uniform pixel scale and matching sea continuation.
func _initialize() -> void:
	var source := Image.load_from_file("D:/HomingStar/homeing-star-temp-assert/Art/salt/layers/20261017-v01/salt_coast_source_v1.png")
	if source == null: quit(1); return
	var height := roundi(600.0*source.get_height()/source.get_width())
	source.resize(600,height,Image.INTERPOLATE_LANCZOS)
	var destination := "res://assets/levels/chapter_2_salt/environment/"
	var result := source.save_png(destination+"salt_coast.png")
	if result != OK: quit(result); return
	var fill := source.get_region(Rect2i(0,height-8,600,8))
	result = fill.save_png(destination+"salt_sea_fill.png")
	print("COAST EXPORT ",source.get_size()," SEA ",fill.get_size())
	quit(result)
