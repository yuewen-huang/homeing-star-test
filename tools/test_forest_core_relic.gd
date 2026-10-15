extends SceneTree

class TestProgress extends SaveProgressService:
	var writes_fail := false
	var snapshot := ""
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		if writes_fail:
			return false
		snapshot = _config.encode_to_text()
		return true
	func is_ability_unlocked(_ability: StringName) -> bool:
		return true

var save: TestProgress
var failures := 0
var host: Node2D
var player: LanPlayer

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1

func frames(n := 3) -> void:
	for i in n: await process_frame

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(filename + ".png"))

func finish_dialogue(gift: MasterCoreGift) -> void:
	var dialogue := gift.dialogue
	var remaining := dialogue.get_line_progress().y - dialogue.get_line_progress().x
	for i in remaining: dialogue.advance()

func key_space() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await create_timer(0.6).timeout
	key = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.keycode = KEY_SPACE
	Input.parse_input_event(key)
	await frames()

func run() -> void:
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = TestProgress.new()
	save.name = "SaveProgress"
	root.add_child(save)
	host = Node2D.new()
	root.add_child(host)
	current_scene = host
	player = load("res://scenes/sideview/lan_player.tscn").instantiate()
	player.position = Vector2(640, 555)
	player.world_min_x = 0
	player.world_max_x = 1280
	player.fallback_ground_y = 555
	host.add_child(player)
	player.set_physics_process(false)
	# Compare the actual existing acquisition UI with the new item's presentation.
	var reference = load("res://scripts/ui/item_acquisition_reveal.gd").new()
	reference.setup(ItemCatalog.HANGOVER_PILL)
	host.add_child(reference)
	await capture("relic_reference_hangover_pill")
	reference.queue_free()
	await frames()
	var gift := MasterCoreGift.new()
	host.add_child(gift)
	gift.begin(player, save)
	check(player.input_frozen and gift.dialogue != null, "Handover dialogue owns the player's input lock")
	check(save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 0, "Beginning dialogue grants nothing")
	save.writes_fail = true
	finish_dialogue(gift)
	check(save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 0 and not save.has_claimed_reward(ForestCoreRelic.REWARD_ID), "Failed grant rolls back both item and reward")
	check(gift.reveal == null and gift.dialogue != null and player.input_frozen, "Failed grant waits for explicit retry instead of displaying success")
	save.writes_fail = false
	finish_dialogue(gift)
	check(save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1 and gift.reveal != null, "Retry grants and displays one pendant")
	check(ForestCoreRelic.power_mask(save) == Vector4.ZERO, "New pendant has four empty slots")
	await capture("relic_empty_reveal")
	# Closing mid-presentation retains ownership but leaves presentation recoverable.
	gift.free()
	check(not player.input_frozen and ForestCoreRelic.needs_gift(save), "Interrupted reveal restores input and remains recoverable")
	gift = MasterCoreGift.new()
	host.add_child(gift)
	gift.begin(player, save)
	check(gift.dialogue == null and gift.reveal != null and save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1, "Recovery resumes reveal without repeating grant")
	save.writes_fail = true
	await key_space()
	check(is_instance_valid(gift) and gift.reveal == null and gift.dialogue != null \
		and not save.has_completed(ForestCoreRelic.PRESENTED_ID) and player.input_frozen, "Failed presentation write keeps a recoverable retry after the actual shrink animation")
	save.writes_fail = false
	finish_dialogue(gift)
	await frames()
	check(not is_instance_valid(gift) and not player.input_frozen and save.has_completed(ForestCoreRelic.PRESENTED_ID), "Retry records presentation and restores input")
	check(save.equip_special_item(ItemCatalog.SPIRIT_PENDANT), "Pendant can be equipped in the Q item slot")

	# Any order, independent absorption, duplicate events, and serialization.
	for region in [3, 0, 2, 1]:
		save.try_complete_fact(ForestCoreRelic.victory_id(region))
		save.writes_fail = true
		check(not ForestCoreRelic.absorb_available(save) and not save.has_completed(ForestCoreRelic.power_id(region)), "Failed %s absorption remains uncommitted" % ForestCoreRelic.TITLES[region])
		save.writes_fail = false
		check(ForestCoreRelic.absorb_available(save) and save.has_completed(ForestCoreRelic.power_id(region)), "Retry absorbs %s power" % ForestCoreRelic.TITLES[region])
	check(ForestCoreRelic.power_mask(save) == Vector4.ONE and save.get_item_count(ItemCatalog.SPIRIT_PENDANT) == 1, "All four powers fill independent slots without duplicating pendant")
	check(ForestCoreRelic.absorb_available(save), "Repeated settlement is idempotent")
	save._config = ConfigFile.new()
	save._config.parse(save.snapshot)
	check(ForestCoreRelic.power_mask(save) == Vector4.ONE and not ForestCoreRelic.needs_gift(save), "Reload preserves ownership, completed presentation and all four powers")
	var charged = load("res://scripts/ui/item_acquisition_reveal.gd").new()
	charged.setup(ItemCatalog.SPIRIT_PENDANT)
	host.add_child(charged)
	await capture("relic_charged_reveal")
	charged.queue_free()
	await frames()
	var inventory := InventoryUI.new()
	host.add_child(inventory)
	inventory._category_index = 2
	inventory._refresh()
	inventory.visible = true
	inventory._show_tooltip(ItemCatalog.SPIRIT_PENDANT)
	check(inventory._tooltip_description.text.count("已解锁") == 4, "Backpack explains all four saved power skills")
	await capture("relic_backpack")
	inventory.queue_free()
	await frames()
	host.free()
	current_scene = null
	# Actual production room: victory signal, failed save retry, and defeated-room restore.
	save.load_progress()
	var room: Chapter1BossRoom = load("res://scenes/sideview/chapter_1_wind_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames()
	var core := room.regional_core
	save.writes_fail = true
	core.combat_stats.apply_health_damage(core.combat_stats.max_health)
	check(room._core_settlement_pending and not save.has_completed(ForestCoreRelic.victory_id(0)), "Failed production core victory is retryable and does not invent a saved win")
	save.writes_fail = false
	room._settle_core_victory()
	check(save.has_completed(ForestCoreRelic.victory_id(0)) and not save.has_completed(ForestCoreRelic.power_id(0)), "Core victory without pendant stores the victory alone")
	room.free()
	current_scene = null
	room = load("res://scenes/sideview/chapter_1_wind_boss_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await frames()
	check(room.regional_core.combat_stats.health == 0 and not room.regional_core.blue_shield_active and not room.regional_core.gold_shield_active, "Re-entering a cleared core room restores the defeated core without shields")
	save.claim_unique_reward(ForestCoreRelic.REWARD_ID, ItemCatalog.SPIRIT_PENDANT)
	check(ForestCoreRelic.absorb_available(save) and save.has_completed(ForestCoreRelic.power_id(0)), "A pendant received later absorbs a previously defeated core")
	for region in [2, 1, 3]:
		check(not save.has_completed(ForestCoreRelic.power_id(region)), "A wind victory never awards another region's power")
	print("FOREST CORE RELIC: ", failures, " failures")
	quit(1 if failures else 0)
