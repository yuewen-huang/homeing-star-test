extends SceneTree
## Real receiver paths plus native SpriteFrames timing and owner cleanup.

var room: Node2D
var feedback: CombatFeedbackService
var checks := 0
var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
	print("OK " if condition else "FAIL ", label)


func clear_feedback() -> void:
	feedback.hit_stop_serial += 1
	Engine.time_scale = 1.0
	feedback.screen_fx.clear()
	feedback._reset_punch()
	feedback.shake_remaining = 0.0
	if is_instance_valid(feedback.shake_target):
		feedback.shake_target.offset = feedback.shake_base_offset
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP):
		effect.free()


func expect_effect(kind: CombatImpactEffect.Kind, receiver: Node = null) -> CombatImpactEffect:
	var effects := get_nodes_in_group(CombatImpactEffect.GROUP)
	check(effects.size() == 1, "One painted effect per event without old overlay")
	if effects.size() != 1:
		return null
	var effect := effects[0] as CombatImpactEffect
	check(effect.kind == kind, "Correct shared artwork for event %d" % kind)
	check(effect.frame == 0 and effect.is_playing(), "Immediate first impact frame")
	if receiver != null:
		check(effect.get_parent() == receiver, "Receiver owns effect for scene/specimen cleanup")
	return effect


func attack(receiver: DamageReceiver2D, red := false) -> CombatAttackData:
	return CombatAttackData.new(&"shared_art_test", receiver, 12, 12, 180.0, 0.0,
		CombatAttackData.DangerType.COUNTERABLE_DANGER if red else CombatAttackData.DangerType.NORMAL)


func run() -> void:
	var saved_existed := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if saved_existed else PackedByteArray()
	room = Node2D.new()
	root.add_child(room)
	current_scene = room
	var camera := Camera2D.new()
	room.add_child(camera)
	camera.make_current()
	feedback = root.get_node("CombatFeedback") as CombatFeedbackService
	var player := load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
	player.name = "Lan"
	player.world_min_x = -1000.0
	player.world_max_x = 2000.0
	room.add_child(player)
	player.set_physics_process(false)
	await process_frame
	var counts := [3, 4, 6, 8, 8]
	var durations := [0.13, 0.26, 0.26, 0.34, 0.34]
	for kind in counts.size():
		var animation_name: StringName = CombatImpactEffect.ANIMATIONS[kind]
		var frames := CombatImpactEffect.FRAMES
		check(frames.get_frame_count(animation_name) == counts[kind], "Authored frame count for %s" % animation_name)
		var duration := 0.0
		for frame in frames.get_frame_count(animation_name):
			duration += frames.get_frame_duration(animation_name, frame) / frames.get_animation_speed(animation_name)
		check(is_equal_approx(duration, durations[kind]) and not frames.get_animation_loop(animation_name), "Authored duration/non-loop for %s" % animation_name)
	clear_feedback()
	player.emit_received_hit_feedback(Vector2(-100, 0), 1.0)
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT)
	clear_feedback()
	var bat := load("res://scenes/sideview/back_alley_bat.tscn").instantiate() as BackAlleyBat
	bat.health = 20
	room.add_child(bat)
	bat.set_process(false)
	bat.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT, bat)
	clear_feedback()
	var slime := load("res://scenes/sideview/back_alley_slime.tscn").instantiate() as BackAlleySlime
	slime.health = 20
	room.add_child(slime)
	slime.set_process(false)
	slime.receive_hit(1, Vector2(100, 0))
	var left := expect_effect(CombatImpactEffect.Kind.NORMAL_HIT, slime)
	check(left.flip_h, "Right-side source mirrors force toward the left")
	clear_feedback()
	var mist := MistAmbusher.new()
	mist.setup(player, MistAmbusher.Species.BOAR, Vector2(500, 555))
	room.add_child(mist)
	mist.set_physics_process(false)
	mist.state = MistAmbusher.State.WARNING
	mist.receive_hit(1, Vector2(100, 555))
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT, mist)
	clear_feedback()
	var dummy := load("res://scenes/sideview/training_dummy.tscn").instantiate() as TrainingDummy
	room.add_child(dummy)
	dummy.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT, dummy)
	clear_feedback()
	dummy.combat_stats.apply_poise_damage(dummy.combat_stats.poise - 10)
	dummy.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.POISE_BREAK, dummy)
	clear_feedback()
	dummy.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.BROKEN_HIT, dummy)
	clear_feedback()
	var deer := DeerBoss.new()
	var deer_mist := DeerMistField.new()
	deer_mist.player = player
	room.add_child(deer_mist)
	deer_mist.set_process(false)
	deer.setup(player, deer_mist)
	deer.manual_control = true
	deer.vine_test_mode = true
	room.add_child(deer)
	deer.set_physics_process(false)
	deer.vfx.set_process(false)
	await process_frame
	await process_frame
	clear_feedback()
	deer.combat_stats.apply_poise_damage(deer.combat_stats.poise - 10)
	deer.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.POISE_BREAK, deer)
	clear_feedback()
	deer.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.BROKEN_HIT, deer)
	clear_feedback()
	var master := load("res://scenes/sideview/tutorial_master_boss.tscn").instantiate() as DamageReceiver2D
	master.set("world_min_x", -1000.0)
	master.set("world_max_x", 2000.0)
	master.set("aggro_target_path", NodePath("../Lan"))
	master.set("manual_control", true)
	room.add_child(master)
	master.set_process(false)
	master.set_physics_process(false)
	master.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT, master)
	clear_feedback()
	var master_stats := master.get("combat_stats") as CombatantStats
	master_stats.apply_poise_damage(master_stats.poise - 1)
	master.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.POISE_BREAK, master)
	clear_feedback()
	master.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.BROKEN_HIT, master)
	clear_feedback()
	var guard := load("res://scenes/sideview/lan_player.tscn").instantiate() as LanPlayer
	guard.world_min_x = -1000.0
	guard.world_max_x = 2000.0
	room.add_child(guard)
	guard.set_physics_process(false)
	guard.start_parry_nothing()
	var health_before := guard.combat_stats.health
	var incoming := CombatAttackData.new(&"half_guard", bat, 20, 12, 180.0, 0.0)
	var result := guard.receive_combat_hit(incoming)
	check(result == CombatHitResult.Type.PARRY_FAILURE and guard.combat_stats.health == health_before - 10, "Existing ordinary guard still deals half damage")
	expect_effect(CombatImpactEffect.Kind.NORMAL_HIT)
	clear_feedback()
	# Settle real player defense through the common hurtbox/hitbox path.
	var hitbox := CombatHitbox2D.new()
	room.add_child(hitbox)
	hitbox.set_physics_process(false)
	guard.start_parry()
	guard.animated_sprite.frame = 3
	guard.on_player_animation_frame_changed()
	health_before = guard.combat_stats.health
	var hurtbox := guard.get_node("Hurtbox") as CombatHurtbox2D
	var normal_attack := CombatAttackData.new(&"native_normal_parry", bat, 20, 12, 180, 0)
	result = hurtbox.receive_attack(normal_attack)
	hitbox._complete_hit(guard, hurtbox.global_position, normal_attack, result)
	check(result == CombatHitResult.Type.PARRY_SUCCESS and guard.combat_stats.health == health_before, "Real player normal parry settles without damage")
	expect_effect(CombatImpactEffect.Kind.PARRY, bat)
	clear_feedback()
	guard.start_parry()
	guard.animated_sprite.frame = 3
	guard.on_player_animation_frame_changed()
	var red_attack := CombatAttackData.new(&"native_red_parry", bat, 20, 12, 180, 0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	result = hurtbox.receive_attack(red_attack)
	hitbox._complete_hit(guard, hurtbox.global_position, red_attack, result)
	check(result == CombatHitResult.Type.PARRY_SUCCESS and guard.combat_stats.health == health_before, "Real player red parry settles without damage")
	expect_effect(CombatImpactEffect.Kind.RED_PARRY, bat)
	clear_feedback()
	deer.finish_stagger()
	feedback._process(0.0)
	deer.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.POISE_BREAK, deer)
	clear_feedback()
	bat.on_attack_parried(attack(bat), bat.global_position + Vector2(-20, -32))
	var parry := expect_effect(CombatImpactEffect.Kind.PARRY, bat)
	check(not parry.flip_h, "Parry deflection points back toward a right-side attacker")
	check(is_equal_approx(feedback.punch_amount, 0.05), "Ordinary parry retains 5 percent camera punch")
	clear_feedback()
	bat.on_attack_parried(attack(bat, true), bat.global_position + Vector2(20, -32))
	var red := expect_effect(CombatImpactEffect.Kind.RED_PARRY, bat)
	check(red.flip_h and is_equal_approx(feedback.punch_amount, 0.11), "Red parry has distinct mirrored art and retains heavy camera punch")
	clear_feedback()
	deer.on_attack_parried(attack(deer, true), deer.global_position + Vector2(-50, -120))
	expect_effect(CombatImpactEffect.Kind.RED_PARRY, deer)
	clear_feedback()
	deer.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.BROKEN_HIT, deer)
	clear_feedback()
	deer.finish_stagger()
	feedback._process(0.0)
	deer.on_attack_parried(attack(deer), deer.global_position + Vector2(-50, -120))
	expect_effect(CombatImpactEffect.Kind.POISE_BREAK, deer)
	clear_feedback()
	deer.receive_hit(1, Vector2(-100, 0))
	expect_effect(CombatImpactEffect.Kind.BROKEN_HIT, deer)
	clear_feedback()
	var transformed := Node2D.new()
	transformed.position = Vector2(30, 40)
	transformed.scale = Vector2(3, 2)
	transformed.rotation = 0.7
	room.add_child(transformed)
	var placed := feedback.spawn_impact_effect(CombatImpactEffect.Kind.PARRY, Vector2(400, 250), -1, transformed)
	check(placed.global_position.is_equal_approx(Vector2(400, 250)), "World contact does not drift under a transformed owner")
	check(placed.global_scale.is_equal_approx(Vector2.ONE * 1.4) and is_zero_approx(placed.global_rotation), "Owner scale/rotation does not deform authored impact art")
	var weak_effect: WeakRef = weakref(placed)
	transformed.free()
	check(weak_effect.get_ref() == null, "Deleting receiver/specimen clears its feedback")
	clear_feedback()
	# Allow first-frame resource-loading stalls to settle before clock assertions.
	await process_frame
	await process_frame
	var timed := feedback.spawn_impact_effect(CombatImpactEffect.Kind.NORMAL_HIT, Vector2.ZERO, 0)
	Engine.time_scale = 0.05
	await create_timer(0.08, true, false, true).timeout
	check(is_instance_valid(timed) and timed.frame == 0, "Hit-stop holds the first impact frame in scaled combat time")
	Engine.time_scale = 1.0
	paused = true
	await create_timer(0.08, true, false, true).timeout
	check(is_instance_valid(timed) and timed.frame == 0, "Paused combat does not consume effect frames")
	paused = false
	await create_timer(0.22, true, false, true).timeout
	check(not is_instance_valid(timed), "Non-looping native animation automatically releases effect")
	clear_feedback()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == saved_existed and (not saved_existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Saved progress and inventory unchanged")
	current_scene = null
	room.free()
	# Let cancelled owner-bound tweens and queued native animations retire.
	await process_frame
	await process_frame
	print("SHARED COMBAT ART: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
