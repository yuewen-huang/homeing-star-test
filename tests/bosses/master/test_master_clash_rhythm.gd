extends SceneTree
## The tutorial master's phase-one 拼刀 rhythms (MasterClashRhythm, 2026-10-19): rhythm data,
## AI choice, kept painted wind frames, new baked ribbons, real Lan parries in the formal
## tutorial room, parry pause, drink rule, interrupt and cleanup. Optional user args: an
## output folder, then "frames" to save every frame of each rhythm parried by Lan.

class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

const BEATS := {&"basic_down": [0.60], &"press_return": [0.60, 1.20], &"return_chain": [0.60, 1.12, 1.62],
	&"blink_return": [0.70, 2.05], &"spin_delayed": [0.50, 1.15, 1.86], &"air_plunge": [2.33]}
## Source frame each beat lands on: [layout action, source frame].
const POSES := {&"basic_down": [[&"attack_1", 8]], &"press_return": [[&"attack_1", 8], [&"attack_3", 17]],
	&"return_chain": [[&"attack_2", 8], [&"attack_2", 15], [&"attack_2", 20]],
	&"blink_return": [[&"dash", 7], [&"special_attack", 12]], &"spin_delayed": [[&"attack_3", 5], [&"attack_2", 15], [&"attack_2", 20]],
	&"air_plunge": [[&"air_spin_slam", 17]]}
const BAKED := {&"return_lift": "master_boss/press_return/return_lift/", &"flip_chop": "master_boss/clash_rhythm/flip_chop/",
	&"front_cut": "master_boss/clash_rhythm/front_cut/", &"blink_spin": "master_boss/clash_rhythm/blink_spin/",
	&"heavy_chop": "master_boss/clash_rhythm/heavy_chop/", &"plunge_crash": "master_boss/clash_rhythm/plunge_crash/"}
## Rhythms whose beats Lan parries in the main loop (the dive's gold landing cannot be).
const PARRIED := [&"basic_down", &"press_return", &"return_chain", &"blink_return", &"spin_delayed"]

var room
var master
var player: LanPlayer
var checks := 0
var failures := 0
var outcomes: Array = []
## Every parry the shared feedback settles (sword qi included).
var parries := 0
var output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func rhythm() -> MasterClashRhythm:
	return master.clash_rhythm

func tick(delta := 1.0 / 120.0) -> void:
	master._process(delta)

func until(time: float) -> void:
	while rhythm() != null and rhythm().elapsed + 0.000001 < time:
		tick(minf(1.0 / 120.0, time - rhythm().elapsed))

func wind_matches_kept_frames() -> bool:
	var shown := rhythm().shown()
	var kept: bool = MasterClashRhythm.PAINTED.has(shown[0]) and int(shown[1]) in MasterClashRhythm.PAINTED[shown[0]]
	if master.wind_effect.visible != kept: return false
	return not kept or (master.wind_effect.animation == shown[0] and master.wind_effect.frame == int(shown[1]))

func ready_guard() -> void:
	player.defense_state = LanPlayer.DefenseState.NONE
	player.defense_recoil_active = false
	player.hit_reaction_active = false
	player.play_idle()
	player.start_parry()
	player.animated_sprite.frame = 3
	player.on_player_animation_frame_changed()
	player.animated_sprite.pause()
	outcomes.clear()
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP): effect.free()

## Lan holds her parry while the open hitbox checks its overlaps (real settlement path).
func settle_guard() -> void:
	ready_guard()
	await physics_frame
	await physics_frame
	await process_frame
	master.attack_hitbox._physics_process(0)

func wait_hit_stop() -> void:
	for i in 40:
		if is_equal_approx(Engine.time_scale, 1.0): return
		await process_frame

func place() -> void:
	master._interrupt_for_special(0.0)
	master.state = master.State.CHASE
	master.poise_broken = false
	master.combat_stats.restore_poise()
	master.position = Vector2(260, 555)
	player.position = Vector2(110, 555)
	player.combat_stats.restore_health()
	player.defense_state = LanPlayer.DefenseState.NONE
	player.play_idle()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]
	var capture_frames := args.size() > 1 and args[1] == "frames"
	var exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if exists else PackedByteArray()
	var previous := root.get_node("SaveProgress")
	root.remove_child(previous)
	previous.free()
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)

	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_player_invincible(false)
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.HARD)
	room = load("res://scenes/sideview/tutorial_battle_room.tscn").instantiate()
	room.get_node("MasterBoss").manual_control = true
	root.add_child(room)
	current_scene = room
	await process_frame
	master = room.boss
	player = room.player
	master.set_process(false)
	master.set_physics_process(false)
	master.attack_hitbox.set_physics_process(false)
	player.set_physics_process(false)
	room.set_physics_process(false)
	master.attack_hitbox.hit_resolved.connect(func(target: Node, result: int) -> void:
		if target == player: outcomes.append(result))
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(func(_r, _a, _c, _red) -> void: parries += 1)

	for id: StringName in PARRIED:
		place()
		master.start_clash_rhythm(id)
		var r := rhythm()
		check(r != null and master.state == master.State.PHASE_1_COMBO, "%s: starts as a phase-one combo" % id)
		var times: Array = r.strikes.map(func(s: Dictionary) -> float: return float(s.t))
		check(times.size() == BEATS[id].size(), "%s: %d beats" % [id, BEATS[id].size()])
		var on_beat := true
		for i in times.size(): on_beat = on_beat and is_equal_approx(times[i], BEATS[id][i])
		check(on_beat, "%s: beats at %s" % [id, str(times)])
		var slow := true
		for i in range(1, times.size()): slow = slow and float(times[i]) - float(times[i - 1]) >= 0.5 - 0.0001
		check(slow, "%s: tutorial beats are at least 0.5 s apart" % id)
		var readable := true
		# The last segment only holds the final authored frame until the move ends.
		# Zero is a deliberate held pose (the 停势 / 蓄势 before a heavy).
		for rate in r.fitted_rates().slice(0, -1): readable = readable and (is_zero_approx(rate) or (rate >= ClashRhythm.MIN_FPS - 0.01 and rate <= ClashRhythm.MAX_FPS + 0.01))
		check(readable, "%s: fitted playback stays within %d–%d fps %s" % [id, ClashRhythm.MIN_FPS, ClashRhythm.MAX_FPS, str(r.fitted_rates())])
		var health := player.combat_stats.health
		var kept_ok := true
		for i in times.size():
			var warned := false
			while r.elapsed + 0.000001 < float(times[i]) - 0.01:
				tick(1.0 / 120.0)
				kept_ok = kept_ok and wind_matches_kept_frames()
				if r.elapsed >= float(times[i]) - 0.3: warned = warned or (master.danger_flash != null and master.danger_flash.visible and master.danger_flash_kind == &"red" and not master.danger_warning.visible)
			if r.strikes[i].danger == &"red": check(warned, "%s beat %d: the new-style red flash shows over his chest before the red beat" % [id, i])
			until(float(times[i]))
			var shown := r.shown()
			check(shown[0] == POSES[id][i][0] and int(shown[1]) == int(POSES[id][i][1]), "%s beat %d: body on %s F%02d (shows %s F%02d)" % [id, i, POSES[id][i][0], POSES[id][i][1], shown[0], shown[1]])
			check(master.attack_hitbox.attack != null and r.open_strike() == i, "%s beat %d: damage opens on the beat" % [id, i])
			var spec: Dictionary = r.strikes[i]
			if spec.wind == &"painted":
				check(master.wind_effect.visible and master.wind_effect.frame == int(shown[1]), "%s beat %d: kept painted wind frame on screen" % [id, i])
			else:
				var ribbon: PixelSlash = r.winds.back().node if not r.winds.is_empty() else null
				check(ribbon != null and ribbon.wind_profile == spec.wind and not ribbon._clip.is_empty() and String(ribbon._clip.asset_path).begins_with(BAKED[spec.wind]), "%s beat %d: new %s ribbon plays from the baked atlas" % [id, i, spec.wind])
				check(ribbon != null and ribbon.age >= ribbon.duration - 0.001, "%s beat %d: ribbon fully open on the beat" % [id, i])
				check(not master.wind_effect.visible, "%s beat %d: no legacy painted wind under the new ribbon" % [id, i])
			await settle_guard()
			check(outcomes.has(CombatHitResult.Type.PARRY_SUCCESS), "%s beat %d: real Lan parry succeeds" % [id, i])
			if r.strikes[i].danger == &"red":
				check(player.defense_state == LanPlayer.DefenseState.RED_PARRY_SUCCESS, "%s beat %d: the red beat gives Lan her red parry (一闪)" % [id, i])
				var red_ribbon: PixelSlash = r.winds.back().node
				tick(0.05)
				check(is_instance_valid(red_ribbon) and red_ribbon.visible and red_ribbon.palette_key == &"master_red", "%s beat %d: the red slash keeps fading after the parry interrupts the master" % [id, i])
			check(get_nodes_in_group(CombatImpactEffect.GROUP).size() == 1, "%s beat %d: exactly one shared impact" % [id, i])
			var frozen := r.elapsed
			tick(0.03)
			check(master.parry_pause_remaining <= 0.0 or is_equal_approx(r.elapsed, frozen), "%s beat %d: the parry pause holds the rhythm" % [id, i])
			await wait_hit_stop()
			player.defense_state = LanPlayer.DefenseState.NONE
		check(kept_ok, "%s: painted wind shows only on the six kept frames, frame-matched to the body" % id)
		check(player.combat_stats.health == health, "%s: parried throughout, Lan unhurt" % id)
		until(r.duration + 0.01)
		check(master.clash_rhythm == null and master.state == master.State.RECOVER and master.attack_hitbox.attack == null, "%s: ends in recovery with the hitbox closed" % id)
		for k in 60: tick(1.0 / 60.0)
		await process_frame
		check(master.get_node_or_null("MasterClashWind") == null and master.fading_winds.is_empty(), "%s: wind ribbons are cleared once they have faded" % id)
		await wait_hit_stop()

	# A landed last cut of 回身三连 earns a drink, like the old whirlwind's hardest slash.
	place()
	master.start_clash_rhythm(&"return_chain")
	until(1.62)
	player.defense_state = LanPlayer.DefenseState.NONE
	player.play_idle()
	outcomes.clear()
	await physics_frame
	await physics_frame
	await process_frame
	master.attack_hitbox._physics_process(0)
	check(outcomes.has(CombatHitResult.Type.NORMAL_HIT) and master.pending_drink, "回身三连's landed last cut earns a drink")
	await wait_hit_stop()

	# 压步回锋 draws Lan in; the master stays planted. A close Lan is never pushed out.
	place()
	master.position = Vector2(460, 555)
	player.position = Vector2(110, 555)
	master.start_clash_rhythm(&"press_return")
	until(0.60)
	var gap: float = master.position.x - player.position.x
	check(is_equal_approx(master.position.x, 460.0), "压步回锋: the master does not slide")
	check(absf(gap - MasterClashRhythm.PULL_STOP) < 1.0, "压步回锋: Lan is drawn in to %d px before the first cut (gap %.1f)" % [MasterClashRhythm.PULL_STOP, gap])
	place()
	master.position = Vector2(200, 555)
	player.position = Vector2(110, 555)
	master.start_clash_rhythm(&"press_return")
	until(0.60)
	check(is_equal_approx(player.position.x, 110.0), "压步回锋: a Lan already close is not pushed away")
	master._interrupt_for_special(0.0)
	await wait_hit_stop()

	# Lan's blue parry cue counts down to the master's beats (new-style prompts).
	place()
	master.start_clash_rhythm(&"basic_down")
	until(0.30)
	await physics_frame
	master._report_parry_cue()
	check(player.parry_cue.source == master and absf(player.parry_cue.time_to_contact - 0.30) < 0.02, "The blue parry cue counts down to the master's beat (%.2f s)" % player.parry_cue.time_to_contact)
	master._interrupt_for_special(0.0)
	await wait_hit_stop()

	# 瞬移回斩: gone between vanish and reappearance, landing locked in front of Lan.
	place()
	master.start_clash_rhythm(&"blink_return")
	until(0.45)
	check(not master.animated_sprite.visible, "瞬移回斩: the master is gone while he blinks")
	until(0.60)
	check(master.animated_sprite.visible and is_equal_approx(master.position.x, player.position.x + master.DASH_REAPPEAR_OFFSET), "瞬移回斩: he reappears %d px in front of Lan" % master.DASH_REAPPEAR_OFFSET)
	master._interrupt_for_special(0.0)
	await wait_hit_stop()

	# 旋空突坠 (user reference video): an air burst shoves Lan away and the camera pulls back,
	# he launches high, throws three big parryable crescent qi, then a gold dive that cannot
	# be parried; the camera comes back in on the landing.
	place()
	var ground: float = master.position.y
	var camera: Camera2D = master.get_viewport().get_camera_2d()
	var rest_zoom: Vector2 = camera.zoom
	var before := parries
	var health := player.combat_stats.health
	master.start_clash_rhythm(&"air_plunge")
	var r := rhythm()
	until(0.62)
	check(absf(player.position.x - master.position.x) >= MasterClashRhythm.PUSH_REACH - 1.0, "旋空突坠: the air burst shoves Lan %d px away" % MasterClashRhythm.PUSH_REACH)
	var gust: PixelSlash = r.winds[0].node
	check(gust.wind_profile == &"push_gust" and not gust._clip.is_empty(), "旋空突坠: the push is a baked burst of wind along the ground")
	check(gust.get_parent().get_parent() == master.get_parent() and gust.get_parent().global_position.y > master.global_position.y + 100.0, "旋空突坠: the push wind stays on the ground while he goes up")
	check(camera.zoom.x < rest_zoom.x * 0.85, "旋空突坠: the camera pulls back as he goes up (%.2f)" % (camera.zoom.x / rest_zoom.x))
	until(0.50)
	check(r.shown()[1] == 6 and master.position.y < ground - 10.0, "旋空突坠: he rises on the airborne frame F06, not the crouch (shows F%02d)" % r.shown()[1])
	check(not r.ghosts.is_empty(), "旋空突坠: afterimages trail the rising body")
	until(0.90)
	check(master.position.y < ground - 170.0, "旋空突坠: he launches high")
	check(r.projectiles.size() >= 1 and not (r.projectiles[0] as MasterSwordQi).visual._clip.is_empty(), "旋空突坠: sword qi fly from the baked atlas")
	# Lan holds her guard while the qi arrive (physics frames let their hitboxes settle).
	var gold_warned := false
	while master.clash_rhythm == r and r.elapsed < 2.12:
		gold_warned = gold_warned or (master.danger_flash != null and master.danger_flash.visible and master.danger_flash_kind == &"gold" and not master.danger_warning.visible)
		if player.defense_state != LanPlayer.DefenseState.PARRY_ACTIVE: ready_guard()
		tick(1.0 / 60.0)
		await physics_frame
		await wait_hit_stop()
	check(parries - before == 3, "旋空突坠: all three sword qi are parried like ordinary strikes (%d)" % (parries - before))
	check(player.combat_stats.health == health, "旋空突坠: parried qi leave Lan unhurt")
	player.defense_state = LanPlayer.DefenseState.NONE
	player.play_idle()
	while master.clash_rhythm == r and r.elapsed < MasterClashRhythm.AIR_LAND - 0.01:
		tick(1.0 / 120.0)
		gold_warned = gold_warned or (master.danger_flash != null and master.danger_flash.visible and master.danger_flash_kind == &"gold" and not master.danger_warning.visible)
	check(gold_warned, "旋空突坠: the new-style gold flash shows over his chest before the dive lands")
	check(master.position.y < ground - 1.0, "旋空突坠: the dive is still coming down just before the landing beat")
	check(not r.winds.any(func(w) -> bool: return is_instance_valid(w.node) and w.node.wind_profile == &"plunge_crash"), "旋空突坠: no landing burst before he touches down")
	check(not r.ghosts.is_empty(), "旋空突坠: afterimages trail the dive")
	until(MasterClashRhythm.AIR_LAND)
	check(is_equal_approx(master.position.y, ground), "旋空突坠: he lands on the beat")
	var crash: PixelSlash = r.winds.back().node
	# The room scales the master (0.924); the blade, burst and hitbox all scale with him.
	var scale_x: float = master.global_scale.x
	var blade_x: float = master.global_position.x + r.direction * MasterClashRhythm.SWORD_TIP_X * scale_x
	check(absf(crash.global_position.x + r.direction * 60.0 * scale_x - blade_x) < 2.0 and absf(master.attack_hitbox.global_position.x - blade_x) < 2.0,
		"旋空突坠: the gold burst and the landing damage are centred on the planted blade (blade %.1f, burst %.1f, hitbox %.1f)" % [blade_x, crash.global_position.x + r.direction * 60.0 * scale_x, master.attack_hitbox.global_position.x])
	check(crash.wind_profile == &"plunge_crash" and not crash._clip.is_empty() and String(crash._clip.asset_path).begins_with(BAKED[&"plunge_crash"]), "旋空突坠: the gold landing plays from the baked atlas")
	await settle_guard()
	check(not outcomes.has(CombatHitResult.Type.PARRY_SUCCESS) and not outcomes.is_empty(), "旋空突坠: the gold landing cannot be parried")
	until(r.duration + 0.01)
	await wait_hit_stop()
	for k in 30: await process_frame
	check(camera.zoom.is_equal_approx(rest_zoom), "旋空突坠: the camera is back to its usual framing")

	# Every wind the six rhythms can play (by danger colour) and the sword qi has a baked
	# atlas clip: a missing recipe would otherwise just not show.
	var missing: Array[String] = []
	var wanted: Array = [[&"sword_qi", &"master_wind"]]
	for id: StringName in MasterClashRhythm.ORDER:
		var data: Dictionary = MasterClashRhythm.RHYTHMS[id]
		for spec: Dictionary in data.strikes:
			if spec.wind == &"painted": continue
			var danger: StringName = spec.get("danger", &"normal")
			wanted.append([spec.wind, &"master_red" if danger == &"red" else (&"master_gold" if danger == &"gold" else &"master_wind")])
		for spec: Dictionary in data.get("winds", []): wanted.append([spec.wind, &"master_wind"])
	for pair: Array in wanted:
		var probe := MasterWindVFX.create(pair[0], 1.0, pair[1])
		room.add_child(probe)
		if probe._clip.is_empty(): missing.append("%s/%s" % [pair[0], pair[1]])
		probe.free()
	check(missing.is_empty(), "Every master rhythm wind is baked (%d checked; missing %s)" % [wanted.size(), str(missing)])

	# Unlocks follow the master's remaining health.
	check(MasterClashRhythm.unlocked(1.0).size() == 3 and MasterClashRhythm.unlocked(0.69).has(&"blink_return")
		and not MasterClashRhythm.unlocked(0.69).has(&"air_plunge") and MasterClashRhythm.unlocked(0.39).size() == 6,
		"Rhythms unlock with health: ①②③, then ⑤ at 70%, then ④⑥ at 40%")

	# Mirror, interrupt.
	place()
	master.position = Vector2(110, 555)
	player.position = Vector2(300, 555)
	master.start_clash_rhythm(&"press_return")
	until(1.20)
	check(rhythm().direction == 1.0 and rhythm().winds.back().node.facing == 1.0, "Right-side target mirrors body and ribbon")
	master._interrupt_for_special(0.1)
	check(master.clash_rhythm == null and master.attack_hitbox.attack == null and not master.wind_effect.visible, "Interrupt cancels the rhythm, its hitbox and painted wind")
	await wait_hit_stop()

	# AI: phase one picks rhythms; never the same one three times running; all appear.
	var seen := {}
	var history: Array[StringName] = []
	var three_in_a_row := false
	master.recent_rhythms.clear()
	for i in 300:
		var pick: StringName = master.choose_clash_rhythm()
		seen[pick] = true
		history.append(pick)
		if history.size() >= 3 and history[-1] == history[-2] and history[-2] == history[-3]: three_in_a_row = true
		master.recent_rhythms.append(pick)
		if master.recent_rhythms.size() > 2: master.recent_rhythms.pop_front()
	check(seen.size() == 3 and not three_in_a_row, "At full health the AI uses ①②③ and never repeats one three times")
	place()
	master._start_next_attack()
	check(master.clash_rhythm != null, "Phase-one approach starts a 拼刀 rhythm, not a legacy attack")
	master._interrupt_for_special(0.0)
	await wait_hit_stop()

	if capture_frames:
		for id: StringName in MasterClashRhythm.ORDER:
			# A third user arg records only that rhythm.
			if args.size() > 2 and String(id) != args[2]: continue
			var folder := output.path_join(String(id))
			DirAccess.make_dir_recursive_absolute(folder)
			place()
			# Start 压步回锋 from farther away so the pull shows.
			if id == &"press_return": master.position.x = 480.0
			for i in 20: await process_frame
			master.start_clash_rhythm(id)
			var settled := {}
			var f := 0
			# Keep recording a second past the end: the parry, 一闪 and fading wind follow it.
			var after := 0
			while f < 320 and (master.clash_rhythm != null or f < 40 or after < 60):
				if master.clash_rhythm == null: after += 1
				if master.clash_rhythm != null:
					tick(Engine.time_scale / 60.0)
					var open: int = master.clash_rhythm.open_strike() if master.clash_rhythm != null else -1
					var qi_in_flight: bool = master.clash_rhythm != null and master.clash_rhythm.projectiles.any(func(q) -> bool: return is_instance_valid(q))
					if qi_in_flight and player.defense_state != LanPlayer.DefenseState.PARRY_ACTIVE: ready_guard()
					if open >= 0 and not settled.has(open):
						settled[open] = true
						await settle_guard()
				else:
					tick(Engine.time_scale / 60.0)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % f))
				f += 1
			await wait_hit_stop()

	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == exists, "Save existence unchanged")
	if exists: check(FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved, "In-memory fixture leaves progression byte-identical")
	Engine.time_scale = 1.0
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	current_scene = null
	room.free()
	print("MASTER CLASH RHYTHM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
