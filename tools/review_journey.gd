extends SceneTree
## Screenshot-led review of the unchanged production journey. Isolated saves only.
## No routing, enemy-state decisions, teleportation, stat edits or victory hooks.
const OUT := "D:/HomingStar/homeing-star-test/artifacts/journey-review-20261109/"
var seq := 0
var ticks := 0
var sim_seconds := 0.0
var game_paused := false
var held: Array[int] = []
var frame_id := 0
var movie_log: FileAccess
func _initialize() -> void: run.call_deferred()
func key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)
func release() -> void:
	for code in held: key(code, false)
	held.clear()
func shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func ready_snapshot() -> void:
	await shot(OUT + "latest.png")
	DirAccess.copy_absolute(OUT + "latest.png", OUT + "decisions/%04d.png" % seq)
	var status := {"seq":seq,"ticks":ticks,"active_seconds":sim_seconds,"scene":current_scene.scene_file_path if is_instance_valid(current_scene) else "transition"}
	FileAccess.open(OUT + "status.json", FileAccess.WRITE).store_string(JSON.stringify(status))
	print("READY ",JSON.stringify(status))
func run() -> void:
	if not ProjectSettings.globalize_path("res://").replace("\\", "/").contains("/artifacts/journey-review-20261109/project"):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUT + "decisions")
	DirAccess.make_dir_recursive_absolute(OUT + "frames")
	movie_log = FileAccess.open(OUT + "movie_frames.jsonl",FileAccess.WRITE)
	root.size = Vector2i(1280,720)
	root.unfocusable = false
	root.title = "HomingStar Review"
	root.show()
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for i in range(90): await process_frame
	root.title = "HomingStar Review"
	game_paused = paused
	paused = true
	await ready_snapshot()
	while true:
		await process_frame
		if not FileAccess.file_exists(OUT + "command.json"): continue
		var c = JSON.parse_string(FileAccess.get_file_as_string(OUT + "command.json"))
		if not c is Dictionary or int(c.get("seq",0)) <= seq: continue
		seq = int(c.seq)
		if c.get("stop",false): break
		if c.get("live",false):
			paused = game_paused
			var live_until := Time.get_ticks_msec() + int(c.get("seconds",60)) * 1000
			while Time.get_ticks_msec() < live_until:
				await process_frame
				sim_seconds += root.get_process_delta_time()
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(OUT + "frames/review_%06d.jpg" % frame_id,0.87)
				movie_log.store_line(JSON.stringify({"frame":frame_id,"seq":seq,"seconds":sim_seconds,"wall_ms":Time.get_ticks_msec(),"mode":"computer-use"}))
				movie_log.flush()
				frame_id += 1
			game_paused = paused
			paused = true
			await ready_snapshot()
			continue
		var log_file := FileAccess.open(OUT + "inputs.jsonl",FileAccess.READ_WRITE) if FileAccess.file_exists(OUT + "inputs.jsonl") else FileAccess.open(OUT + "inputs.jsonl",FileAccess.WRITE)
		log_file.seek_end()
		log_file.store_line(JSON.stringify({"at":sim_seconds,"input":c}))
		log_file.close()
		paused = game_paused
		for code in c.get("hold",[]):
			key(int(code),true)
			held.append(int(code))
		for i in range(clampi(int(c.get("frames",60)),1,36000)):
			for event in c.get("events",[]):
				if i == int(event[0]):
					key(int(event[1]),bool(event[2]))
			for code in c.get("repeat",[]):
				var period := int(c.get("period",24))
				if i % period == 0: key(int(code),true)
				elif i % period == 2: key(int(code),false)
			await process_frame
			ticks += 1
			sim_seconds += root.get_process_delta_time()
			if i % int(c.get("capture_every",2)) == 0:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_jpg(OUT + "frames/review_%06d.jpg" % frame_id,0.87)
				movie_log.store_line(JSON.stringify({"frame":frame_id,"seq":seq,"seconds":sim_seconds,"wall_ms":Time.get_ticks_msec()}))
				movie_log.flush()
				frame_id += 1
		for code in c.get("repeat",[]): key(int(code),false)
		for event in c.get("events",[]): key(int(event[1]),false)
		release()
		await process_frame
		game_paused = paused
		paused = true
		await ready_snapshot()
	quit()
