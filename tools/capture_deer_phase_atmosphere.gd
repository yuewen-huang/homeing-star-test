extends SceneTree

var room
var deer: DeerBoss
var output := ""

func _initialize() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func tick(count: int) -> void:
	for i in count:
		deer._physics_process(1.0/60.0)
		room._physics_process(1.0/60.0)
		deer.vfx._process(1.0/60.0)

func shot(label: String) -> void:
	room._process(0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("CAPTURE ",label)

func run() -> void:
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	deer = room.adapter.deer
	room.player.set_physics_process(false)
	room.player.position.x = 70
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	for phase in [1,2,3]:
		room.select_combo(phase-1)
		deer.position = Vector2(820,555)
		deer.direction = 1
		deer._show_clip(&"idle_ING",0)
		deer.vfx.reset_effects()
		deer.vfx.phase_atmosphere_enabled = true
		for i in 180: deer.vfx._process(1.0/60.0)
		await shot("phase%d_idle_on" % phase)
		deer.vfx.phase_atmosphere_enabled = false
		deer.vfx._process(0.0)
		await shot("phase%d_idle_off" % phase)
		deer.vfx.phase_atmosphere_enabled = true
		room.play_action(1)
		for i in 180:
			tick(1)
			if deer.vfx.red_warning.visible and deer.vfx.red_warning.frame == 1: break
		assert(deer.vfx.red_warning.visible,"Capture needs the actual danger cue")
		await shot("phase%d_warning" % phase)
		for i in 180:
			tick(1)
			if deer.attack_hitbox.attack != null: break
		assert(deer.attack_hitbox.attack != null,"Capture needs the actual active hitbox")
		await shot("phase%d_active" % phase)
		for i in 180:
			tick(1)
			if deer.attack_hitbox.attack == null and String(deer.animated_sprite.animation).ends_with("_END"): break
		await shot("phase%d_recovery" % phase)
	room.free()
	quit()
