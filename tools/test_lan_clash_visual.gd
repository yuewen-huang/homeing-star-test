extends SceneTree

## Lan's global 拼刀 presentation (LanClashVisual + CombatFeedbackService.parry_landed and
## chain escalation), driven through Lan's real parry path against the wind-phase deer in
## the production final room (the development room's observer cannot parry). Saves go to
## an in-memory stand-in. Optional user args: snapshot directory, then "frames" to save
## every frame of two deer rhythms parried by Lan (subfolders accel, red).

class MemoryProgress extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var room: Chapter1DeerBossRoom
var deer: DeerBoss
var lan: LanPlayer
var visual: LanClashVisual
var checks := 0
var failures := 0
var output := ""
var capture_frames := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func wait_hit_stop() -> void:
	for i in 40:
		await process_frame
		if is_equal_approx(Engine.time_scale, 1.0): return

## One parry along Lan's real path: her hurtbox result, then the attacker's settlement.
func parry(attack: CombatAttackData) -> CombatHitResult.Type:
	lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
	var result := lan.receive_combat_hit(attack)
	if result == CombatHitResult.Type.PARRY_SUCCESS:
		deer.on_attack_parried(attack, lan.defense_contact_point(deer.global_position))
	return result

func normal_attack(n: int) -> CombatAttackData:
	return CombatAttackData.new(StringName("test_clash_%d" % n), deer, 12, 12, 180.0, 0.0, CombatAttackData.DangerType.NORMAL)

func pieces_of(shape: StringName) -> Array:
	return visual.pieces.filter(func(p) -> bool: return is_instance_valid(p) and p.shape == shape)

func snapshot(path: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(path + ".png"))

func place() -> void:
	if deer.poise_broken: deer.finish_stagger()
	deer._recover(0.0)
	deer.position.x = 820.0
	deer.direction = -1.0
	lan.reset_after_map_fall(Vector2(655, 555))
	lan.combat_stats.restore_health()
	lan.velocity = Vector2.ZERO
	lan.defense_state = LanPlayer.DefenseState.NONE

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	capture_frames = args.size() > 1 and args[1] == "frames"
	var original := root.get_node("SaveProgress")
	root.remove_child(original); original.free()
	var memory := MemoryProgress.new(); memory.name = "SaveProgress"; root.add_child(memory)
	var assist := root.get_node("/root/BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)  # every parry manual
	room = load("res://scenes/sideview/chapter_1_final_boss_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	await process_frame; await process_frame
	# Close the deer's opening comic so the fight is on screen (its own abandon path).
	for node in room.find_children("*", "WindSightingComic", true, false):
		node.abandoned.emit()
	await process_frame; await process_frame
	deer = room.deer
	lan = room.player
	deer.set_physics_process(false); lan.set_physics_process(false)
	deer.manual_control = true
	deer.phase = 3
	visual = lan.clash_visual
	visual.set_process(false)
	check(visual != null and visual.get_parent() == lan, "Every Lan owns a clash visual")
	place()

	# Escalation: the first parry keeps the base stop; later ones grow.
	check(is_equal_approx(CombatFeedbackService.parry_hit_stop(0), CombatFeedbackService.TIER_HIT_STOP[CombatFeedbackService.Tier.PARRY]), "The first parry keeps the base hit-stop")
	var growing := true
	for n in range(1, 6): growing = growing and CombatFeedbackService.parry_hit_stop(n) > CombatFeedbackService.parry_hit_stop(n - 1) and CombatFeedbackService.parry_shake(n) > CombatFeedbackService.parry_shake(n - 1)
	check(growing, "Each parry in a run stops longer and shakes harder")

	# A run of five parries.
	var radii: Array[float] = []
	var sweeps: Array[float] = []
	for n in range(1, 6):
		check(parry(normal_attack(n)) == CombatHitResult.Type.PARRY_SUCCESS, "Parry %d succeeds" % n)
		var answers := pieces_of(&"crescent").filter(func(p) -> bool: return p.get_parent() == lan)
		check(not answers.is_empty(), "Parry %d: Lan answers with a crescent from her sword" % n)
		if not answers.is_empty(): sweeps.append(signf(answers.back().end_angle - answers.back().start_angle))
		var stars := pieces_of(&"star")
		var star: PixelSlash = stars.back() if not stars.is_empty() else null
		check(star != null and star.age >= star.duration - 0.0001 and star.center.distance_to(lan.defense_contact_point(deer.global_position)) < 1.0, "Parry %d: the clash star is already open on Lan's blade" % n)
		if star != null: radii.append(star.radius)
		check(visual.chain == n, "Parry %d counts as clash %d" % [n, n])
		if n == 1: await snapshot("clash_1")
		await wait_hit_stop()
		visual.advance(0.05)
		if n == 2: check(visual.label.visible and visual.label.text == "2 拼刀", "The counter appears from the second clash")
		lan.defense_state = LanPlayer.DefenseState.NONE
	var rising := radii.size() == 5
	for i in range(1, radii.size()): rising = rising and radii[i] >= radii[i - 1]
	check(rising and radii[4] > radii[0], "Clash stars grow through the run %s" % str(radii))
	var alternating := sweeps.size() == 5
	for i in range(1, sweeps.size()): alternating = alternating and sweeps[i] == -sweeps[i - 1]
	check(alternating, "Lan's answers alternate their sweep")
	check(visual.label.text == "5 拼刀" and visual.label.get_theme_color("font_color") == Color("ffe189"), "Five clashes turn the counter gold")
	await snapshot("clash_5")

	# A hit that gets through breaks the run.
	var hit := lan.receive_combat_hit(normal_attack(9))
	check(hit == CombatHitResult.Type.NORMAL_HIT and visual.chain == 0, "A hit that gets through ends the run")
	visual.advance(0.01)
	check(visual.label.visible and visual.label.text == "拼刀中断", "The broken run is announced")
	await wait_hit_stop()
	visual.advance(1.0)
	check(not visual.label.visible, "The announcement fades")

	# Red parry → 一闪 through the attacker, delayed cuts and a burst on it.
	place()
	var red := CombatAttackData.new(&"test_clash_red", deer, 20, 12, 180.0, 0.0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(parry(red) == CombatHitResult.Type.PARRY_SUCCESS and lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "A red strike is red-parried")
	await wait_hit_stop()
	lan.red_parry_frame_changed.emit(deer, RedCounterSlashVisual.FIRST_FRAME)
	check(lan.global_position.x > deer.position.x + LanClashVisual.COUNTER_MIN_CROSS, "一闪 carries Lan through to the deer's far side")
	await snapshot("flash_step")
	var lines_before := pieces_of(&"line").size()
	for i in 16: visual.advance(1.0 / 60.0)  # to just past the third cut
	check(pieces_of(&"line").size() - lines_before == 3, "Three delayed cuts open on the deer")
	for i in 8: visual.advance(1.0 / 60.0)
	check(pieces_of(&"star").any(func(s) -> bool: return s.radius >= 100.0), "The counter ends in a large burst")
	await snapshot("counter_burst")
	lan.red_parry_finished.emit(deer)
	await wait_hit_stop()
	visual.advance(1.0)

	# No room behind the attacker: Lan stays on her side.
	place()
	deer.position.x = lan.world_max_x - 40.0
	lan.global_position.x = deer.position.x - 165.0
	var stay_x := lan.global_position.x
	lan.red_parry_frame_changed.emit(deer, RedCounterSlashVisual.FIRST_FRAME)
	check(is_equal_approx(lan.global_position.x, stay_x), "Against a wall the counter does not move Lan")
	visual._pending.clear()
	lan.red_parry_finished.emit(deer)
	visual.advance(1.0)

	if capture_frames:
		for pass_index in 2:
			var folder := "accel" if pass_index == 0 else "red"
			DirAccess.make_dir_recursive_absolute(output.path_join(folder))
			place()
			lan.red_parry_finished.emit(deer)
			lan.animated_sprite.play(&"idle")
			for i in 120: visual.advance(1.0 / 60.0)
			deer.start_clash(&"accel_five" if pass_index == 0 else &"red_finale", lan.global_position.x)
			# Like a player: press parry just before each beat; the deer's own contact
			# settlement then resolves the parry through the production path.
			var red_emitted := false
			var f := 0
			while f < 240 and (deer.state == DeerBoss.State.CLASH or f < 10 or not visual.pieces.is_empty()):
				var delta := Engine.time_scale / 60.0
				var next := deer.clash_phase.next_parry_contact_in() if deer.state == DeerBoss.State.CLASH else -1.0
				if next >= 0.0 and next <= 0.04 and lan.defense_state != LanPlayer.DefenseState.RED_PARRY_SUCCESS:
					lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
				deer._physics_process(delta)
				visual.advance(delta)
				if lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS and not red_emitted:
					red_emitted = true
					lan.red_parry_frame_changed.emit(deer, RedCounterSlashVisual.FIRST_FRAME)
				await snapshot("%s/frame_%03d" % [folder, f])
				f += 1
			lan.red_parry_finished.emit(deer)
			await wait_hit_stop()
	Engine.time_scale = 1.0
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	current_scene = null
	room.free()
	print("LAN CLASH: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
