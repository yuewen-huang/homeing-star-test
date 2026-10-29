extends SceneTree
## Graphic switch HUD follows the real switch state and live InputMap binding.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_text: String) -> void: pass

var failures := 0
var checks := 0
var scene: MirrorLake
var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + message)

func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var save := MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	var bindings := InputMap.action_get_events(MirrorLake.SWITCH_ACTION)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.player.set_physics_process(false)
	scene.ink_trial.set_physics_process(false)
	var hud := scene.switch_hud
	scene.update_debug_label()
	check(hud != null and not hud.is_yin and hud.available, "white sun jade ready on yang side")
	check(hud.key_label.text == KeyHint.resolve_action_key_label(MirrorLake.SWITCH_ACTION), "key comes from current InputMap")
	check(scene.find_child("SwitchDebugLabel", true, false) == null, "old debug sentence removed")
	await shot("01_yang_ready")
	check(scene.request_switch(), "real switch accepted")
	scene.advance_switch(0.7)
	scene.update_debug_label()
	check(hud.is_yin and hud.inverted and not hud.available, "moon jade and red swap symbol follow yin")
	check(is_equal_approx(hud.cooldown_ratio, 0.65), "cooldown ring tracks actual remaining time")
	check(not scene.request_switch(), "HUD does not bypass cooldown")
	await shot("02_yin_cooling")
	scene.advance_switch(2)
	scene.update_debug_label()
	check(hud.available and hud.cooldown_ratio == 0, "ring clears when switch ready")
	await shot("03_yin_ready")
	check(save.claim_unique_reward(&"hud_fixture_mirror", ItemCatalog.NINGXIN_MIRROR), "fixture owns mirror")
	check(save.equip_special_item(ItemCatalog.NINGXIN_MIRROR), "fixture equips mirror")
	scene.refresh_controls()
	scene.update_debug_label()
	check(hud.is_yin and not hud.inverted, "equipped mirror keeps moon jade and restores normal compass")
	await shot("04_yin_mirror_equipped")
	InputMap.action_erase_events(MirrorLake.SWITCH_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_G
	InputMap.action_add_event(MirrorLake.SWITCH_ACTION, key)
	scene.update_debug_label()
	check(hud.key_label.text == "G", "live rebinding F to G updates plaque")
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(scene.side == MirrorLake.Side.YANG, "remapped key actually switches the lake")
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	scene.advance_switch(3)
	scene.update_debug_label()
	await shot("05_rebound_G")
	InputMap.action_erase_events(MirrorLake.SWITCH_ACTION)
	key = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	key.ctrl_pressed = true
	InputMap.action_add_event(MirrorLake.SWITCH_ACTION, key)
	scene.update_debug_label()
	check(hud.key_label.text == "Ctrl+Space" and hud.key_width > 36, "modifier and longer binding expands plaque")
	await shot("06_long_binding")
	InputMap.action_erase_events(MirrorLake.SWITCH_ACTION)
	scene.update_debug_label()
	check(hud.key_label.text == "—", "unbound action does not falsely display F")
	for binding in bindings: InputMap.action_add_event(MirrorLake.SWITCH_ACTION, binding)
	scene.queue_free()
	await process_frame
	root.remove_child(save)
	save.free()
	root.add_child(original)
	print("Switch HUD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
