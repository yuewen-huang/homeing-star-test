extends SceneTree
## Native editor look-development. No game scene, save, hitbox or editor source changes.
const Catalog = preload("res://vfx/editor_catalog.gd")
var output := "E:/HomingStar/homeing-star-test/artifacts/deer-vfx-catalog-20261104"
const CASES := [
	["cleave", "blade", 7],
	["ribbon", "blade", 3],
	["ground", "quake", 0],
	["greatblade", "quake", 3],
	["fire", "magic", 0],
	["vortex", "magic", 4],
	["leaves", "swarm", 11],
	["swords", "swarm", 10],
]

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var recipes := []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--recipes="):
			recipes = JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--recipes=")))
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if recipes.is_empty():
		for item: Array in CASES:
			var original := Catalog.create(item[1],item[2])
			original["id"] = item[0]
			if item[0] == "fire":
				original.data.events.append({"t":.82,"do":"hit","push":0.0,"stop":0.0,"shake":0.0,"spark":65.0})
			recipes.append(original)
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	DirAccess.make_dir_recursive_absolute(output)
	var records := []
	for preset: Dictionary in recipes:
		ComboStyle.load_file("res://styles/default.json")
		ComboStyle.data.merge(preset.style,true)
		ComboStyle.data.merge({"quake_style":"real","quake_detail":"explosive","magic_quality":"explosive"},true)
		var renderer := String(preset.style.get("renderer",""))
		var stage: ComboStage = ComboStage.new() if renderer.is_empty() else load("res://vfx/%s_stage.gd" % renderer).new()
		root.add_child(stage)
		stage.set_process(false)
		stage.help.hide()
		stage.counter.hide()
		if stage.get("quality_label") != null: stage.quality_label.hide()
		stage.TIMELINE = ComboStage.parse_events(preset.data.events)
		stage.play()
		if preset.has("target"):
			stage.target.position = Vector2(float(preset.target[0]),float(preset.target[1]))
		var label := Label.new()
		label.text = "%s · %s" % [preset.data.name,preset.get("note","编辑器原生预设研究")]
		label.position = Vector2(30,28)
		label.add_theme_font_size_override("font_size",24)
		stage.overlay.add_child(label)
		var folder := output.path_join(preset.id)
		DirAccess.make_dir_recursive_absolute(folder)
		var frames := int(float(preset.get("seconds",2.5))*24)+1
		for frame in frames:
			if frame > 0:
				for substep in 5: stage.advance(1.0/120.0)
			stage.update_layers()
			stage.counter.hide()
			for key in ["caption","rhythm"]:
				if stage.get(key) is CanvasItem: stage.get(key).hide()
			await process_frame
			RenderingServer.force_draw(false)
			await process_frame
			RenderingServer.force_draw(false)
			var err := root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frame))
			assert(err == OK)
		preset["fps"] = 24
		records.append(preset)
		print("CAPTURED ",preset.id," ",preset.data.name)
		stage.free()
		await process_frame
	var file := FileAccess.open(output.path_join("recipes.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	file.close()
	print("CATALOG STUDY READY ",output)
	quit()
