extends SceneTree
## Keep map-local action anchors stable while the scrolling WorldRoot moves.
class MemorySave extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var scene: MirrorLake
var player: LanPlayer
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + message)
func place(x: float) -> void:
	player.combat_timeline.stop()
	player.attack_state = LanPlayer.AttackState.NONE
	player.ground_action_state = LanPlayer.GroundActionState.NONE
	player.air_state = LanPlayer.AirState.GROUNDED
	player.position = Vector2(x, MirrorLake.STAND_Y)
	player.velocity = Vector2.ZERO
	player.instant_dash_cooldown_remaining = 0
	player.play_idle()
	scroll()
func scroll(extra := Vector2.ZERO) -> void:
	scene.camera_x = MirrorLake.camera_x_for(player.position.x) + extra.x
	scene.camera_y = MirrorLake.camera_y_for(player.position.y) + extra.y
	scene.update_scroll()
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HOMING_STAR_TEST_OUTPUT").path_join(label + ".png"))
func run() -> void:
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var memory := MemorySave.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	scene.ink_trial.set_physics_process(false)
	player = scene.player as LanPlayer
	player.set_physics_process(false)
	scene.entry.activate_seal()
	scene.request_switch()
	scene.advance_switch(3)
	await process_frame
	for spec in [[2100.0,-1.0],[2100.0,1.0],[6000.0,1.0],[13780.0,1.0]]:
		var x: float = spec[0]
		var direction: float = spec[1]
		place(x)
		if x == 2100 and direction < 0: await shot("01_before_U")
		var expected := clampf(x + direction * player.INSTANT_DASH_DISTANCE, player.world_min_x, player.world_max_x)
		player.start_instant_dash(direction)
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y), "U startup stays on map standing line at x=" + str(x))
		scroll(Vector2(125, 25))
		player.animated_sprite.frame = player.INSTANT_DASH_TELEPORT_FRAME
		player.update_instant_dash_phase()
		check(is_equal_approx(player.position.x, expected), "U keeps intended map distance/bounds while parent scrolls at x=" + str(x))
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y), "U stays on original floor after teleport")
		player.on_animation_finished()
		scroll()
		check(is_equal_approx(scene.camera_y, MirrorLake.CAMERA_Y_REST), "U does not pull camera down into lake")
		if x == 2100 and direction < 0: await shot("02_after_U")
	for direction in [-1.0, 1.0]:
		place(6000)
		if direction > 0: await shot("03_before_roll_finisher")
		var expected: float = player.position.x + float(direction) * player.DODGE_ATTACK_3_FALLBACK_DISTANCE
		player.start_dodge_attack_3x(direction)
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y), "roll finisher charge stays on map floor")
		scroll(Vector2(-180, 40))
		player.update_dodge_attack_3_phase()
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y), "roll finisher charge ignores camera transform")
		player._timeline_dodge_attack_3_teleport()
		check(is_equal_approx(player.position.x, expected), "roll finisher keeps map-local horizontal fallback")
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y - player.DODGE_ATTACK_3_DROP_HEIGHT), "roll finisher drops from authored height above map floor")
		player.dodge_attack_3_landed = true
		player.update_dodge_attack_3_phase()
		scroll()
		check(is_equal_approx(player.position.y, MirrorLake.STAND_Y) and is_equal_approx(scene.camera_y, MirrorLake.CAMERA_Y_REST), "roll finisher lands without sinking or lowering camera")
		if direction > 0:
			player.combat_timeline.stop()
			player.finish_ground_attack()
			await shot("04_after_roll_finisher")
	place(6000)
	var target := Node2D.new()
	target.position = Vector2(6240, MirrorLake.STAND_Y)
	scene.world_root.add_child(target)
	target.add_to_group(&"damageable")
	player.start_dodge_attack_3x(1)
	scroll(Vector2(230, -30))
	player._timeline_dodge_attack_3_teleport()
	check(is_equal_approx(player.position.x, target.position.x - player.DODGE_ATTACK_3_TARGET_OFFSET), "roll finisher converts chased target from global to map coordinates")
	scene.queue_free()
	await process_frame
	root.remove_child(memory)
	memory.free()
	root.add_child(original)
	print("Mirror lake displacement: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
