extends SceneTree
## Lotus never auto-delivers; paused turtle reward dialogue/card must not retain directions.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + message)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func step(scene: MirrorLake, leaf: int) -> void:
	scene.player.position = scene.lotus.position + Vector2(100, 0)
	scene.lotus.tick(0.01)
	scene.player.position = scene.lotus.position + Vector2(scene.lotus.LEAF_X[leaf], scene.lotus.DECK_Y)
	scene.lotus.tick(0.01)
func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var save := MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var scene := load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate() as MirrorLake
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.ink_trial.set_physics_process(false)
	var player := scene.player as LanPlayer
	scene.entry.activate_seal()
	scene.shadow_bridge.fix_bridge(0)
	scene.shadow_bridge.fix_bridge(1)
	save.claim_unique_reward(MirrorLakeInkCarp.REWARD_ID, MirrorLakeInkCarp.REWARD_ITEM)
	scene.ink_trial._try_complete()
	scene.ink_trial._refresh()
	scene.player.position = scene.lotus.position
	scene.request_switch()
	scene.advance_switch(3)
	await process_frame
	for leaf in scene.lotus.ORDER: step(scene, leaf)
	check(scene.lotus.solved, "real lotus stepping sequence completes")
	for i in 20: scene.lotus.tick(0.1)
	check(scene.lotus.dropped and scene.lotus.drop_landed and not scene.lotus.claimed, "lotus red seal settles before pickup")
	scene.player.position = scene.lotus.position + Vector2(scene.lotus.FLOWER_AT.x, 0)
	key(KEY_D, true)
	check(Input.is_physical_key_pressed(KEY_A), "held real D is mapped to A in yin")
	scene.lotus.tick(0.01)
	scene.lake_progress.tick(0.01)
	check(scene.lotus.claimed and scene.lake_progress.reveal == null and not paused and not save.has_claimed_reward(MirrorLakeProgress.REWARD_ID), "final lotus pickup stays playable and only enables turtle reward interaction")
	key(KEY_D, false)
	scene.player.position = scene.ink_trial.position + scene.ink_trial.turtle.position + Vector2(-50, 0)
	key(KEY_D, true)
	key(KEY_E, true)
	key(KEY_E, false)
	check(paused and scene.lake_progress.reward_dialogue != null, "E near turtle starts the reward dialogue")
	key(KEY_D, false)
	check(not Input.is_physical_key_pressed(KEY_A) and not Input.is_action_pressed("ui_left"), "releasing D during paused reward clears its synthetic left key")
	check(not scene.control_inverter.real_held.get(KEY_D, false), "raw held-direction ledger receives release while game is paused")
	for i in 3:
		key(KEY_E, true)
		key(KEY_E, false)
		await process_frame
	check(scene.lake_progress.reveal != null and paused, "finishing actual dialogue inputs opens the acquisition card")
	key(KEY_ENTER, true)
	await create_timer(0.65, true).timeout
	key(KEY_ENTER, false)
	check(not paused and not player.input_frozen, "real continue input closes reward and restores gameplay")
	var start_x := player.position.x
	for i in 8:
		player._physics_process(1.0 / 60.0)
		await process_frame
	check(is_zero_approx(player.input_direction) and is_zero_approx(player.velocity.x), "player has no movement input or horizontal velocity after reward")
	check(absf(player.position.x - start_x) < 0.1, "player does not keep running after releasing the direction")
	check(not scene.control_inverter.real_held.get(KEY_D, false), "reward dismissal does not resurrect the released direction")
	save.equip_special_item(ItemCatalog.NINGXIN_MIRROR)
	check(not Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_D), "equipping mirror after reward cannot resurrect a stale direction")
	scene.queue_free()
	await process_frame
	root.remove_child(save)
	save.free()
	root.add_child(original)
	print("Lotus reward input: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
