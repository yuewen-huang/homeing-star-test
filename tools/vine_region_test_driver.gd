extends SceneTree
## Input-driven traversal, progress and portal checks; never writes the user's save.
class TestProgress extends SaveProgressService:
	var disk_snapshot := ""
	var writes_fail := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		if writes_fail:
			return false
		disk_snapshot = _config.encode_to_text()
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true
var room: Chapter1VineRoom
var player: LanPlayer
var save: TestProgress
var failures := 0
var grabs: Array[StringName] = []
func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok:
		failures += 1
func _initialize() -> void:
	call_deferred("run")
func frames(n: int) -> void:
	for i in n:
		await physics_frame
func release_inputs() -> void:
	for action in [&"ui_left", &"ui_right", &"jump", &"parry", &"ui_down"]:
		Input.action_release(action)
func drive(direction: float) -> void:
	Input.action_release(&"ui_right")
	Input.action_release(&"ui_left")
	if not is_zero_approx(direction):
		Input.action_press(&"ui_right" if direction > 0 else &"ui_left")
func ground() -> bool:
	return player.air_state in [LanPlayer.AirState.GROUNDED, LanPlayer.AirState.LANDING, LanPlayer.AirState.ROLL_LANDING]
func setup(at: Vector2) -> void:
	release_inputs()
	if player.vine:
		player.release_vine()
	player._vine_regrab_block = null
	player.reset_after_map_fall(at)
	await frames(20)

func walk_to(x: float) -> void:
	for i in 550:
		if absf(player.position.x - x) < 10:
			break
		drive(signf(x - player.position.x))
		await physics_frame
	release_inputs()
	await frames(16)

func e() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event = InputEventKey.new()
	event.physical_keycode = KEY_E
	Input.parse_input_event(event)
	await frames(10)

func travel(marker: Node2D) -> void:
	release_inputs()
	player.set_physics_process(false)
	player.position = marker.global_position
	await frames(2)
	await e()
	var transition := root.get_node("SceneTransition") as SceneTransitionService
	for i in 240:
		await physics_frame
		if not transition.is_transitioning:
			break
	player = current_scene.get_node("Lan") as LanPlayer
	player.set_physics_process(false)

func run() -> void:
	pass # Implemented by test_vine_remake.gd.
