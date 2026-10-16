extends SceneTree
## Real receiver paths to the one shared procedural impact (2026-10-16), its colours by
## event, scaled-time playback and owner cleanup.

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
	check(effects.size() == 1, "One shared impact per event, nothing stacked")
	if effects.size() != 1:
		return null
	var effect := effects[0] as CombatImpactEffect
	check(effect.kind == kind, "Correct impact look for event %d" % kind)
	check(effect.star != null and effect.star.age >= effect.star.duration - 0.0001, "Star already open for the hit-stop frame")
	if receiver != null:
		check(effect.get_parent() == receiver, "Receiver owns effect for scene/specimen cleanup")
	return effect


func attack(receiver: DamageReceiver2D, red := false) -> CombatAttackData:
	return CombatAttackData.new(&"shared_art_test", receiver, 12, 12, 180.0, 0.0,
		CombatAttackData.DangerType.COUNTERABLE_DANGER if red else CombatAttackData.DangerType.NORMAL)


func run() -> void:
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	var prior_invincibility := assist.player_invincible
	assist.set_player_invincible(false)
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
	# Colour follows the event (user 2026-10-16); only poise breaks and the red counter's
	# close get the finisher (ring, all-round shards, shockwave).
	var palettes := {CombatImpactEffect.Kind.NORMAL_HIT: &"normal", CombatImpactEffect.Kind.PARRY: &"normal",
		CombatImpactEffect.Kind.RED_PARRY: &"red", CombatImpactEffect.Kind.PLAYER_HURT: &"red",
		CombatImpactEffect.Kind.POISE_BREAK: &"gold", CombatImpactEffect.Kind.BROKEN_HIT: &"gold",
		CombatImpactEffect.Kind.COUNTER_CUT: &"gold", CombatImpactEffect.Kind.COUNTER_FINISH: &"gold"}
	for kind: int in palettes:
		check(CombatImpactEffect.LOOKS[kind].palette == palettes[kind], "Event %d uses the %s palette" % [kind, palettes[kind]])
		var finisher: bool = CombatImpactEffect.LOOKS[kind].get("finisher", false)
		check(finisher == (kind in [CombatImpactEffect.Kind.POISE_BREAK, CombatImpactEffect.Kind.COUNTER_FINISH]), "Finisher look only for event %d when it closes a break or counter" % kind)
	var sizes: Array[float] = []
	for run in CombatFeedbackService.PARRY_CHAIN_MAX + 1:
		var probe := CombatImpactEffect.new()
		probe.setup(CombatImpactEffect.Kind.PARRY, 1.0, Vector2.ZERO, run)
		sizes.append(float(probe.look().spark))
		probe.free()
	var capped := CombatImpactEffect.new()
	capped.setup(CombatImpactEffect.Kind.PARRY, 1.0, Vector2.ZERO, CombatFeedbackService.PARRY_CHAIN_MAX + 3)
	var rising := true
	for i in range(1, sizes.size()): rising = rising and sizes[i] > sizes[i - 1]
	check(rising and float(capped.look().spark) == sizes[5] and sizes[5] < CombatImpactEffect.LOOKS[CombatImpactEffect.Kind.POISE_BREAK].spark, "Parry impact grows through a run, below the finisher %s" % str(sizes))
	capped.free()
	clear_feedback()
	player.emit_received_hit_feedback(Vector2(-100, 0), 1.0)
	expect_effect(CombatImpactEffect.Kind.PLAYER_HURT)
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
	check(left.facing < 0.0, "Right-side source mirrors force toward the left")
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
	var breaking := expect_effect(CombatImpactEffect.Kind.POISE_BREAK, dummy)
	check(breaking != null and breaking.pieces.size() == 4, "Poise break plays the full finisher: star, shards, ring and ground shockwave")
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
	expect_effect(CombatImpactEffect.Kind.PLAYER_HURT)
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
	check(parry.facing > 0.0, "Parry deflection points back toward a right-side attacker")
	check(is_equal_approx(feedback.punch_amount, 0.05), "Ordinary parry retains 5 percent camera punch")
	clear_feedback()
	bat.on_attack_parried(attack(bat, true), bat.global_position + Vector2(20, -32))
	var red := expect_effect(CombatImpactEffect.Kind.RED_PARRY, bat)
	check(red.facing < 0.0 and red.look().palette == &"red" and is_equal_approx(feedback.punch_amount, 0.11), "Red parry is red, mirrored, and retains heavy camera punch")
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
	check(placed.global_scale.is_equal_approx(Vector2.ONE) and is_zero_approx(placed.global_rotation), "Owner scale/rotation does not deform the impact")
	var weak_effect: WeakRef = weakref(placed)
	transformed.free()
	check(weak_effect.get_ref() == null, "Deleting receiver/specimen clears its feedback")
	clear_feedback()
	# Allow first-frame resource-loading stalls to settle before clock assertions.
	await process_frame
	await process_frame
	var timed := feedback.spawn_impact_effect(CombatImpactEffect.Kind.NORMAL_HIT, Vector2.ZERO, 0)
	# Fixed-fps runs: each frame is 1/60 s of game time times the time scale.
	var opened := timed.star.age
	Engine.time_scale = 0.05
	for i in 10: await process_frame
	var held := timed.star.age - opened
	check(is_instance_valid(timed) and held > 0.0 and held < 10.0 / 60.0 * 0.2, "Hit-stop slows the impact to scaled combat time (%.4f s in 10 frames)" % held)
	Engine.time_scale = 1.0
	paused = true
	var paused_age := timed.star.age
	for i in 10: await process_frame
	check(is_instance_valid(timed) and timed.star.age == paused_age, "Paused combat does not advance the impact")
	paused = false
	await create_timer(0.5, true, false, true).timeout
	check(not is_instance_valid(timed), "The impact frees itself once its pieces finish")
	clear_feedback()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == saved_existed and (not saved_existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Saved progress and inventory unchanged")
	current_scene = null
	room.free()
	# Let cancelled owner-bound tweens and queued native animations retire.
	await process_frame
	await process_frame
	print("SHARED COMBAT ART: ", checks, " checks, ", failures, " failures")
	assist.set_player_invincible(prior_invincibility)
	quit(1 if failures else 0)
