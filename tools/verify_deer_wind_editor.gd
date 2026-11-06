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
		if key=="core":
			var beat: Dictionary=editor.data.events.filter(func(e): return e.get("shape")=="core_pulse")[0]
			for i in 9:
				var t: float=beat.t+beat.charge+beat.travel+i*beat.interval
				editor._seek(t+.005)
				var pulses: Array=editor.stage.fx.get_children().filter(func(n): return "released" in n and "compression" in n)
				assert(pulses.size()==1 and pulses[0].released==i+1,"Editor scrubbing resolves every real wind-core beat")
			print("EDITOR NINE WIND BEATS PASS")
			var blasts: Array=editor.data.events.filter(func(e): return e.get("shape")=="core_burst")
			assert(blasts.size()==9,"All nine settlement beats are authored in the editor")
			for blast: Dictionary in blasts:
				for offset in [-.04,.005]:
					editor._seek(float(blast.t)+float(blast.charge)+offset)
					var matches: Array=editor.stage.fx.get_children().filter(func(n): return "detonated" in n and is_equal_approx(n.radius,blast.radius))
					assert(matches.size()==1 and matches[0].detonated==(offset>0),"Editor charge and burst boundary matches the game's damage onset")
			print("EDITOR NINE SETTLEMENT CHARGES AND BLASTS PASS")
		print("EDITOR WIND PROFILE PASS "+key)
	editor.free()
	await process_frame
	quit()
