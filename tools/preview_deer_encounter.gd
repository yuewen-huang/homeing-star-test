extends "../tests/support/harness.gd"
## The actual shipped room and ordinary player; only persistence is isolated.
class RetryControls extends Node:
	func _unhandled_key_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_R:
			var room := get_tree().current_scene as Chapter1DeerBossRoom
			if room!=null and not room.story._settled and not get_tree().paused:
				room.restart_mist_phase()
				if "--vine-phase" in OS.get_cmdline_user_args():
					room.encounter._spawn_phase(3,room.encounter.arena_center+180)
					room.encounter.start()
				get_viewport().set_input_as_handled()
func run() -> void:
	use_memory_progress()
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(false)
	DisplayServer.window_set_title("朽角巡林者 · 正式四阶段试玩 · R 重试（存档隔离）")
	var room := load("res://scenes/levels/chapter_1/chapter_1_deer_boss_room.tscn").instantiate() as Chapter1DeerBossRoom
	var vine_only: bool="--vine-phase" in OS.get_cmdline_user_args()
	if vine_only:
		var intro:=WindSightingComic.new()
		var packed:=PackedScene.new()
		packed.pack(intro)
		intro.free()
		room.deer_intro_scene=packed
	root.add_child(room)
	current_scene=room
	root.add_child(RetryControls.new())
	await wait_frames(3)
	if vine_only:
		room.encounter._spawn_phase(3,room.encounter.arena_center+180)
		room.encounter.start()
		DisplayServer.window_set_title("朽角巡林者 · 正式森林藤阶段试玩 · R 重试（存档隔离）")
		print("DEER VINE PRODUCTION READY: actual forest room; phase=",room.encounter.phase,"; R retries vine; isolated progress")
	print("DEER PRODUCTION READY: shipped room; mist/root/vine/wind; ordinary player; isolated progress")
