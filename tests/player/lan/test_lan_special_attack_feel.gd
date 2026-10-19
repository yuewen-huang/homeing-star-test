extends SceneTree
## Lan's special attack (I): shared skill-hit emphasis, timing curve, lunge, trimmed
## damage windows, input buffer / combo cancel / recovery cancel and boss skill poise.

class LocalProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func show_toast(_message: String) -> void: pass

class Receiver extends DamageReceiver2D:
	var hits := 0
	var poise_bar := false
	var immune := false
	func receive_hit(_damage: int, _source_position: Vector2) -> void:
		hits += 1
	func receive_skill_hit(_hit: RefCounted, source_position: Vector2) -> void:
		hits += 1
		if immune: return
		(get_node("/root/CombatFeedback") as CombatFeedbackService).emit_receiver_hit(self, global_position, source_position)
	func has_poise_bar() -> bool: return poise_bar
	var broken_poise := false
	func is_poise_broken() -> bool: return broken_poise

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func receiver_at(parent: Node, point: Vector2) -> Receiver:
	var receiver := Receiver.new()
	receiver.position = point
	var area := Area2D.new()
	area.name = "Hurtbox"
	area.collision_layer = 2
	area.collision_mask = 0
	area.add_to_group("hurtbox")
	var collision := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(2, 2)
	collision.shape = rect
	area.add_child(collision)
	receiver.add_child(area)
	parent.add_child(receiver)
	return receiver

func settle() -> void:
	for i in 4: await physics_frame

func run() -> void:
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var world := Node2D.new()
	root.add_child(world)
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	await process_frame

	# --- A1: emphasis only through settle_skill_hit, scaled by form, skipped for immune receivers.
	var receiver := receiver_at(world, Vector2(5000, 0))
	var plain := SkillHitContext.new(&"lan_special_attack", 18)
	var serial := feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, plain, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial + 1 and is_zero_approx(feedback.punch_remaining), "Skill without emphasis keeps the receiver's ordinary feedback")
	var skill := SkillHitContext.new(&"lan_special_attack", 18)
	skill.emphasis = SkillHitContext.Emphasis.SKILL
	serial = feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, skill, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial + 2, "Skill emphasis requests a longer hit-stop over the receiver's own")
	check(is_equal_approx(feedback.punch_amount, CombatFeedbackService.SKILL_PUNCH) and feedback.skill_layer_player.playing, "Skill emphasis punches the camera and layers the heavy slash sound")
	check(feedback._settling_skill == null, "Settlement context is cleared after the hit")
	feedback._reset_punch()
	var heavy := SkillHitContext.new(&"lan_special_attack", 60, false, false, false, true)
	heavy.emphasis = SkillHitContext.Emphasis.HEAVY_SKILL
	feedback.settle_skill_hit(receiver, heavy, Vector2.ZERO)
	check(is_equal_approx(feedback.punch_amount, CombatFeedbackService.TIER_PUNCH[CombatFeedbackService.Tier.HEAVY]), "Max form uses the HEAVY tier punch")
	feedback._reset_punch()
	receiver.immune = true
	serial = feedback.hit_stop_serial
	feedback.settle_skill_hit(receiver, skill, Vector2.ZERO)
	check(feedback.hit_stop_serial == serial and receiver.hits == 4, "Immune receivers get the hit call but no emphasis")
	receiver.queue_free()
	await create_timer(0.3, true, false, true).timeout
	Engine.time_scale = 1.0

	# --- A4: damage windows match the visible slash.
	for max_form in [false, true]:
		var config := LanAttackEffectCatalog.special_attack(max_form, 28.0, skill)
		var expected := range(8, 16) if not max_form else range(10, 14)
		check(config.hitboxes.keys() == Array(expected), "Damage window matches painted slash (max=%s)" % max_form)
		var spec: Dictionary = config.hitboxes[expected[0]][0]
		var forward_tip: float = (spec.center.x - config.frame_size.x * 0.5 - spec.length * 0.5) - config.sprite_offset.x
		var rear_tip: float = (spec.center.x - config.frame_size.x * 0.5 + spec.length * 0.5) - config.sprite_offset.x
		check(-forward_tip > rear_tip, "Most of the damage reach is in front of Lan (max=%s)" % max_form)

	# --- Player: timing curve, lunge, buffer and cancels.
	var player = (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate()
	player.world_min_x = -3000.0
	player.world_max_x = 3000.0
	world.add_child(player)
	await process_frame
	player.set_physics_process(false)
	check(player.special_attack_speed_scale(0) > player.special_attack_speed_scale(8) \
		and player.special_attack_speed_scale(12) > player.special_attack_speed_scale(8), "Windup and recovery are faster than the slash")
	var windup_seconds: float = 8.0 / (player.SPECIAL_ATTACK_FPS * player.SPECIAL_ATTACK_WINDUP_SPEED_SCALE)
	check(windup_seconds < 0.13, "Damage opens within 0.13 s (%.3f)" % windup_seconds)
	# Max form: slow wolf rise, snap pounce, held slash, hurried backward tail.
	player.special_attack_max_form = true
	var max_until_slash := 0.0
	for f in 10:
		max_until_slash += 1.0 / (player.SPECIAL_ATTACK_FPS * player.special_attack_speed_scale(f))
	check(max_until_slash > 0.2 and max_until_slash < 0.3, "Max slash lands after a readable 0.2-0.3 s build-up (%.3f)" % max_until_slash)
	check(player.special_attack_speed_scale(5) < player.special_attack_speed_scale(1) \
		and player.special_attack_speed_scale(9) > player.special_attack_speed_scale(5) \
		and player.special_attack_speed_scale(10) < player.special_attack_speed_scale(9) \
		and player.special_attack_speed_scale(20) > player.special_attack_speed_scale(12), "Max curve: rise slower than crouch, pounce snaps, slash holds, tail hurries")
	player.special_attack_max_form = false

	player.facing_direction = -1.0
	check(is_equal_approx(player.special_attack_lunge_reach(null), player.SPECIAL_ATTACK_LUNGE_DISTANCE), "Without a target the lunge uses its full distance")
	var near := receiver_at(world, player.global_position + Vector2(-40, 0))
	check(is_equal_approx(player.special_attack_lunge_reach(near), 40.0 - 1.0 - player.NORMAL_ATTACK_MIN_GAP), "Lunge stops short of a close target's hurtbox")
	near.queue_free()

	# Max form: the cat spirit is drawn behind Lan's body.
	var broken := receiver_at(world, player.global_position + Vector2(-150, 0))
	broken.poise_bar = true
	broken.broken_poise = true
	broken.add_to_group(&"damageable")
	player.perform_special_attack(-1.0, 0.0, player.find_throw_target())
	check(player.special_attack_max_form and player.timeline_attack_effect.get_index() < player.animated_sprite.get_index(), "Max cat spirit draws behind Lan")
	player.end_special_attack_early()
	# I remains a heavy attack even with a broken enemy nearby.
	Input.action_press(&"special_attack")
	player.start_special_attack(-1.0)
	check(player.special_attack_charging and not player.special_attack_max_form, "I charges instead of selecting PLUS on broken targets")
	player.update_special_attack_charge(0.45)
	check(player.special_attack_charging and not player.animated_sprite.is_playing(), "Held I keeps the windup pose and never hits")
	Input.action_release(&"special_attack")
	player.update_special_attack_charge(0.0)
	check(not player.special_attack_max_form and player.timeline_attack_effect.skill_hit_context.damage == 30, "Half charge releases a 30 damage heavy attack")
	player.end_special_attack_early()
	broken.free()
	for ratio in [0.0, 0.5, 1.0]:
		player.perform_special_attack(-1.0, ratio)
		check(is_equal_approx(player.special_attack_lunge_distance, lerpf(96.0, 300.0, ratio)), "Charge scales unobstructed travel: %s" % ratio)
		check(player.timeline_attack_effect.skill_hit_context.damage == roundi(lerpf(18.0, 42.0, ratio)), "Charge scales damage: %s" % ratio)
		check(player.timeline_attack_effect.skill_hit_context.poise_damage == 15 and not player.timeline_attack_effect.skill_hit_context.max_form, "Charge preserves the normal interrupt contract")
		player.end_special_attack_early()
	Input.action_press(&"special_attack")
	player.start_special_attack(-1.0)
	player.update_special_attack_charge(2.0)
	check(player.special_attack_charging and is_equal_approx(player.special_attack_charge_elapsed, 0.9), "Full charge caps and waits for release")
	player.cancel_uncommitted_attack_effects()
	check(not player.special_attack_charging, "An interrupted charge cannot release a phantom attack")
	Input.action_release(&"special_attack")
	player.perform_special_attack(-1.0)
	var effect = player.timeline_attack_effect
	check(effect.skill_hit_context.emphasis == SkillHitContext.Emphasis.HEAVY_SKILL and effect.skill_hit_context.poise_damage == player.SPECIAL_ATTACK_POISE_DAMAGE, "Heavy attack preserves skill poise")
	player.special_attack_lunge_elapsed = 0.0
	var travelled := 0.0
	var steps := 0
	while steps < 30:
		var lunge_velocity: float = player.special_attack_lunge_velocity(1.0 / 60.0)
		if is_nan(lunge_velocity): break
		travelled += lunge_velocity / 60.0
		steps += 1
	check(steps >= 6 and steps <= 7 and is_equal_approx(travelled, -player.special_attack_lunge_distance), "Eased lunge covers exactly its distance forward in 0.1 s, then stops (%d steps, %.2f px)" % [steps, travelled])

	# Recovery cancel opens only at the cancel frame.
	player.animated_sprite.frame = player.SPECIAL_ATTACK_CANCEL_FRAME - 1
	player.attack_input_buffer_remaining = 0.2
	check(not player.can_cancel_special_attack_recovery(false), "Attack cannot cancel before the recovery window")
	player.animated_sprite.frame = player.SPECIAL_ATTACK_CANCEL_FRAME
	check(player.can_cancel_special_attack_recovery(false), "Buffered attack cancels the late recovery")
	player.end_special_attack_early()
	check(player.attack_state == player.AttackState.NONE and player.active_attack_effects.is_empty(), "Early end clears the special state and its effect")
	player.attack_input_buffer_remaining = 0.0

	# Buffer + combo cancel.
	player.update_special_attack_buffer(0.0, true)
	check(player.has_buffered_special_attack(), "I press is buffered")
	player.update_special_attack_buffer(player.COMBAT_INPUT_BUFFER + 0.01, false)
	check(not player.has_buffered_special_attack(), "Buffer expires like other combat inputs")
	player.start_attack_1x(-1.0)
	check(not player.can_cancel_attack_into_special(), "Combo cannot cancel before its blade comes out")
	player.combat_timeline.advance(0.13)
	await process_frame
	check(player.can_cancel_attack_into_special(), "Combo hit cancels into the special once its blade is active")
	player.cancel_attack_into_special()
	check(player.attack_state == player.AttackState.NONE and not player.combat_timeline.is_playing(), "Combo cancel stops the combo timeline")
	player.queue_free()

	# --- A8: BossBase honours skill poise (shields removed on a regional core).
	var original := root.get_node("SaveProgress")
	root.remove_child(original)
	var progress := LocalProgress.new()
	progress.name = "SaveProgress"
	root.add_child(progress)
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	room.player.set_physics_process(false)
	room.select_boss(4)
	var core := room.adapter.boss as RegionalCoreBoss
	core.set_physics_process(false)
	room.shield_toggles[0].button_pressed = false
	room.shield_toggles[1].button_pressed = false
	var poise := core.combat_stats.poise
	var poised := SkillHitContext.new(&"lan_special_attack", 18)
	poised.poise_damage = 15
	core.receive_skill_hit(poised, Vector2(600, 555))
	check(core.combat_stats.poise == poise - 15, "Boss skill hit applies the context's poise damage")
	poise = core.combat_stats.poise
	core.receive_skill_hit(SkillHitContext.new(&"lan_special_attack", 18), Vector2(600, 555))
	check(core.combat_stats.poise == poise, "Skill hits without poise damage leave poise alone")
	room.shield_toggles[0].button_pressed = true
	poise = core.combat_stats.poise
	core.receive_skill_hit(poised, Vector2(600, 555))
	check(core.combat_stats.poise == poise, "A shield still blocks skill poise")
	var finished: Node = room
	current_scene = null
	finished.free()
	await process_frame
	progress.free()
	root.add_child(original)
	await create_timer(0.3, true, false, true).timeout
	Engine.time_scale = 1.0
	print("LAN SPECIAL CHECKS: ", checks, "; failures: ", failures)
	quit(1 if failures else 0)
