extends SceneTree
## Real final room: camera, full-screen pulse, once-per-fight AI, death/retry cleanup.
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
func until(predicate: Callable, limit := 3000) -> bool:
	for i in limit:
		if predicate.call(): return true
		tick()
	return bool(predicate.call())
func capture(label: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.player_invincible = true
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	boss = room.deer; vine = boss.vine_phase
	room.set_process(false); room.player.set_physics_process(false)
	boss.set_physics_process(false); boss.vfx.set_process(false)
	room.player.reset_after_map_fall(Vector2(1250,555))
	boss.phase = 4; boss.reset_phase(); boss.manual_control = true
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "production transformation reaches human hover")
	room._process(0)
	var camera := room.get_node("Camera2D") as Camera2D
	camera.force_update_scroll()
	check(camera.zoom.is_equal_approx(Vector2.ONE * 0.8), "existing fourth-phase flight camera remains 0.8")
	boss.combat_stats.health = boss.combat_stats.max_health / 2
	boss.phase_ai.choose(300)
	check(vine.sequence_id == &"ultimate" and vine.ultimate_used, "production AI chooses full ultimate once at half health")
	check(until(func() -> bool: return is_instance_valid(vine.god_statue)), "real sequence reaches new finale")
	var statue := vine.god_statue
	check(statue.position == Vector2(1250,555), "production finale is anchored beneath Lan")
	await capture("production_warning")
	until(func() -> bool: return statue.rise_progress() >= 0.5)
	await capture("production_rise")
	# Outside the statue footprint, still in the visible screen: flash must hit once.
	room.player.reset_after_map_fall(Vector2(1750,555))
	assist.player_invincible = false
	room.player.defense_state = LanPlayer.DefenseState.PARRY_NOTHING_EARLY
	var health := room.player.combat_stats.health
	until(func() -> bool: return statue.flashed)
	check(room.player.combat_stats.health == health - DeerGodCome.FLASH_DAMAGE, "green pulse reaches Lan outside statue silhouette and ignores guard")
	check(statue.hitbox.hit_targets.has(room.player.get_instance_id()), "screen pulse has its own single-hit target budget")
	await capture("production_full_flash")
	until(func() -> bool: return statue.age >= statue.dust_start() + statue.erosion_time() * 0.5)
	check(statue.sprite.frame == 0 and statue.sprite.visible and statue.hitbox.attack == null, "production erodes only the first pose with no continuing damage")
	await capture("production_dissolve")
	until(func() -> bool: return not statue.sprite.visible)
	for i in 20: tick()
	await capture("production_dust")
	check(until(func() -> bool: return vine.step == DeerVinePhase.Step.HOVER), "real ultimate waits for dust then resumes hover")
	check(room.player.combat_stats.health == health - DeerGodCome.FLASH_DAMAGE, "dissolution and dust cannot repeat pulse damage")
	boss.phase_ai.choose(300)
	check(vine.sequence_id != &"ultimate", "production AI never repeats the ultimate")
	# Lethal pulse exercises cancellation reentrantly inside the contact callback.
	vine.cancel(); vine.human = true; vine._enter(DeerVinePhase.Step.HOVER)
	vine.start_sequence(&"ultimate")
	assist.player_invincible = true
	until(func() -> bool: return is_instance_valid(vine.god_statue))
	var fatal := vine.god_statue
	room.player.combat_stats.health = 1
	room.player.defense_state = LanPlayer.DefenseState.NONE
	assist.player_invincible = false
	until(func() -> bool: return fatal.finished)
	check(fatal.finished and fatal.hitbox.attack == null and not (root.get_node("CombatFeedback") as CombatFeedbackService).screen_fx.pulse_active() and vine.god_statue == null, "lethal pulse immediately cancels statue and screen pulse inside death callback")
	await process_frame; await process_frame
	boss.set_physics_process(false)
	check(boss.phase == 1 and not vine.ultimate_active and vine.god_statue == null, "retry restarts mist with no finale state")
	print("GOD COME PRODUCTION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
