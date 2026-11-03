extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var checks := 0
	for phase in range(1,5):
		for weight in ["light","heavy"]:
			var path := "res://combos/deer_stomp_%d_%s/combo.json"%[phase,weight]
			root.set_meta("quake_editor_open",path)
			var editor: Control=load("res://vfx/quake_editor.gd").new()
			root.add_child(editor)
			await process_frame
			if editor.combo_path!=path or editor.event().unit!="sword" or editor.event().form!="crescent" or editor.event().trail!="flame" or editor.event().mode!="radial" or editor.style.quake_detail!="balanced":
				push_error("Editor preset mismatch "+path); quit(1); return
			checks+=1
			editor.free()
	print("PASS: ",checks," deer quake presets open in the real skill editor")
	quit()
