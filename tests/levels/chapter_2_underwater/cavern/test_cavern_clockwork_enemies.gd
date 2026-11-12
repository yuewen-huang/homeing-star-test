extends "../../../support/harness.gd"

const ROOM := preload("../../../../tools/level_design/clockwork_enemy_room.gd")
const OX := 0
const BIRD := 1
const SNAKE := 2

var room
var player: LanPlayer
var enemy: ClockworkEnemy
var contacts: Array[CombatHitResult.Type] = []


func run() -> void:
	use_memory_progress()
	await _check_ox()
	await _check_bird()
	await _check_bird_red_cut()
	await _check_snake()
	await _check_health()
	await _dispose()
	expect_save_untouched()
	finish("CAVERN CLOCKWORK ENEMIES")


func _check_ox() -> void:
	await _open(OX)
	var start := enemy.global_position
	check(await _phase(ClockworkEnemy.Phase.ACTIVE), "Ox gives a windup then charges")
	check(await _phase(ClockworkEnemy.Phase.RECOVERY), "Ox charge has a committed endpoint")
	check(enemy.global_position.y == start.y and enemy.global_position.x < start.x - 215.0,
		"Ox keeps its feet on the authored level")
	check(player.combat_stats.health == player.combat_stats.max_health - 13 and contacts.size() == 1,
		"Standing in the charge receives exactly one ordinary hit")
	await _open(OX)
	check(await _phase(ClockworkEnemy.Phase.ACTIVE), "Ox can be baited into a second trial")
	Input.action_press(&"jump")
	await _step(14)
	Input.action_release(&"jump")
	check(await _phase(ClockworkEnemy.Phase.RECOVERY), "Ox completes the charge while Lan jumps")
	check(player.combat_stats.health == player.combat_stats.max_health and contacts.is_empty(),
		"Ordinary jump clears the ground charge")
	await _open(OX)
	check(await _phase(ClockworkEnemy.Phase.ACTIVE), "Ox charge reaches the guard trial")
	for i in 30:
		if absf(enemy.global_position.x - player.global_position.x) < 139.0:
			break
		await physics_frame
	Input.action_press(&"parry")
	await _step(2)
	Input.action_release(&"parry")
	await _phase(ClockworkEnemy.Phase.RECOVERY)
	check(contacts == [CombatHitResult.Type.PARRY_SUCCESS] and player.combat_stats.health == player.combat_stats.max_health,
		"K uses Lan's real guard and interrupts the ox")
	await _open(OX, Vector2(188.0, 584.0), Vector2(322.0, 584.0))
	await _phase(ClockworkEnemy.Phase.ACTIVE)
	await _phase(ClockworkEnemy.Phase.RECOVERY)
	check(enemy.position.x >= 200.0 and is_equal_approx(enemy.position.y, 584.0),
		"Ox checks ground ahead and stops before an unguarded drop")


func _check_bird() -> void:
	await _open(BIRD, Vector2(228.0, 584.0))
	var bird := enemy as ClockworkBird
	var wing_frames := {}
	var top := bird.position.y
	var bottom := top
	for i in 32:
		wing_frames[bird.sprite.frame] = true
		top = minf(top, bird.position.y)
		bottom = maxf(bottom, bird.position.y)
		await physics_frame
	check(bird.phase == ClockworkEnemy.Phase.IDLE and wing_frames.size() == 4 and bottom - top > 7.0,
		"Bird flaps through four poses and gains height on the downstroke")

	await _open(BIRD)
	bird = enemy as ClockworkBird
	var diving := await _phase(ClockworkEnemy.Phase.ACTIVE)
	check(diving, "Bird starts with the dive")
	if not diving:
		return
	check(String(bird.attack_hitbox.attack.attack_id).contains("_dive_"), "Dive uses its own hit")
	var dive := await _attack_positions()
	check(dive.size() >= 42, "Dive completes the committed arc")
	if dive.size() >= 42:
		var entry := dive[24] - dive[12]
		var exit := dive[-1] - dive[-8]
		check(entry.x < -35.0 and entry.y > 24.0 and exit.y < -5.0,
			"Dive curves downward, then banks back up")
		var early_speed := (dive[8] - dive[1]).length() / 7.0
		var late_speed := exit.length() / 7.0
		var peak := _peak_speed(dive) / 60.0
		check(peak > early_speed * 2.0 and peak > late_speed * 2.0,
			"Dive accelerates into the pass and visibly brakes")
	check(contacts.size() == 1, "Dive can reach a grounded player")
	Input.action_press(&"ui_right")
	for i in 90:
		if player.global_position.x >= 415.0:
			break
		await physics_frame
	Input.action_release(&"ui_right")
	var spins := await _phase(ClockworkEnemy.Phase.ACTIVE, 360)
	check(spins, "Bird returns and winds up again (phase %s, bird %s, Lan %s)" %
		[ClockworkEnemy.Phase.keys()[bird.phase], bird.global_position, player.global_position])
	if not spins:
		return
	var cut_ids: Array[StringName] = []
	var cut_order: Array[int] = []
	var red_cuts: Array[int] = []
	bird.spin_cut_released.connect(func(index: int, attack: CombatAttackData) -> void:
		cut_ids.append(attack.attack_id)
		cut_order.append(index)
		if attack.danger_type == CombatAttackData.DangerType.COUNTERABLE_DANGER:
			red_cuts.append(index))
	var spin: Array[Vector2] = []
	var yaw_frames := {}
	var upright := true
	for i in 120:
		if bird.phase != ClockworkEnemy.Phase.ACTIVE:
			break
		spin.append(bird.global_position)
		yaw_frames[bird.sprite.frame] = true
		upright = upright and is_zero_approx(bird.sprite.rotation)
		await physics_frame
	var lowest := -INF
	for point in spin:
		lowest = maxf(lowest, point.y)
	check(upright and yaw_frames.has(2) and yaw_frames.has(3) and lowest < 548.0,
		"Top turns around its upright axis in the air and clears the floor")
	check(_peak_speed(spin) >= 1150.0 and _peak_speed(spin) > _peak_speed(dive) * 1.5,
		"Spin makes a much faster pass than the dive")
	var unique := {}
	for id in cut_ids:
		unique[id] = true
	check(cut_order == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and unique.size() == 10,
		"Spin resolves exactly ten cuts with distinct combat IDs")
	check(red_cuts == [10], "Only cut ten uses the red counterable danger type")
	check(contacts.size() > 2, "The moving flurry lands multiple independent contacts")


func _check_bird_red_cut() -> void:
	await _open(BIRD, Vector2(228.0, 584.0))
	var bird := enemy as ClockworkBird
	bird._spin_next = true
	player.reset_after_map_fall(Vector2(423.0, 584.0))
	if not await _phase(ClockworkEnemy.Phase.ACTIVE):
		check(false, "Bird starts the isolated spin finisher trial")
		return
	# The wider finisher reaches this test position just beyond the normal rings.
	player.reset_after_map_fall(Vector2(252.0, 584.0))
	for i in 70:
		if bird.phase_length - bird.time_left >= 0.32:
			break
		await physics_frame
	check(contacts.is_empty() and bird._danger.visible, "The red cue leads the isolated finisher")
	Input.action_press(&"parry")
	await _step(2)
	Input.action_release(&"parry")
	await _phase(ClockworkEnemy.Phase.RECOVERY)
	check(contacts == [CombatHitResult.Type.PARRY_SUCCESS] and
		player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS,
		"Real K on cut ten triggers Lan's red counter")


func _attack_positions() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for i in 150:
		if enemy.phase != ClockworkEnemy.Phase.ACTIVE:
			break
		points.append(enemy.global_position)
		await physics_frame
	return points


func _peak_speed(points: Array[Vector2]) -> float:
	var peak := 0.0
	for i in range(1, points.size()):
		peak = maxf(peak, points[i].distance_to(points[i - 1]))
	return peak * 60.0

func _check_snake() -> void:
	await _open(SNAKE)
	var anchor := enemy.global_position
	var resting_head := enemy.hurtbox.global_position
	var bar_offset := enemy.health_bar.global_position - resting_head
	check(await _phase(ClockworkEnemy.Phase.WINDUP), "Snake coils before the bite")
	check(await _phase(ClockworkEnemy.Phase.ACTIVE), "Snake commits the bite")
	await _step(8)
	check(enemy.hurtbox.global_position.distance_to(resting_head) > 30.0,
		"Snake's moving head owns the hurtbox")
	check((enemy.health_bar.global_position - enemy.hurtbox.global_position).is_equal_approx(bar_offset),
		"Snake's floating health bar follows the biting head")
	check(enemy.global_position == anchor, "The tail stays on the wall during the bite")
	await _phase(ClockworkEnemy.Phase.RECOVERY)
	check(contacts.size() == 1 and player.combat_stats.health == player.combat_stats.max_health - 12,
		"Bite hits once in reach")
	enemy.receive_hit(enemy.health, player.global_position)
	await _step(45)
	check(not is_instance_valid(enemy), "Defeating the snake clears the entire mount")


func _check_health() -> void:
	await _open(OX, Vector2(725.0, 584.0))
	# Hold the ox still so three isolated J presses go through Lan's real hitboxes.
	enemy.set_physics_process(false)
	check(enemy.health_bar.value == 28 and enemy.health_bar.max_value == 28,
		"Ox starts with a full miniature health bar")
	for expected: int in [18, 8, 0]:
		await _normal_cut()
		check(enemy.health == expected and enemy.health_bar.value == expected,
			"Real J and the health bar agree at %d HP" % expected)
		if expected > 0:
			for i in 100:
				if player.attack_state == LanPlayer.AttackState.NONE:
					break
				await physics_frame
	check(not enemy.health_bar.visible, "The ox health bar disappears on defeat")

	var air_cut := LanAttackEffectCatalog.jump_attack_1x(LanPlayer.JUMP_ATTACK_1X_FPS).attack_hit_context
	var ground_cut := LanAttackEffectCatalog.attack_1x().attack_hit_context
	for trial in [[BIRD, 18, 6, air_cut], [SNAKE, 20, 10, ground_cut]]:
		await _open(int(trial[0]))
		check(enemy.health == trial[1] and enemy.health_bar.value == trial[1],
			"Enemy bar shows its own starting health")
		enemy.receive_attack_hit(trial[3], player.global_position)
		check(enemy.health == trial[2] and enemy.health_bar.value == trial[2],
			"The first attack uses the move's health damage")
		enemy.receive_attack_hit(trial[3], player.global_position)
		check(enemy.health == 0 and not enemy.health_bar.visible, "The second hit defeats the light enemy")


func _normal_cut() -> void:
	var before := enemy.health
	var press := InputEventKey.new()
	press.physical_keycode = KEY_J
	press.pressed = true
	Input.parse_input_event(press)
	await _step(2)
	var release := InputEventKey.new()
	release.physical_keycode = KEY_J
	Input.parse_input_event(release)
	for i in 90:
		if enemy.health != before:
			return
		await physics_frame


func _phase(wanted: ClockworkEnemy.Phase, limit := 210) -> bool:
	for i in limit:
		if enemy.phase == wanted:
			return true
		await physics_frame
	return false


func _step(count: int) -> void:
	for i in count:
		await physics_frame


func _open(index: int, player_at := Vector2.ZERO, enemy_at := Vector2.ZERO) -> void:
	await _dispose()
	contacts.clear()
	room = ROOM.new()
	root.add_child(room)
	current_scene = room
	room.build(index)
	player = room.player
	enemy = room.enemy
	if player_at != Vector2.ZERO:
		player.reset_after_map_fall(player_at)
	if enemy_at != Vector2.ZERO:
		enemy.global_position = enemy_at
		enemy.home = enemy_at
	enemy.attack_hitbox.hit_resolved.connect(func(_target: Node, result: CombatHitResult.Type) -> void:
		contacts.append(result))
	await _step(3)


func _dispose() -> void:
	if is_instance_valid(room):
		room.queue_free()
	await _step(4)
