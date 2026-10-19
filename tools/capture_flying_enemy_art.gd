extends SceneTree
## Render the production bat and wind-trial caster without entering a story map.
## Usage: Godot --path ../homeing-star-game --script <this file> -- <capture dir>
var world: Node2D
var bird: WindCombatTrial
var bat: BackAlleyBat
var actor: LanPlayer
var output: String

func _initialize() -> void:
	call_deferred("run")

func capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename + ".png"))

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	world = Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	camera.position = Vector2(640, 360)
	world.add_child(camera)
	var backdrop := Polygon2D.new()
	backdrop.polygon = PackedVector2Array([Vector2.ZERO, Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)])
	backdrop.color = Color("263f45")
	backdrop.z_index = -100
	world.add_child(backdrop)
	var label := Label.new()
	label.text = "Back-alley bat                         Wind trial: approved Fly / Idle"
	label.position = Vector2(60, 160)
	world.add_child(label)
	actor = load("res://scenes/player/lan/lan_player.tscn").instantiate()
	actor.world_min_x = 0
	actor.world_max_x = 1280
	world.add_child(actor)
	actor.position = Vector2(750, 610)
	actor.set_input_frozen(true)
	actor.set_physics_process(false)
	bat = load("res://scenes/enemies/back_alley/back_alley_bat.tscn").instantiate()
	bat.position.x = 200
	bat.setup(2, 510, 100)
	world.add_child(bat)
	assert(bat.animated_sprite.sprite_frames.get_frame_count(&"fly") == 2)
	assert(not bat.animated_sprite.sprite_frames.has_animation(&"death"))
	assert(bat.animated_sprite.position.y == bat.hurtbox_shape.position.y)
	bird = WindCombatTrial.new()
	world.add_child(bird)
	bird.setup(actor, Rect2(400, 240, 800, 380), 3)
	assert(bird._bird.texture == WindCombatTrial.BIRD_IDLE)
	await capture("warning_idle")
	bird.step(WindCombatTrial.WARNING_TIME + 0.15)
	assert(bird._bird.texture == WindCombatTrial.BIRD_FLY)
	await capture("active_fly")
	bat.receive_hit(1, actor.global_position)
	await create_timer(0.20).timeout
	assert(bat.animated_sprite.is_playing())
	bird.flow = WindCombatTrial.Flow.DOWN
	bird.state_age = bird.active_duration() - 0.01
	bird.step(0.02)
	assert(bird.state == WindCombatTrial.State.RECOVERY)
	assert(bird._bird.texture == WindCombatTrial.BIRD_IDLE)
	await capture("recovery_idle")
	bat.receive_hit(1, actor.global_position)
	assert(bat._dying)
	assert(not bat.animated_sprite.is_playing())
	await create_timer(0.10).timeout
	await capture("bat_defeat_fade")
	await create_timer(0.20).timeout
	assert(not is_instance_valid(bat))
	bird.stop()
	assert(not bird.visible)
	print("Flying enemy art: frame layouts, state selection, hit recovery and death cleanup passed")
	world.queue_free()
	await process_frame
	quit()
