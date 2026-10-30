extends "../../support/harness.gd"
## 第二章终关 · 水下沉城 step 2: oxygen on the blue bar (UnderwaterOxygen), real physics.
const SCENE_PATH := "res://scenes/levels/chapter_2_underwater/chapter_2_underwater.tscn"
const PLAYER := preload("res://scenes/player/lan/lan_player.tscn")
const PIECE := preload("res://scenes/levels/common/terrain_piece.tscn")
const ACTIONS: Array[StringName] = [&"ui_left", &"ui_right", &"ui_up", &"ui_down", &"jump", &"instant_dash"]
const OPEN_WATER := Vector2(640, 1500)  # R02 mid-water, far from floors, pockets and bubbles

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
	await test_pocket_refill()
	await test_bubble_refill()
	await test_skills_blocked_while_swimming()
	await test_empty_damage()
	await test_drowning_respawn()
	level.queue_free()
	await process_frame
	await test_no_oxygen_outside_level()
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
	stats.mana = mana
	await step(3)


func near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance


func test_setup() -> void:
	level = (load(SCENE_PATH) as PackedScene).instantiate() as Node2D
	root.add_child(level)
	current_scene = level
	await step(40)
	player = level.player
	oxygen = level.oxygen
	stats = player.combat_stats
	check(oxygen != null and oxygen.player == player, "Level adds the UnderwaterOxygen component")
	check(near(stats.mana, stats.max_mana, 0.01), "Oxygen (blue bar) starts full: %.1f/%.1f" % [stats.mana, stats.max_mana])
	check(level.bubbles.size() == 4, "Bubbles b1–b4 are real pickups: %d" % level.bubbles.size())
	check(UnderwaterOxygen.FULL_BAR_SECONDS == 20.0 and UnderwaterOxygen.REFILL_SECONDS == 0.5, "Tunable constants (20 s / 0.5 s)")


func test_drain_while_swimming() -> void:
	await place(OPEN_WATER, stats.max_mana)
	check(player.air_state == LanPlayer.AirState.SWIMMING and oxygen.mode == UnderwaterOxygen.Mode.SWIMMING, "Swimming in open water")
	var before := stats.mana
	await step(180)
	var expected := stats.max_mana * 3.0 / UnderwaterOxygen.FULL_BAR_SECONDS
	check(near(before - stats.mana, expected, 1.5), "3 s swimming drains ≈%.0f (%.1f)" % [expected, before - stats.mana])
	check(stats.health == stats.max_health, "No damage while oxygen remains")


func test_hold_on_underwater_floor() -> void:
	await place(Vector2(1900, 2050), 50.0)  # R04 floor, inside the water
	var landed := false
	for i in 300:
		await physics_frame
		if player.is_on_floor() and player.air_state != LanPlayer.AirState.SWIMMING:
			landed = true
			break
	check(landed and player.is_in_deep_water(), "Standing on a floor inside the water (%s, deep %s)" % [player.position, player.is_in_deep_water()])
	var before := stats.mana
	await step(120)
	check(oxygen.mode == UnderwaterOxygen.Mode.HOLDING, "Mode HOLDING on the underwater floor: %s" % UnderwaterOxygen.Mode.keys()[oxygen.mode])
	check(near(stats.mana, before, 0.01), "No drain (and no refill) on the floor: %.1f → %.1f" % [before, stats.mana])


func test_surface_refill() -> void:
	await place(Vector2(640, 420), 10.0)  # R01 just under the global surface
	Input.action_press(&"ui_up")
	var floated := false
	for i in 240:
		await physics_frame
		if player.swim.is_floating():
			floated = true
			break
	release_all()
	check(floated, "Swims up and floats at the surface")
	var low := stats.mana
	await step(6)
	check(stats.mana > low and stats.mana < stats.max_mana, "Refill is gradual, not a pop (%.1f after 0.1 s)" % stats.mana)
	await step(30)
	check(near(stats.mana, stats.max_mana, 0.01), "Full again within ~0.6 s at the surface: %.1f" % stats.mana)
	await step(120)
	check(near(stats.mana, stats.max_mana, 0.01) and player.swim.is_floating(), "No drain while floating at the surface")


func test_pocket_refill() -> void:
	await place(Vector2(2300, 900), 10.0)  # R03 air pocket save ledge
	await step(60)
	check(not player.is_in_deep_water() and player.air_state == LanPlayer.AirState.GROUNDED, "Standing in the R03 air pocket: %s" % player.position)
	check(near(stats.mana, stats.max_mana, 0.01), "Air pocket refills the bar: %.1f" % stats.mana)


func test_bubble_refill() -> void:
	var bubble: OxygenBubble = level.bubbles[0]
	var at := bubble.global_position + Vector2(0.0, 29.0)
	await place(at + Vector2(-120.0, 0.0), 10.0)
	check(oxygen.mode == UnderwaterOxygen.Mode.SWIMMING, "Swimming next to bubble b1")
	player.reset_after_map_fall(at)
	player.air_state = LanPlayer.AirState.FALLING
	await step(45)
	check(not bubble.available, "Bubble b1 taken on touch")
	check(near(stats.mana, stats.max_mana, 2.5), "Bubble refills the bar under water: %.1f" % stats.mana)
	await place(OPEN_WATER, stats.max_mana)
	await step(int(OxygenBubble.RESPAWN_SECONDS * 60.0) + 10)
	check(bubble.available, "Bubble b1 respawns after %.0f s" % OxygenBubble.RESPAWN_SECONDS)


func test_skills_blocked_while_swimming() -> void:
	await place(OPEN_WATER, 60.0)
	var before := stats.mana
	for action in [&"attack", &"parry", &"dodge", &"ultimate"]:
		if InputMap.has_action(action):
			Input.action_press(action)
			await step(2)
			Input.action_release(action)
	await step(20)
	check(player.air_state == LanPlayer.AirState.SWIMMING and player.attack_state == LanPlayer.AttackState.NONE,
		"Combat inputs do nothing while swimming")
	check(stats.mana < before and stats.mana > before - 3.0, "Only oxygen changes the bar under water: %.1f → %.1f" % [before, stats.mana])


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
	await place(Vector2(640, 420), 0.0)
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
	await place(Vector2(2300, 900), 100.0)
	await step(30)
	var breath: Vector2 = level.breath_point
	check(breath.distance_to(Vector2(2300, 930)) < 40.0, "Breath point follows the last air: %s" % breath)
	await place(OPEN_WATER, 0.0)
	var assist := stats.refill_health_on_depletion
	stats.refill_health_on_depletion = false  # BattleAssist invincibility would refill instead
	stats.health = UnderwaterOxygen.DAMAGE_PER_TICK
	var drowned: int = level.drowned_count
	await step(75)
	check(level.drowned_count == drowned + 1, "Out of health under water → drowned")
	check(player.position.distance_to(breath) < 40.0, "Respawned at the breath point: %s" % player.position)
	stats.refill_health_on_depletion = assist
	check(stats.health == stats.max_health and near(stats.mana, stats.max_mana, 0.01), "Health and oxygen restored")


func test_no_oxygen_outside_level() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var other := PLAYER.instantiate() as LanPlayer
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
	other.combat_stats.mana = 40.0
	await step(240)
	check(other.air_state == LanPlayer.AirState.SWIMMING, "Swimming in another level's deep water")
	check(near(other.combat_stats.mana, 40.0, 0.01) and other.combat_stats.health == other.combat_stats.max_health,
		"Outside the underwater level the blue bar is untouched (%.1f), no damage" % other.combat_stats.mana)
	check(world.find_children("*", "", true, false).all(func(n): return not n is UnderwaterOxygen), "No oxygen component outside the level")
	world.queue_free()
