extends SceneTree
## Screenshots of the shared full-screen looks in the deer development room: dodge bullet
## time (global), the red-counter pulse and the god-statue green pulse, each before and at
## its peak. Usage: --script tools/capture_screen_pulses.gd -- <out dir>

var output := ""

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func frames(count: int) -> void:
	for i in count: await process_frame

func run() -> void:
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await frames(3)
	room.select_combo(2)
	var player: LanPlayer = room.player
	var deer: DeerBoss = room.adapter.deer
	await shot("0_baseline")
	player.dodge_evaded_attack.emit(deer, LanPlayer.DODGE_BULLET_TIME_DURATION)
	await frames(2); await shot("1_bullet_time_flash")
	await frames(16); await shot("2_bullet_time_hold")
	await create_timer(3.5).timeout
	feedback.emit_parry_success(deer, CombatAttackData.new(&"t", deer, 20, 12, 180.0, 0.0, CombatAttackData.DangerType.COUNTERABLE_DANGER), deer.global_position)
	await frames(2); await shot("3_red_counter_pulse")
	await create_timer(1.0, true, false, true).timeout
	feedback.screen_fx.vignette_pulse(DeerGodCome.FLASH_TINT, DeerGodCome.FLASH_TIME + 0.2)
	await frames(6); await shot("4_god_green_pulse")
	quit(0)
