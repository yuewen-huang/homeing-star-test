extends "../../../tools/level_design/preview_twin_fish_arena.gd"

const Duel := preload("res://scripts/bosses/twin_fish/twin_fish_lightning_duel.gd")

class TeachingRecorder extends OpeningRecorder:
	func _process(delta: float) -> void:
		var encounter := (get_parent() as SunkenCavern).twin_fish_encounter
		if not encounter.battle_ready: return
		# Keep the visible contact frames even when shared hit-stop slows gameplay.
		age += delta / maxf(0.01, Engine.time_scale)
		if age + 0.00001 < next_sample: return
		next_sample = maxf(next_sample + 1.0 / 24.0, age)
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var file := "%04d.jpg" % frames.size()
		var frame := get_viewport().get_texture().get_image()
		frame.resize(960, 540, Image.INTERPOLATE_BILINEAR)
		frame.save_jpg(folder.path_join(file), 0.93)
		frames.append({"file": file, "time": age})

func make_recorder() -> OpeningRecorder: return TeachingRecorder.new()

func verifying() -> bool: return true

func sword(down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_J
	key.physical_keycode = KEY_J
	key.pressed = down
	Input.parse_input_event(key)
	Input.flush_buffered_events()

func walk(offset: float) -> void:
	Input.action_release(&"ui_left")
	Input.action_release(&"ui_right")
	if absf(offset) > 8.0: Input.action_press(&"ui_right" if offset > 0 else &"ui_left")

func verify_opening() -> void:
	var encounter := level.twin_fish_encounter
	walk(100)
	for i in 150:
		await physics_frame
		if encounter.engaged: break
	walk(0)
	var seeded := false
	for i in 700:
		await physics_frame
		if not seeded and is_instance_valid(encounter.fish):
			encounter.fish._swim_random.seed = 41019
			seeded = true
		if encounter.battle_ready: break
	check(encounter.battle_ready, "A27 hands control to the live lightning encounter")
	if not encounter.battle_ready:
		finish("TWIN FISH LIGHTNING")
		return
	var fish := encounter.fish
	var duel := fish.lightning
	var last := -1
	var detached := false
	var charged := false
	var locked := false
	var straight := true
	var route := Vector2.ZERO
	var warned_from := Vector2.ZERO
	var warned_to := Vector2.ZERO
	var tracks_target := true
	var cue_direction := Vector2.ZERO
	var cue_turned := false
	var normal_attacks := true
	var returned_by_turn := false
	var flashed := false
	var stopped := false
	var flinched := false
	var impact_seen := false
	var clash_stop := false
	var feedback := root.get_node("CombatFeedback") as CombatFeedbackService
	var before_stop := feedback.hit_stop_serial
	var start := Vector2.ZERO
	var chased := false
	var entered_open := false
	var punish_hit := false
	var hp := fish.combat_stats.health
	var individual_hit := false
	var missed := false
	var protected_after := false
	var observed := {}
	var recorder: OpeningRecorder
	for child in level.get_children():
		if child is OpeningRecorder: recorder = child
	for i in 3600:
		await physics_frame
		if encounter.fish != fish: break
		var target := duel._target()
		if last != duel.beat:
			print("BEAT ", duel.LABELS[duel.beat], " t=", snappedf(duel.clock, 0.01), " nose=", fish.white_sprite.head_in_boss().round(), " ball=", duel.orb.position.round(), " flying=", duel.orb.flying, " Lan=", target.round())
			if recorder: print("CAPTURE ", duel.LABELS[duel.beat], " ", recorder.frames.size())
			last = duel.beat
			observed[duel.beat] = true
			if duel.beat == Duel.Beat.AIM:
				cue_direction = duel.aim_direction
			if duel.beat == Duel.Beat.DASH:
				start = fish.white_swimmer.position
				route = duel.locked_direction
				warned_from = duel.lane_start
				warned_to = duel.lane_end
				locked = true
			if duel.beat == Duel.Beat.OPEN:
				entered_open = not fish.invulnerable and fish.attack_hitbox.attack == null and not duel.orb.flying
				clash_stop = feedback.hit_stop_serial > before_stop
				before_stop = feedback.hit_stop_serial
				await capture("clash")
			if duel.beat == Duel.Beat.RECOVER:
				if not duel.clashes or duel.cast_number > duel.clashes: missed = true
				protected_after = fish.invulnerable
		if duel.beat in [Duel.Beat.AIM, Duel.Beat.LOCK]:
			tracks_target = tracks_target and absf(duel.aim_direction.angle_to(duel.lane_start.direction_to(target))) < 0.05
			cue_turned = cue_turned or absf(cue_direction.angle_to(duel.aim_direction)) > 0.10
		if duel.beat == Duel.Beat.DASH:
			straight = straight and warned_from == duel.lane_start and warned_to == duel.lane_end
		if duel.beat == Duel.Beat.RECOVER and not duel.clashes and fish.white_swimmer.turning:
			returned_by_turn = returned_by_turn or fish.white_swimmer.action_name == "turn_up"
		if duel.orb.hitbox.attack != null:
			normal_attacks = normal_attacks and duel.orb.hitbox.attack.danger_type == CombatAttackData.DangerType.NORMAL
		if fish.attack_hitbox.attack != null:
			normal_attacks = normal_attacks and fish.attack_hitbox.attack.danger_type == CombatAttackData.DangerType.NORMAL
		if duel.beat == Duel.Beat.CAST and not duel._released and duel.yin.visible:
			var rim := duel.Field.RING_RADIUS * smoothstep(0.20, 1.42, duel.age)
			if rim >= duel.Field.RING_RADIUS:
				charged = charged or absf(duel.yin.position.distance_to(fish.black_sprite.joint_in_boss(4)) - rim) < 4.0
		if duel.orb.flying and duel.orb.age < 0.02 and not detached:
			detached = absf(duel.orb.position.distance_to(fish.black_sprite.joint_in_boss(4)) - duel.Field.RING_RADIUS) < 6.0
		if duel.orb.flying and duel.orb.age > 1.6 and duel.orb.velocity.dot(duel.orb.position.direction_to(target)) > 60:
			chased = true
		if duel.beat == Duel.Beat.DASH:
			straight = straight and absf((fish.white_swimmer.position - start).cross(route)) < 1.0 and route.is_equal_approx(duel.locked_direction)
		if duel.beat == Duel.Beat.OPEN:
			var to_fish := fish.white_sprite.joint_in_boss(1).x - target.x
			walk(to_fish)
			if absf(to_fish) <= 155.0 and i % 18 == 0:
				sword(true)
			else: sword(false)
			punish_hit = punish_hit or fish.combat_stats.health < hp
			if fish.zhao.combat_stats.health < fish.zhao.combat_stats.max_health and fish.xuan.combat_stats.health == fish.xuan.combat_stats.max_health:
				individual_hit = fish.zhao.hud.health_bar.value == fish.zhao.combat_stats.health and fish.xuan.hud.health_bar.value == fish.xuan.combat_stats.health
			if punish_hit:
				stopped = stopped or feedback.hit_stop_serial > before_stop
				for sprite in [fish.black_sprite, fish.white_sprite]:
					flashed = flashed or float(sprite.material.get_shader_parameter(&"flash_amount")) > 0.5
				flinched = flinched or fish.white_swimmer.action_name == "fin_sweep" or fish.black_swimmer.action_name == "fin_sweep"
				impact_seen = impact_seen or not get_nodes_in_group(CombatImpactEffect.GROUP).is_empty()
		elif duel.cast_number == 1:
			# Keep moving through the tracking cue and out of the released charge.
			walk(220.0 if duel.beat in [Duel.Beat.AIM, Duel.Beat.LOCK, Duel.Beat.DASH] else 0.0)
		elif (duel.beat == Duel.Beat.AIM and duel.age >= 0.24) or duel.beat == Duel.Beat.LOCK:
			# Read the stripe, then run past the landing point to draw the ball across.
			var side := signf(duel.lane_end.x - duel.orb.position.x)
			if duel.orb.position.distance_to(target) > 180:
				walk(duel.lane_end.x + 35.0 * side - target.x)
			else: walk(duel.lane_end.x + 135.0 * side - target.x)
		else: walk(0.0)
		if entered_open and missed and protected_after and duel.beat == Duel.Beat.RECOVER: break
	walk(0)
	sword(false)
	if recorder: recorder.set_process(false)
	check(charged and detached, "Yin charge and release originate at the painted tail fin")
	check(chased, "The released orb bends toward the real player")
	check(locked and straight and observed.has(Duel.Beat.DASH), "The charge commits to one straight lane")
	check(tracks_target and cue_turned, "The warning follows moving Lan throughout the windup")
	check(normal_attacks, "Orb and dash both settle as normal attacks")
	check(returned_by_turn, "After a miss Zhao immediately swims the painted upward turn")
	check(missed, "An unintercepted charge recovers and starts another cast")
	check(entered_open, "A player-guided orb intercepts the charge and opens the punish window")
	check(punish_hit, "A real player attack reaches a vulnerable fish")
	check(individual_hit, "A sword on Zhao changes only Zhao's health and its matching HUD")
	check(clash_stop and stopped and flashed and impact_seen and flinched, "Clash and sword hits stop on contact; real sword contact flashes the fish, spawns the impact and plays its flinch")
	check(protected_after, "Recovery closes the punish window")
	encounter.reset_attempt()
	await wait_frames(3)
	check(not is_instance_valid(duel) and not encounter.battle_ready, "Retry retires the old duel and every active projectile")
	await verify_parry_and_exit(encounter)
	level.queue_free()
	await wait_frames(3)
	expect_save_untouched()
	finish("TWIN FISH LIGHTNING")

func verify_parry_and_exit(encounter: CavernTwinFishEncounter) -> void:
	for i in 500:
		await physics_frame
		if encounter.battle_ready: break
	var boss := encounter.fish
	var duel := boss.lightning
	# Isolate the new return during the stationary coil. Real input removes the
	# hostile hitbox; the player projectile must leave both fish protected.
	for i in 1000:
		await physics_frame
		if duel.beat == Duel.Beat.LOCK: break
	var toward := Vector2(level.player.facing_direction, 0)
	duel.orb.release(duel._target() + toward * 49.0, -toward * 115.0, 1000)
	Input.action_press(&"parry")
	var returned := false
	var heading := Vector2.ZERO
	var separate := true
	var hp := boss.zhao.combat_stats.health
	for i in 120:
		await physics_frame
		if i == 4: Input.action_release(&"parry")
		if duel.counters.returned:
			if not returned: heading = duel.counters.return_velocity
			returned = true
			separate = separate and not duel.orb.flying and duel.orb.hitbox.attack == null and heading.is_equal_approx(duel.counters.return_velocity)
		if boss.zhao.combat_stats.health < hp: break
	Input.action_release(&"parry")
	check(returned and separate and boss.defense_credit == 1, "Parry consumes the enemy orb once and launches a separate straight return")
	check(boss.zhao.combat_stats.health == hp - duel.counters.HIT_DAMAGE and boss.xuan.combat_stats.health == boss.xuan.combat_stats.max_health and duel.clashes == 0 and boss.invulnerable, "Only Zhao takes return damage; neither fish enters shared vulnerability")
	# The following independent-health/exit fixture needs the normal punish window.
	for i in 180:
		await physics_frame
		if duel.beat == Duel.Beat.DASH: break
	duel.orb.release(duel.lane_start + duel.locked_direction * 85.0, Vector2.ZERO, 1001)
	for i in 60:
		await physics_frame
		if duel.beat == Duel.Beat.OPEN: break
	var zhao_first := "--zhao-first" in OS.get_cmdline_user_args()
	var first := boss.zhao if zhao_first else boss.xuan
	var survivor := boss.xuan if zhao_first else boss.zhao
	var other_hp := survivor.combat_stats.health
	first.receive_attack_hit(AttackHitContext.new(&"first_final_hit", 900, 0, 1), level.player.global_position)
	await physics_frame
	check(first.combat_stats.health == 0 and survivor.combat_stats.health == other_hp and encounter.engaged and not encounter.cleared, "First fish falls independently while the other stays in battle")
	var solo_attack := false
	for i in 1000:
		await physics_frame
		if (zhao_first and duel.orb.flying) or (not zhao_first and duel.beat == Duel.Beat.DASH):
			solo_attack = true
			break
	check(solo_attack, "The surviving fish continues to use its own attack")
	survivor.receive_attack_hit(AttackHitContext.new(&"survivor_final_hit", 900, 0, 1), level.player.global_position)
	await wait_frames(4)
	check(encounter.cleared and not encounter.engaged and encounter.seals.is_empty() and not level.player.input_frozen, "Depleting the current encounter releases the arena and player")
