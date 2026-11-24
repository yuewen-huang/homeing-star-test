extends "../../support/harness.gd"
## Oxygen and drowning on the current Sunken Cavern player.
const SCENE_PATH := "res://scenes/levels/chapter_2_underwater/cavern/sunken_cavern.tscn"
const PIECE := preload("res://scenes/levels/common/terrain_piece.tscn")
const ACTIONS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"instant_dash"]
const TEST_POOL := Rect2(100, -8000, 2800, 1050)
const OPEN_WATER := TEST_POOL.position + Vector2(1000, 400)
const NEAR_SURFACE := TEST_POOL.position + Vector2(1000, 120)
const POOL_FLOOR := TEST_POOL.position + Vector2(1000, 920)

var level: Node2D
var player: LanPlayer
var oxygen: UnderwaterOxygen
var stats: CombatantStats


func run() -> void:
	use_memory_progress()
	await test_setup()
	await test_drain_while_swimming()
	await test_hold_on_underwater_floor()
	await test_surface_refill()
	await test_bank_refill()
	await test_skills_blocked_while_swimming()
	await test_empty_damage()
	await test_drowning_respawn()
	level.queue_free()
	await process_frame
	await test_swimming_outside_level()
	expect_save_untouched()
	finish("CHAPTER 2 UNDERWATER OXYGEN")


func release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


func step(frames: int) -> void:
	for i in frames:
		await physics_frame


func place(at: Vector2, mana: float) -> void:
	release_all()
	await step(2)
	player.reset_after_map_fall(at)
	player.air_state = LanPlayer.AirState.FALLING
	oxygen.remaining = mana
	await step(3)


func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func test_setup() -> void:
	level = (load(SCENE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	# Measure oxygen in still water, including when the chapter tide would normally surge.
	level.tide.set_combat_suspended(true)
	await step(40)
	player = level.player
	oxygen = level.oxygen
	# A deep test pool above the quay gives us room to measure oxygen ticks.
	var pool := UnderwaterVolume.new()
	pool.position = TEST_POOL.position
	pool.size = TEST_POOL.size
	level.add_child(pool)
	pool.register_to(player)
	var floor_piece := PIECE.instantiate() as TerrainPiece
	floor_piece.kind = "wall"
	floor_piece.position = TEST_POOL.position + Vector2(0, 1000)
	floor_piece.size = Vector2(TEST_POOL.size.x, 64)
	level.add_child(floor_piece)
	floor_piece.register_to(player)
	stats = player.combat_stats
	check(oxygen != null and oxygen.player == player, "Cavern tracks the player-owned traversal gauge")
	check(near(oxygen.remaining, oxygen.CAPACITY, 0.01), "Oxygen (blue bar) starts full: %.1f/%.1f" % [oxygen.remaining, oxygen.CAPACITY])
	check(UnderwaterOxygen.FULL_BAR_SECONDS == 20.0 and UnderwaterOxygen.REFILL_SECONDS == 0.5, "Tunable constants (20 s / 0.5 s)")


func test_drain_while_swimming() -> void:
	await place(OPEN_WATER, oxygen.CAPACITY)
	check(player.air_state == LanPlayer.AirState.SWIMMING and oxygen.mode == UnderwaterOxygen.Mode.SWIMMING, "Swimming in open water")
	var before := oxygen.remaining
	await step(180)
	var expected := oxygen.CAPACITY * 3.0 / UnderwaterOxygen.FULL_BAR_SECONDS
	check(near(before - oxygen.remaining, expected, 1.5), "3 s swimming drains ≈%.0f (%.1f)" % [expected, before - oxygen.remaining])
	check(stats.health == stats.max_health, "No damage while oxygen remains")


func test_hold_on_underwater_floor() -> void:
	await place(POOL_FLOOR, 50.0)
	var landed := false
	for i in 300:
		await physics_frame
		if player.is_on_floor() and player.air_state != LanPlayer.AirState.SWIMMING:
			landed = true
			break
	check(landed and player.is_in_deep_water(), "Standing on a floor inside the water (%s, deep %s)" % [player.position, player.is_in_deep_water()])
	var before := oxygen.remaining
	await step(120)
	check(oxygen.mode == UnderwaterOxygen.Mode.HOLDING, "Mode HOLDING on the underwater floor: %s" % UnderwaterOxygen.Mode.keys()[oxygen.mode])
	check(near(oxygen.remaining, before, 0.01), "No drain (and no refill) on the floor: %.1f → %.1f" % [before, oxygen.remaining])


func test_surface_refill() -> void:
	await place(NEAR_SURFACE, 10.0)
	Input.action_press(&"ui_up")
	var floated := false
	for i in 240:
		await physics_frame
		if player.swim.is_floating():
			floated = true
			break
	release_all()
	check(floated, "Swims up and floats at the surface")
	var low := oxygen.remaining
	await step(6)
	check(oxygen.remaining > low and oxygen.remaining < oxygen.CAPACITY, "Refill is gradual, not a pop (%.1f after 0.1 s)" % oxygen.remaining)
	await step(30)
	check(near(oxygen.remaining, oxygen.CAPACITY, 0.01), "Full again within ~0.6 s at the surface: %.1f" % oxygen.remaining)
	await step(120)
	check(near(oxygen.remaining, oxygen.CAPACITY, 0.01) and player.swim.is_floating(), "No drain while floating at the surface")


func test_bank_refill() -> void:
	await place(level.start, 10.0)
	await step(60)
	check(not player.is_in_deep_water() and player.air_state == LanPlayer.AirState.GROUNDED, "Standing on the dry quay: %s" % player.position)
	check(near(oxygen.remaining, oxygen.CAPACITY, 0.01), "Dry quay refills the bar: %.1f" % oxygen.remaining)


func test_skills_blocked_while_swimming() -> void:
	await place(OPEN_WATER, 60.0)
	var before := oxygen.remaining
	for action in [&"attack", &"parry", &"dodge", &"ultimate"]:
		if InputMap.has_action(action):
			Input.action_press(action)
			await step(2)
			Input.action_release(action)
	await step(20)
	check(player.air_state == LanPlayer.AirState.SWIMMING and player.attack_state == LanPlayer.AttackState.NONE,
		"Combat inputs do nothing while swimming")
	check(oxygen.remaining < before and oxygen.remaining > before - 3.0, "Only oxygen changes the bar under water: %.1f → %.1f" % [before, oxygen.remaining])


func test_empty_damage() -> void:
	await place(OPEN_WATER, 0.0)
	var hp := stats.health
	var hits := [0]
	var on_hit := func(_amount: int) -> void: hits[0] += 1
	oxygen.oxygen_damage.connect(on_hit)
	var reaction := false
	for i in 190:
		await physics_frame
		reaction = reaction or player.hit_reaction_active
	oxygen.oxygen_damage.disconnect(on_hit)
	var expected := 3 * UnderwaterOxygen.DAMAGE_PER_TICK
	check(hits[0] == 3 and hp - stats.health == expected, "Empty bar: %d hp per %.0f s (%d ticks, -%d)" % [UnderwaterOxygen.DAMAGE_PER_TICK, UnderwaterOxygen.DAMAGE_INTERVAL, hits[0], hp - stats.health])
	check(not reaction and player.air_state == LanPlayer.AirState.SWIMMING, "No hurt reaction/stunlock: keeps swimming")
	await place(NEAR_SURFACE, 0.0)
	Input.action_press(&"ui_up")
	for i in 240:
		await physics_frame
		if player.swim.is_floating():
			break
	release_all()
	var hp_surface := stats.health
	await step(90)
	check(stats.health == hp_surface, "No damage once breathing again")


func test_drowning_respawn() -> void:
	stats.restore_health()
	await place(level.start, 100.0)
	await step(30)
	var breath: Vector2 = level.breath_point
	check(breath.distance_to(level.start) < 40.0, "Breath point follows the last air: %s" % breath)
	await place(OPEN_WATER, 0.0)
	var assist := stats.refill_health_on_depletion
	stats.refill_health_on_depletion = false  # BattleAssist invincibility would refill instead
	stats.health = UnderwaterOxygen.DAMAGE_PER_TICK
	var drowned: int = level.drowned_count
	await step(75)
	check(level.drowned_count == drowned + 1, "Out of health under water → drowned")
	check(player.position.distance_to(breath) < 40.0, "Respawned at the breath point: %s" % player.position)
	stats.refill_health_on_depletion = assist
	check(stats.health == stats.max_health and near(oxygen.remaining, oxygen.CAPACITY, 0.01), "Health and oxygen restored")


func test_swimming_outside_level() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var other := (load("res://scenes/player/lan/lan_player.tscn") as PackedScene).instantiate() as LanPlayer
	other.world_min_x = 0
	other.world_max_x = 3000
	other.fallback_ground_y = 3000
	world.add_child(other)
	var floor_piece := PIECE.instantiate() as TerrainPiece
	floor_piece.position = Vector2(0, 1200)
	floor_piece.length = 3000.0
	world.add_child(floor_piece)
	floor_piece.register_to(other)
	var volume := UnderwaterVolume.new()
	volume.position = Vector2(400, 300)
	volume.size = Vector2(1800, 960)
	world.add_child(volume)
	volume.register_to(other)
	await step(3)
	other.reset_after_map_fall(Vector2(1200, 700))
	other.air_state = LanPlayer.AirState.FALLING
	other.oxygen.remaining = 40.0
	await step(240)
	check(other.air_state == LanPlayer.AirState.SWIMMING, "Swimming in another level's deep water")
	check(near(other.oxygen.remaining, 20.0, 0.5) and other.combat_stats.health == other.combat_stats.max_health,
		"Swimming in another map drains the same blue gauge (%.1f)" % other.oxygen.remaining)
	check(other.oxygen.get_parent() == other, "Each player owns their traversal gauge")
	world.queue_free()
