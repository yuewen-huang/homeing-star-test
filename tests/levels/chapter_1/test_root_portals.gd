extends SceneTree
class TestProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		return true
var failures := 0
func _initialize() -> void:
	call_deferred("run_tests")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func use_portal(room: Node) -> void:
	room.player.set_physics_process(false)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	room._unhandled_input(key)
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in range(180):
		await physics_frame
		if not transition.is_transitioning:
			return
	check(false, "Root portal transition timed out")
func run_tests() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	var save := TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var room = load("res://scenes/levels/chapter_1/chapter_1_root_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.position = room.get_node("Portals/MistGate").global_position
	await use_portal(room)
	check(current_scene.scene_file_path.ends_with("chapter_1_mist_room.tscn"), "Root -> Mist failed")
	room = current_scene
	for enemy: MistAmbusher in room.mist_enemies:
		enemy.set_physics_process(false)
	room.player.set_physics_process(false)
	room.player.position = room.get_node("PortalToRoot").position
	await use_portal(room)
	check(current_scene is Chapter1RootRoom, "Mist -> Root failed")
	room = current_scene
	check(room.player.position.distance_to(room.get_node("Portals/MistGate").global_position) < 4, "Mist arrival ignores Root marker")
	room.player.position = room.get_node("Portals/VineGate").global_position
	await use_portal(room)
	check(current_scene.scene_file_path.ends_with("chapter_1_vine_room.tscn"), "Root -> Vine failed")
	room = current_scene
	room.player.position = room.get_node("Portals/RootGate").global_position
	await use_portal(room)
	check(current_scene is Chapter1RootRoom, "Vine -> Root failed")
	room = current_scene
	check(room.player.position.distance_to(room.get_node("Portals/VineGate").global_position) < 4, "Vine arrival ignores Root marker")
	print("Root portal checks: %d failures" % failures)
	quit(1 if failures else 0)
