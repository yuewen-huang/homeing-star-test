extends SceneTree
## Verify the gold lash against the real fourth-phase 0.8 camera, in both directions.
class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var boss: DeerBoss
var vine: DeerVinePhase
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)
func tick() -> void:
	boss._physics_process(1.0 / 60.0)
	boss.vfx._process(1.0 / 60.0)
func until(predicate: Callable, limit := 600) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return false
func capture(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	(root.get_node("BattleAssist") as BattleAssistSettingsService).set_player_invincible(true)
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	boss = room.deer; vine = boss.vine_phase
	room.set_process(false); room.player.set_physics_process(false)
	boss.set_physics_process(false); boss.vfx.set_process(false)
	room.player.reset_after_map_fall(Vector2(1250, 555))
	boss.phase = 4; boss.reset_phase(); boss.manual_control = true
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "real room completes the fourth-phase transformation")
	room._process(0)
	var camera := room.get_node("Camera2D") as Camera2D
	camera.force_update_scroll()
	check(camera.zoom.is_equal_approx(Vector2(0.8,0.8)), "production camera uses its actual 0.8 flight view")
	for direction in [1.0, -1.0]:
		boss.position.x = room.player.position.x - direction * 400.0
		vine.start_sequence(&"ground_lash")
		var strike: DeerVineStrike = vine.strikes.back()
		var label := "right" if direction > 0.0 else "left"
		check(is_equal_approx(strike.lash_reach, 1280.0) and is_equal_approx(strike.lash_scale * DeerVineLashArt.sweep_reach() * 0.8, 1024.0), label + " sweep measures 1024 screen pixels, exactly 80% of 1280")
		check(strike._sprite.scale.is_equal_approx(Vector2.ONE * strike.lash_scale) and strike.side == direction, label + " giant body preserves uniform proportions and the root pivot")
		await capture(label + "_warning")
		check(until(func() -> bool: return strike.lash_frame() == 7), label + " reaches the upright growth frame")
		await capture(label + "_rise")
		check(until(func() -> bool: return strike.lash_frame() == 15), label + " reaches the fast downstroke")
		check(not strike._lash_trails.is_empty() and strike._lash_trails.back().sprite.scale == strike._sprite.scale, label + " downstroke afterimages share the giant scale")
		await capture(label + "_slam")
		# The redraw preserves the action timing, but its exact widest pose is measured.
		var widest_frame := 11
		var widest_reach := 0.0
		for index in range(11,21):
			for capsule in DeerVineLashArt.capsules(index):
				var reach: float = maxf(capsule[0].x, capsule[1].x) + float(capsule[2])
				if reach > widest_reach: widest_reach = reach; widest_frame = index
		check(until(func() -> bool: return strike.lash_frame() == widest_frame), label + " reaches the measured widest solid sweep")
		var solid := 0.0
		for capsule in strike.capsules():
			solid = maxf(solid, absf(capsule[1].x - strike.origin.x) + float(capsule[2]))
		check(absf(solid * camera.zoom.x / 1280.0 - 0.8) < 0.001, label + " real damage capsules cover the same 80% sweep")
		var center := camera.get_screen_center_position().x
		var safe_x: float = center + direction * 1600.0 * 0.46
		check(is_nan(strike.touch(Rect2(safe_x - 10.0, 481.0, 20.0, 74.0)).x), label + " outer screen margin remains outside the attack")
		await capture(label + "_impact")
		check(until(func() -> bool: return strike.lash_frame() == 23) and not strike.is_active() and strike._lash_trails.is_empty(), label + " recovery clears damage and trails")
		await capture(label + "_recovery")
		check(until(func() -> bool: return vine.strikes.is_empty()), label + " full animation cleans up")
	print("GROUND_LASH_SCREEN: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
