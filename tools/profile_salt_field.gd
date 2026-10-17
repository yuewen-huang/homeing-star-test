extends SceneTree
## Local scene-entry and steady-frame diagnostic; uses an isolated in-memory save.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var environment_cache: PackedScene
	if "--split-load" in OS.get_cmdline_user_args():
		var environment_start := Time.get_ticks_usec()
		environment_cache = load("res://scenes/sideview/chapter_2_salt_environment.tscn")
		print("ENVIRONMENT RESOURCE LOAD MS ",(Time.get_ticks_usec()-environment_start)/1000.0)
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save); real_save.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var start := Time.get_ticks_usec()
	var packed: PackedScene = load("res://scenes/sideview/chapter_2_salt_field.tscn")
	var loaded := Time.get_ticks_usec()
	var field: Node2D = packed.instantiate()
	var instantiated := Time.get_ticks_usec()
	root.add_child(field); current_scene = field
	var ready := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	var presented := Time.get_ticks_usec()
	var report := {
		"scene_load_ms":(loaded-start)/1000.0,
		"instantiate_ms":(instantiated-loaded)/1000.0,
		"ready_ms":(ready-instantiated)/1000.0,
		"first_present_ms":(presented-start)/1000.0,
		"map_nodes":field.find_children("*","",true,false).size()+1,
		"wall_meshes":field.get_node("Environment/Boundary").find_children("*","MeshInstance2D",true,false).size(),
		"rock_sprites":field.get_node("Environment/Boundary").outcrops.size(),
		"static_memory_delta_mb":(Performance.get_monitor(Performance.MEMORY_STATIC)-memory_before)/1048576.0,
		"gpu_texture_memory_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0,
	}
	var cases := {}
	for location in ["entrance","side","overview"]:
		field.feet = Vector2(3560,1075) if location=="side" else field.SPAWN
		field.overview = location=="overview"
		field._sync_view(0)
		for i in 30: await process_frame
		var times: Array[float] = []
		var draws: Array[float] = []
		var cpu: Array[float] = []
		var last := Time.get_ticks_usec()
		for i in 120:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now-last)/1000.0); last = now
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		times.sort(); draws.sort(); cpu.sort()
		cases[location] = {"frame_median_ms":times[60],"frame_p95_ms":times[114],
			"draw_calls_median":draws[60],"engine_process_median_ms":cpu[60]}
	report["views"] = cases
	print("SALT PROFILE ",JSON.stringify(report))
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("salt_field_profile.json"),FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report,"\t"))
	field.free(); current_scene = null
	await process_frame
	quit()
