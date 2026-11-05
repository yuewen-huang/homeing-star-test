extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var editor=load("res://node_editor.tscn").instantiate()
	root.add_child(editor)
	for key in ["leaves","tornado","meteors","phantom","core"]:
		var path: String="res://combos/deer_wind_%s/combo.json"%key
		var index: int=editor._paths.find(path)
		assert(index>=0,"New wind recipe is discoverable in the real skill editor")
		editor._open(index)
		var before := JSON.stringify(editor.data)
		for i in editor.data.events.size(): editor.select_event(i)
		assert(JSON.stringify(editor.data)==before,"Editor selection preserves gameplay metadata and spell coordinates")
		for f in 20: await process_frame
		print("EDITOR WIND PROFILE PASS "+key)
	editor.free()
	await process_frame
	quit()
