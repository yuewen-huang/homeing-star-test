extends SceneTree
## Native puzzle progress, common acquisition card, backpack and passive equip review.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_text: String) -> void: pass
var output := "E:/HomingStar/homeing-star-temp-assert/artifacts/ningxin_mirror"
var scene: MirrorLake
func _initialize() -> void: run.call_deferred()
func shot(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var save := MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.ink_trial.set_physics_process(false)
	var progress := scene.lake_progress
	scene.player.position = scene.puzzle_stele.position + Vector2(-125,0)
	scene.camera_x = scene.puzzle_stele.position.x
	scene.update_scroll()
	progress.tick(0)
	await shot("01_zero_of_five")
	scene.entry.activate_seal()
	scene.shadow_bridge.fix_bridge(0)
	progress.tick(0)
	await shot("02_two_of_five")
	scene.shadow_bridge.fix_bridge(1)
	save.claim_unique_reward(MirrorLakeInkCarp.REWARD_ID, MirrorLakeInkCarp.REWARD_ITEM)
	progress.tick(0)
	await shot("03_four_of_five")
	save.claim_unique_reward(MirrorLakeLotus.REWARD_ID, MirrorLakeLotus.REWARD_ITEM)
	progress.tick(0)
	await shot("04_puzzle_complete")
	scene.player.position = scene.ink_trial.position + Vector2(-155,0)
	scene.camera_x = scene.ink_trial.position.x - 155
	scene.update_scroll()
	scene.ink_trial._try_complete()
	scene.ink_trial._refresh()
	progress.tick(0)
	assert(progress.reveal == null and not paused)
	await shot("04b_turtle_E_ready")
	scene.player.position = scene.ink_trial.position + scene.ink_trial.turtle.position + Vector2(65,0)
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.keycode = KEY_E
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	e = e.duplicate()
	e.pressed = false
	Input.parse_input_event(e)
	Input.flush_buffered_events()
	assert(progress.reward_dialogue != null)
	await shot("04c_turtle_reward_dialogue")
	progress.reward_dialogue.advance()
	await shot("04d_lan_reward_dialogue")
	while progress.reward_dialogue != null: progress.reward_dialogue.advance()
	assert(progress.reveal != null)
	await shot("05_acquisition")
	progress.reveal.call("_finish_reveal")
	await process_frame
	scene.request_switch()
	scene.advance_switch(3)
	scene.update_debug_label()
	await shot("06_owned_not_equipped_yin")
	var inventory := root.get_node("InventoryScreen") as InventoryUI
	var inventory_save := inventory._save
	inventory._save = save
	inventory._category_index = inventory.CATEGORIES.find(ItemCatalog.CATEGORY_QUEST)
	inventory.visible = true
	inventory._refresh()
	inventory._on_item_equip_requested(ItemCatalog.NINGXIN_MIRROR)
	inventory._show_tooltip(ItemCatalog.NINGXIN_MIRROR)
	await shot("07_backpack_equipped")
	inventory.close_inventory()
	inventory._save = inventory_save
	scene.update_debug_label()
	await shot("08_equipped_yin")
	scene.queue_free()
	await process_frame
	root.remove_child(save)
	save.free()
	root.add_child(original)
	quit()
