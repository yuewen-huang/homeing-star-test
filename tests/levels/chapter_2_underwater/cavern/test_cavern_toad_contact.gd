extends "../../../support/harness.gd"

const SCENE := preload("res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn")
const TOAD := preload("res://scripts/levels/chapter_2_underwater/cavern/cavern_bronze_toad.gd")
const NEAR_FACE := TOAD.ORIGIN.x + TOAD.BODY_SOLID.position.x - LanPlayer.BODY_HALF_WIDTH

var level: SunkenCavern
var toad: TOAD
var lan: LanPlayer


func run() -> void:
	seed(25)
	use_memory_progress().try_complete_fact(&"sunken_cavern_bell_awake")
	level = SCENE.instantiate() as SunkenCavern
	root.add_child(level)
	current_scene = level
	toad = level.bronze_toad
	lan = level.player
	# Keep the actual boss body, hurtbox and room. Isolate contact from weapon hits.
	toad.set_physics_process(false)
	await step(3)
	await check_rebound()
	await check_dodge_finisher()
	await check_normal_finisher()
	await check_ground_dash()
	expect_save_untouched()
	level.queue_free()
	await wait_frames(4)
	finish("A25 TOAD CONTACT")


func check_rebound() -> void:
	await approach(6090.0)
	Input.action_press(&"ui_right")
	await step(25)
	await jump(27)
	await jump(27)
	var hp := toad.combat_stats.health
	await tap(KEY_S)
	check(toad.combat_stats.health == hp - CombatTuning.LAN_ATTACK_1X_DAMAGE \
		and lan.velocity.y < -300.0 and lan.can_start_double_jump(),
		"A25 downslash with room above deals one hit and keeps the full bounce")
	await step(16)
	Input.action_press(&"jump")
	for i in 24:
		await step(1)
		if lan.is_on_ceiling(): break
	Input.action_release(&"jump")
	check(lan.is_on_ceiling(), "Bounce and jump reach the actual A25 rock overhang")
	hp = toad.combat_stats.health
	key(KEY_S, true)
	for i in 12:
		await step(1)
		if toad.combat_stats.health < hp: break
	key(KEY_S, false)
	check(toad.combat_stats.health == hp - CombatTuning.LAN_ATTACK_1X_DAMAGE \
		and lan.velocity.y > -100.0, "Downslash under the low roof hits once with a short rebound")
	var cleared := true
	for i in 100:
		await step(1)
		cleared = cleared and not lan.is_on_ceiling() and lan.position.x <= NEAR_FACE + 0.1
	check(cleared and lan.air_state == LanPlayer.AirState.GROUNDED \
		and toad.combat_stats.health == hp - CombatTuning.LAN_ATTACK_1X_DAMAGE,
		"Low rebound stays out of the roof and boss, then lands without another hit")
	Input.action_release(&"ui_right")
	await retreat()


func check_dodge_finisher() -> void:
	await approach(6050.0)
	await tap(KEY_L)
	for i in 30:
		if lan.back_dodge_attack_cancel_open: break
		await step(1)
	Input.action_press(&"ui_right")
	await tap(KEY_J)
	await tap(KEY_J)
	await wait_for_attack(LanPlayer.AttackState.DODGE_ATTACK_2X)
	await tap(KEY_J)
	await wait_for_attack(LanPlayer.AttackState.DODGE_ATTACK_3X)
	check(lan.attack_state == LanPlayer.AttackState.DODGE_ATTACK_3X,
		"Real L and J input reaches the dodge finisher beside the boss")
	Input.action_release(&"ui_right")
	var hp := toad.combat_stats.health
	var clear := true
	var landed := false
	for i in 110:
		await step(1)
		clear = clear and lan.position.x <= NEAR_FACE + 0.1 and not lan.is_on_ceiling()
		landed = landed or (lan.dodge_attack_3_landed and absf(lan.position.y - TOAD.ORIGIN.y) < 5.0)
	check(clear and landed, "Finisher drops and lands on the open side of the toad")
	check(toad.combat_stats.health == hp - CombatTuning.LAN_DODGE_ATTACK_3X_DAMAGE,
		"Dodge finisher settles its damage exactly once")
	await retreat()


func check_normal_finisher() -> void:
	await approach(6132.0)
	for i in 20:
		await tap(KEY_J)
		if lan.attack_state == LanPlayer.AttackState.ATTACK_3X: break
	check(lan.attack_state == LanPlayer.AttackState.ATTACK_3X,
		"Real J chain reaches the normal finisher at the boss's front")
	var hp := toad.combat_stats.health
	await step(120)
	check(toad.combat_stats.health == hp - CombatTuning.LAN_ATTACK_3X_DAMAGE,
		"Normal finisher hits once, then deals no damage after input stops")
	await retreat()


func check_ground_dash() -> void:
	await approach(6020.0)
	Input.action_press(&"instant_dash")
	await step(4)
	Input.action_release(&"instant_dash")
	await step(35)
	check(lan.position.x > 6100.0 and lan.position.x <= NEAR_FACE + 0.1 \
		and absf(lan.position.y - TOAD.ORIGIN.y) < 5.0,
		"Ground U stops on the near side without wedging between boss and floor")
	await retreat()


func approach(x: float) -> void:
	toad.reset_attempt()
	lan.reset_after_map_fall(Vector2(x, TOAD.ORIGIN.y))
	lan.combat_stats.restore_stamina(lan.combat_stats.max_stamina)
	lan.facing_direction = 1.0
	level.snap_camera()
	await step(6)
	toad._engage()


func retreat() -> void:
	var start_x := lan.position.x
	Input.action_press(&"ui_left")
	await step(25)
	Input.action_release(&"ui_left")
	check(lan.position.x < start_x - 40.0 and lan.air_state == LanPlayer.AirState.GROUNDED \
		and lan.attack_state == LanPlayer.AttackState.NONE and not lan.combat_timeline.is_playing(),
		"Lan regains ordinary movement with no surviving attack timeline")


func wait_for_attack(state: int) -> void:
	for i in 65:
		if lan.attack_state == state: return
		await step(1)


func jump(frames: int) -> void:
	Input.action_press(&"jump")
	await step(3)
	Input.action_release(&"jump")
	await step(frames - 3)


func tap(code: Key) -> void:
	key(code, true)
	await step(3)
	key(code, false)
	await step(5)


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func step(frames: int) -> void:
	for i in frames: await physics_frame
