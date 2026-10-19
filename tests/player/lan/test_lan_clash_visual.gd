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

## Live shared impacts (CombatImpactEffect) anywhere in the tree.
func impacts() -> Array:
	return get_nodes_in_group(CombatImpactEffect.GROUP).filter(func(e) -> bool: return is_instance_valid(e) and not e.is_queued_for_deletion())

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
		var before := impacts()
		check(parry(normal_attack(n)) == CombatHitResult.Type.PARRY_SUCCESS, "Parry %d succeeds" % n)
		var answers := pieces_of(&"crescent").filter(func(p) -> bool: return p.get_parent() == lan)
		check(not answers.is_empty() and answers.back().width <= LanClashVisual.CRESCENT_WIDTH and LanClashVisual.CRESCENT_WIDTH <= 24.0, "Parry %d: Lan answers with a thin crescent from her sword" % n)
		if not answers.is_empty(): sweeps.append(signf(answers.back().end_angle - answers.back().start_angle))
		var contact := lan.defense_contact_point(deer.global_position)
		var fresh := impacts().filter(func(e) -> bool: return not before.has(e))
		check(fresh.size() == 1 and fresh[0].kind in [CombatImpactEffect.Kind.PARRY, CombatImpactEffect.Kind.POISE_BREAK] and fresh[0].global_position.distance_to(contact) < 1.0, "Parry %d: exactly one shared impact, on Lan's blade (kinds %s)" % [n, str(fresh.map(func(e) -> int: return e.kind))])
		var star: PixelSlash = fresh[0].star if fresh.size() == 1 else null
		check(star != null and star.age >= star.duration - 0.0001, "Parry %d: its star is already open for the hit-stop frame" % n)
		check(pieces_of(&"star").is_empty() and pieces_of(&"burst").is_empty() and pieces_of(&"sparks").is_empty(), "Parry %d: Lan adds no second burst at the contact" % n)
		if star != null: radii.append(star.radius)
		check(visual.chain == n, "Parry %d counts as clash %d" % [n, n])
		if n == 1: await snapshot("clash_1")
		await wait_hit_stop()
		visual.advance(0.05)
		if n == 2: check(visual.counter_view.panel.visible and visual.counter_view.digits.get_child_count() == 1, "Supplied digit and HIT art appear from the second clash")
		lan.defense_state = LanPlayer.DefenseState.NONE
	var rising := radii.size() == 5
	for i in range(1, radii.size()): rising = rising and radii[i] >= radii[i - 1]
	check(rising and radii[4] > radii[0], "Parry impacts grow through the run %s" % str(radii))
	var alternating := sweeps.size() == 5
	for i in range(1, sweeps.size()): alternating = alternating and sweeps[i] == -sweeps[i - 1]
	check(alternating, "Lan's answers alternate their sweep")
	check(visual.counter_view.panel.visible and visual.counter_view.milestone == 0, "Five clashes use the original gold art without an extra milestone")
	check(visual.counter_view.panel.global_position.x > 900 and visual.counter_view.word.get_global_rect().end.x <= 1241, "Clash counter stays on screen right")
	await snapshot("clash_5")

	# User: taking damage does not break the existing clash count; only timeout does.
	var hit := lan.receive_combat_hit(normal_attack(9))
	check(hit == CombatHitResult.Type.NORMAL_HIT and visual.chain == 5, "Taking damage preserves clash count")
	visual.advance(0.01)
	check(visual.counter_view.panel.visible, "Counter remains visible after taking damage")
	await wait_hit_stop()
	visual.advance(3.01)
	check(visual.chain == 0 and not visual.counter_view.panel.visible, "Three seconds without a parry clears and hides the counter")
	# Exercise the existing parry signal through the milestone values; no hit counter exists.
	for threshold in [10, 20, 50]:
		while visual.chain < threshold:
			(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.emit(deer, normal_attack(50 + visual.chain), lan.defense_contact_point(deer.global_position), false)
			if visual.chain < threshold: visual.advance(0.3)
		var view := visual.counter_view
		check(view.milestone == threshold and view.digits.get_child_count() == 2, "Clash %d selects milestone and digit art" % threshold)
		check(view.digits.scale.is_equal_approx(Vector2.ONE * 1.3), "Clash %d instantly scales digits to 1.3" % threshold)
		check(view.panel.modulate != Color.WHITE, "Clash %d has a local milestone accent" % threshold)
		await snapshot("clash_%d_pop" % threshold)
		if threshold == 10 and not output.is_empty():
			DirAccess.make_dir_recursive_absolute(output.path_join("pop"))
			for frame in 24:
				await snapshot("pop/frame_%03d" % frame)
				visual.advance(1.0 / 60.0)
			# Restart the same displayed value to check rebound timings below.
			view.show_count(visual.chain)
		visual.advance(0.08)
		check(view.digits.scale.x < 1.3 and view.digits.position.length() <= 2.0, "Clash %d rebounds with small local shake" % threshold)
		visual.advance(0.22)
		check(view.digits.scale.is_equal_approx(Vector2.ONE) and view.digits.position == Vector2.ZERO and view.panel.modulate.is_equal_approx(Color.WHITE), "Clash %d returns to its original size and color" % threshold)
		await snapshot("clash_%d_rest" % threshold)
	visual.advance(3.01)

	# Red parry → 一闪 through the attacker, delayed cuts and a burst on it.
	place()
	var red := CombatAttackData.new(&"test_clash_red", deer, 20, 12, 180.0, 0.0, CombatAttackData.DangerType.COUNTERABLE_DANGER)
	check(parry(red) == CombatHitResult.Type.PARRY_SUCCESS and lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "A red strike is red-parried")
	await wait_hit_stop()
	lan.red_parry_frame_changed.emit(deer, LanClashVisual.COUNTER_FRAME)
	check(lan.global_position.x > deer.position.x + LanClashVisual.COUNTER_MIN_CROSS, "一闪 carries Lan through to the deer's far side")
	await snapshot("flash_step")
	var lines_before := pieces_of(&"line").size()
	for i in 16: visual.advance(1.0 / 60.0)  # to just past the third cut
	check(pieces_of(&"line").size() - lines_before == 3, "Three delayed cuts open on the deer")
	var cut_impacts := visual.impacts.filter(func(e) -> bool: return is_instance_valid(e) and e.kind == CombatImpactEffect.Kind.COUNTER_CUT)
	check(cut_impacts.size() == 3 and cut_impacts.all(func(e) -> bool: return e.get_parent() == deer and e.global_position.distance_to(LanClashVisual.counter_point(deer)) < 1.0), "Each delayed cut lands with the shared impact on the deer")
	for i in 8: visual.advance(1.0 / 60.0)
	var finish := visual.impacts.filter(func(e) -> bool: return is_instance_valid(e) and e.kind == CombatImpactEffect.Kind.COUNTER_FINISH)
	check(finish.size() == 1 and finish[0].is_finisher() and finish[0].star.radius >= 100.0 and finish[0].look().palette == &"gold", "The counter ends in the gold finisher impact")
	check(pieces_of(&"star").is_empty() and pieces_of(&"burst").is_empty(), "The counter adds no burst of its own beside the shared impact")
	await snapshot("counter_burst")
	lan.red_parry_finished.emit(deer)
	await wait_hit_stop()
	visual.advance(1.0)

	# No room behind the attacker: Lan stays on her side.
	place()
	deer.position.x = lan.world_max_x - 40.0
	lan.global_position.x = deer.position.x - 165.0
	var stay_x := lan.global_position.x
	lan.red_parry_frame_changed.emit(deer, LanClashVisual.COUNTER_FRAME)
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
			while f < 240 and (deer.state == DeerBoss.State.CLASH or f < 10 or not visual.pieces.is_empty() or not visual.impacts.is_empty()):
				var delta := Engine.time_scale / 60.0
				var next := deer.clash_phase.next_parry_contact_in() if deer.state == DeerBoss.State.CLASH else -1.0
				if next >= 0.0 and next <= 0.04 and lan.defense_state != LanPlayer.DefenseState.RED_PARRY_SUCCESS:
					lan.defense_state = LanPlayer.DefenseState.PARRY_ACTIVE
				deer._physics_process(delta)
				visual.advance(delta)
				if lan.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS and not red_emitted:
					red_emitted = true
					lan.red_parry_frame_changed.emit(deer, LanClashVisual.COUNTER_FRAME)
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
