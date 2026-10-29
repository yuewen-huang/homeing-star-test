extends SceneTree
class MemorySave extends SaveProgressService:
	var reject := false
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not reject
	func show_toast(_text: String) -> void: pass
var failures := 0
var checks := 0
var scene: MirrorLake
var save: MemorySave
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + message)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func make_scene() -> void:
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.ink_trial.set_physics_process(false)
func talk() -> void:
	scene.player.position = scene.ink_trial.position + scene.ink_trial.turtle.position + Vector2(-50, 0)
	key(KEY_E, true)
	key(KEY_E, false)
func finish_talk() -> void:
	while scene.lake_progress.reward_dialogue != null:
		scene.lake_progress.reward_dialogue.advance()
func run() -> void:
	Input.use_accumulated_input = false
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	make_scene()
	await process_frame
	var progress := scene.lake_progress
	check(progress.seal_count == 0 and scene.puzzle_stele.state == MinigameStele.SteleState.LOCKED, "fresh puzzle stele locked at zero of five")
	save.reject = true
	scene.entry.activate_seal()
	check(not scene.entry.seal_activated and not save.has_completed(MirrorLakeEntry.SEAL_FACT), "failed entry save neither counts seal nor opens gate")
	save.reject = false
	scene.entry.activate_seal()
	progress.tick(0.01)
	check(scene.entry.gate_open and progress.seal_count == 1, "entry red seal persists one puzzle step")
	scene.entry.activate_seal()
	progress.tick(0.01)
	check(progress.seal_count == 1, "repeated entry seal cannot double count")
	check(scene.shadow_bridge.fix_bridge(0), "first bridge red seal saves")
	progress.tick(0.01)
	check(progress.seal_count == 2, "first bridge counts separately")
	check(scene.shadow_bridge.fix_bridge(1), "second bridge red seal saves")
	progress.tick(0.01)
	check(progress.seal_count == 3, "second bridge counts separately")
	save.claim_unique_reward(MirrorLakeShadowBridge.REWARD_ID, MirrorLakeShadowBridge.REWARD_ITEM)
	save.try_complete_fact(MirrorLakeLotus.SOLVED_FACT)
	progress.tick(0.01)
	check(progress.seal_count == 3, "bridge rubbing and uncollected lotus do not add puzzle progress")
	check(save.claim_unique_reward(MirrorLakeInkCarp.REWARD_ID, MirrorLakeInkCarp.REWARD_ITEM), "carp seal collected")
	progress.tick(0.01)
	check(progress.seal_count == 4 and scene.puzzle_stele.state == MinigameStele.SteleState.LOCKED, "four seals keep puzzle stele locked")
	save.reject = true
	check(not save.claim_unique_reward(MirrorLakeLotus.REWARD_ID, MirrorLakeLotus.REWARD_ITEM), "failed lotus pickup rolls back")
	progress.tick(0.01)
	check(progress.seal_count == 4, "failed pickup is not counted")
	save.reject = false
	save.claim_unique_reward(MirrorLakeLotus.REWARD_ID, MirrorLakeLotus.REWARD_ITEM)
	save.reject = true
	progress.tick(0.01)
	check(progress.seal_count == 5 and scene.puzzle_stele.state == MinigameStele.SteleState.LOCKED, "failed stele save does not falsely complete it")
	save.reject = false
	progress.tick(1.1)
	check(scene.puzzle_stele.state == MinigameStele.SteleState.COMPLETED, "all five seals unlock and complete puzzle stele")
	check(save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 0, "puzzle completion alone does not grant mirror")
	scene.ink_trial._try_complete()
	scene.ink_trial._refresh()
	check(save.get_stele_state(progress.COMBAT_ID) == MinigameStele.SteleState.COMPLETED, "ink trial supplies combat stele completion")
	progress.tick(1.1)
	check(progress.reward_hint != null and progress.reward_dialogue == null and progress.reveal == null and not paused and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 0, "both completed steles only light turtle E hint; no automatic grant or popup")
	key(KEY_E, true)
	key(KEY_E, false)
	check(progress.reward_dialogue == null, "E far from the turtle cannot claim reward")
	talk()
	check(progress.reward_dialogue != null and paused and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 0, "nearby E opens turtle dialogue without granting early")
	save.reject = true
	finish_talk()
	check(not save.has_claimed_reward(progress.REWARD_ID) and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 0 and progress.reveal == null, "failed mirror grant has no item, claim or reveal")
	check(not paused and not (scene.player as LanPlayer).input_frozen, "failed delivery restores controls for another conversation")
	save.reject = false
	progress.tick(1.1)
	check(progress.reward_hint != null and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 0, "save retry only restores E hint, never auto grants")
	talk()
	finish_talk()
	check(save.has_claimed_reward(progress.REWARD_ID) and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 1 and save.has_completed(progress.TALK_FACT), "finished turtle dialogue grants one unique mirror")
	check(progress.reveal != null and paused and (scene.player as LanPlayer).input_frozen, "shared acquisition reveal pauses gameplay and freezes player")
	check(not scene.request_switch(), "reward reveal blocks map input")
	progress.reveal.call("_finish_reveal")
	await process_frame
	check(not paused and not (scene.player as LanPlayer).input_frozen and save.has_completed(progress.REVEAL_FACT), "closing reveal restores gameplay and saves viewing fact")
	progress.tick(1.1)
	check(progress.reveal == null and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 1, "no repeated reveal or duplicate mirror")
	scene.player.position = Vector2(6000, MirrorLake.STAND_Y)
	check(scene.request_switch(), "switch into yin after reveal")
	check(scene.controls_inverted(), "owning an unequipped mirror keeps inversion")
	key(KEY_D, true)
	key(KEY_W, true)
	check(Input.is_physical_key_pressed(KEY_A) and Input.is_physical_key_pressed(KEY_S), "held D and W are actually inverted before equip")
	save.reject = true
	check(not save.equip_special_item(ItemCatalog.NINGXIN_MIRROR) and scene.controls_inverted(), "failed equipment save does not activate passive mirror")
	save.reject = false
	var inventory := root.get_node("InventoryScreen") as InventoryUI
	var original_inventory_save := inventory._save
	inventory._save = save
	inventory._on_item_equip_requested(ItemCatalog.NINGXIN_MIRROR)
	inventory._save = original_inventory_save
	check(save.get_equipped_special_item() == ItemCatalog.NINGXIN_MIRROR, "mirror equips through the existing backpack equip action")
	check(not scene.controls_inverted() and not scene.control_inverter.inverted, "equipping immediately disables yin inversion")
	check(Input.is_physical_key_pressed(KEY_D) and Input.is_physical_key_pressed(KEY_W) and not Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_S), "equip restores held right and up without stuck inverse keys")
	check((scene.player as LanPlayer).are_attacks_allowed() and not (scene.player as LanPlayer).are_parries_allowed(), "mirror preserves yin attack and parry rules")
	save.equip_special_item(&"")
	check(scene.controls_inverted() and Input.is_physical_key_pressed(KEY_A) and Input.is_physical_key_pressed(KEY_S), "unequip restores inverse held inputs immediately")
	save.equip_special_item(ItemCatalog.NINGXIN_MIRROR)
	key(KEY_D, false)
	key(KEY_W, false)
	check(not Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_S) and not Input.is_physical_key_pressed(KEY_D) and not Input.is_physical_key_pressed(KEY_W), "releasing real inputs leaves no stuck keys")
	var serialized := save._config.encode_to_text()
	scene.queue_free()
	await process_frame
	save._config = ConfigFile.new()
	save._config.parse(serialized)
	make_scene()
	await process_frame
	scene.lake_progress.tick(0.1)
	check(scene.entry.gate_open and scene.entry.seal_activated and scene.lake_progress.seal_count == 5, "reload restores entrance gate and all five seals")
	check(scene.puzzle_stele.state == MinigameStele.SteleState.COMPLETED and scene.lake_progress.reveal == null and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 1, "reload restores completion without another reward or reveal")
	scene.player.position.x = 6000
	scene.request_switch()
	check(not scene.controls_inverted(), "equipped mirror remains effective after serialized reload")
	check(not save.has_completed(&"mirror_lake_boss_defeated"), "optional mirror progression does not complete or gate boss")
	save._config.set_value(SaveProgressService.PROGRESS_SECTION, String(MirrorLakeProgress.REVEAL_FACT), false)
	scene.lake_progress.tick(1.1)
	check(not paused and scene.lake_progress.reveal == null and scene.lake_progress.reward_hint != null, "unseen acquisition waits for E conversation instead of auto-opening on reload")
	talk()
	finish_talk()
	check(paused and scene.lake_progress.reveal != null and save.get_item_count(ItemCatalog.NINGXIN_MIRROR) == 1, "E conversation can resume unseen card without duplicate reward")
	scene.queue_free()
	await process_frame
	check(not paused, "tearing down the reward reveal restores tree pause state")
	root.remove_child(save)
	save.free()
	root.add_child(original)
	print("Mirror lake progression: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
