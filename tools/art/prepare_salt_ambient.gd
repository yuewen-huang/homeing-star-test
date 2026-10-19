extends SceneTree
const DEST := "res://assets/levels/chapter_2_salt/environment/ambient/"
const STATIC := ["starfish","plank","stone_1","stone_2","stone_3","crystal"]
const ANIMALS := ["fish","jijuxie","pangxie","woniu"]
func _initialize() -> void:
	var atlas := Image.create(1000,300,false,Image.FORMAT_RGBA8)
	var cell := 0
	var manifest := {"static":{},"animals":{}}
	for kind in STATIC:
		var image := Image.load_from_file(DEST+kind+".png")
		if image==null or image.get_size()!=Vector2i(100,100): quit(1); return
		var origin := Vector2i(cell%10,cell/10)*100
		atlas.blit_rect(image,Rect2i(0,0,100,100),origin)
		var bounds := image.get_used_rect()
		manifest.static[kind] = {"cell":cell,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]}
		cell += 1
	for kind in ANIMALS:
		var image := Image.load_from_file(DEST+kind+".png")
		var data = JSON.parse_string(FileAccess.get_file_as_string(DEST+kind+".json"))
		var frames := []; var floor_y := 0
		for spec in data.frames:
			var rect := Rect2i(spec.frame.x,spec.frame.y,spec.frame.w,spec.frame.h)
			atlas.blit_rect(image,rect,Vector2i(cell%10,cell/10)*100)
			floor_y = maxi(floor_y,image.get_region(rect).get_used_rect().end.y)
			frames.append({"cell":cell,"seconds":float(spec.duration)/1000.0}); cell += 1
		manifest.animals[kind] = {"frames":frames,"foot_y":floor_y}
	var result := atlas.save_png(DEST+"ambient_atlas.png")
	var file := FileAccess.open(DEST+"atlas_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	print("AMBIENT ATLAS ",cell," cells")
	quit(result)
