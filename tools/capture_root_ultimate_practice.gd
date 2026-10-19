extends SceneTree

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var output := ProjectSettings.globalize_path("res://").path_join("../homeing-star-test/artifacts/root-ultimate-practice-20261012")

func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	room = load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	room.player.set_physics_process(false)
	room.player.position = Vector2(1250, 555)
	var boss := room.deer
	boss.set_physics_process(false)
	boss.vfx.set_process(false)
	boss.manual_control = false
	boss.phase = 2
	boss.start_root_hunt()
	room._refresh_core_state()
	for i in 541:
		boss._physics_process(1.0 / 60)
		boss.vfx._process(1.0 / 60)
		if i == 467: await capture("01_warning_invincible")
		elif i == 510: await capture("02_active_invincible")
		elif i == 540: await capture("03_recovery_invincible")
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	await capture("04_invincibility_off")
	print("ROOT_CAPTURE: player HP=", room.player.combat_stats.health, " screenshots saved to ", output)
	room.queue_free()
	await process_frame; await process_frame
	quit()
