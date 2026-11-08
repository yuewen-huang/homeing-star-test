extends SceneTree
func _initialize()->void: call_deferred("run")
func run()->void:
	var rows:Array=[]
	for combo in ["sandstorm_pressure","sandstorm_counter"]:
		var arrangement:Node2D=load("res://scripts/bosses/sandstorm_fighter/authored/arranged_track_player.gd").new()
		arrangement.combo_file=combo;root.add_child(arrangement);arrangement.set_process(false)
		for i in arrangement.playlist.size():
			arrangement.slot=i;arrangement._open();arrangement.current.set_process(false)
			var clip:Node2D=arrangement.current
			for e:Dictionary in clip.document.events:
				if not e.has("_fire_tail"): continue
				rows.append({"combo":combo,"action":clip.document.action,"wind":e.wind,"contact":e.contact,"end":e.end,"wind_frame":clip._frame_at(e.wind),"contact_frame":clip._frame_at(e.contact),"end_frame":clip._frame_at(e.end-.00001),"start_frame":clip._frame_at(float(arrangement.playlist[i].start_time)),"durations":clip.library.actions[clip.document.action].durations})
		arrangement.free()
	DirAccess.make_dir_recursive_absolute("D:/HomingStar/homeing-star-test/artifacts/sandstorm-fire-sockets")
	FileAccess.open("D:/HomingStar/homeing-star-test/artifacts/sandstorm-fire-sockets/timing.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	print("SOCKET TIMING: ",rows.size()," actions")
	quit()
