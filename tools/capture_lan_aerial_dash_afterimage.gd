extends SceneTree
## Native production-background preview; all progress remains in memory.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func shadows(world: Node) -> Array[Node]:
	return world.get_children().filter(func(child: Node) -> bool: return child is LanUltimateAfterimage)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "Capture " + label)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	assert(not output.is_empty())
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	var room := load("res://scenes/levels/chapter_1/chapter_1_root_heart_room.tscn").instantiate() as Chapter1BossRoom
	root.add_child(room)
	current_scene = room
	room.regional_core.battle.cancel()
	room.regional_core.set_physics_process(false)
	var player := room.player
	player.set_physics_process(false)
	await process_frame
	for direction in [1.0, -1.0]:
		var label := "right" if direction > 0 else "left"
		player.reset_after_map_fall(Vector2(640, 320))
		player.air_state = LanPlayer.AirState.FALLING
		player.start_aerial_dash(direction)
		var peak := 0
		for frame in 40:
			player._physics_process(1.0 / 60)
			var current := shadows(room)
			peak = maxi(peak, current.size())
			if frame == 0:
				check(current.size() == 1, label + ": dash emits a body snapshot")
				var shadow := current[0] as LanUltimateAfterimage
				check(shadow.texture == player.animated_sprite.sprite_frames.get_frame_texture(player.animated_sprite.animation, player.animated_sprite.frame)
					and shadow.offset == player.animated_sprite.offset and shadow.flip_h == player.animated_sprite.flip_h,
					label + ": pose, pivot and facing match the live body")
				check(shadow.z_index < player.z_index, label + ": shadow renders behind the player")
				player.update_aerial_dash_phase(0)
				check(shadows(room).size() == 1, label + ": paused action emits no extra shadows")
			await process_frame
			if frame in [0, 12, 20, 39]: await capture(label + "_" + str(frame))
		check(peak <= 4, label + ": at most four short-lived body sprites")
		check(shadows(room).is_empty(), label + ": shadows fade and free after dash ends")
	room.queue_free()
	await process_frame
	await process_frame
	check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "Save bytes unchanged")
	print("AERIAL_DASH_AFTERIMAGE_PREVIEW: failures=", failures)
	quit(1 if failures else 0)
