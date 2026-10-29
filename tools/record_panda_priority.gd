extends "../tests/support/harness.gd"
## Panda BOSS highlight reel: 对弈 (go board solve) → 震刀 during 笔走龙蛇 → 一笔山河 / 千里江山 5-hit.
## MovieWriter-friendly: keep MirrorLake._process on; real Input.action_press for parries.

const PARRY_LEAD := 0.32
const PARRY_MIN := 0.02

var scene: MirrorLake
var arena: PandaGoArena
var lan: LanPlayer
var output := ""
var caption: Label
var running := false
var driving := false
var cue_armed := true
var stage := ""
var elapsed := 0.0
var release_actions: Array[StringName] = []
var events: Array[Dictionary] = []
var total_parries := 0
var skill_parries := 0
var last_cue := 99.0

func run() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var args := OS.get_cmdline_user_args()
	output = args[0] if not args.is_empty() else "user://panda_priority"
	DirAccess.make_dir_recursive_absolute(output)
	use_memory_progress()
	var assist := root.get_node("BattleAssist") as BattleAssistSettingsService
	assist.set_difficulty(BattleAssistSettingsService.Difficulty.NORMAL)
	assist.set_player_invincible(false)
	assist._invincibility_label.hide()
	assist._difficulty_label.hide()
	load("D:/HomingStar/homeing-star-test/tools/recording_audio_mix.gd").apply(self)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	lan = scene.player as LanPlayer
	arena = scene.panda_arena
	check(arena != null, "panda arena present")
	lan.input_frozen = false
	lan.combat_stats.refill_health_on_depletion = true
	paused = false
	var layer := CanvasLayer.new()
	scene.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(140, 70)
	caption.size = Vector2(1000, 90)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 24)
	caption.add_theme_color_override(&"font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override(&"shadow_offset_x", 2)
	caption.add_theme_constant_override(&"shadow_offset_y", 2)
	layer.add_child(caption)
	(root.get_node("CombatFeedback") as CombatFeedbackService).parry_landed.connect(_on_parry)
	running = true
	await _beat_go()
	await _beat_bizou()
	await _beat_yibi()
	running = false
	driving = false
	_release_inputs()
	check(total_parries > 0, "Panda reel landed parries: %d" % total_parries)
	expect_save_untouched()
	FileAccess.open(output.path_join("events.json"), FileAccess.WRITE).store_string(JSON.stringify(events, "\t"))
	finish("PANDA PRIORITY")

func _beat_go() -> void:
	stage = "go"
	caption.text = "镜湖熊猫 · 对弈 · 破局"
	caption.show()
	_log("take_start")
	# Walk in from the left of the trigger so start_encounter fires.
	lan.reset_after_map_fall(Vector2(PandaGoArena.TRIGGER_X - 80.0, MirrorLake.STAND_Y))
	await _wait(0.35)
	lan.position = Vector2(PandaGoArena.TRIGGER_X + 40.0, MirrorLake.STAND_Y)
	lan.reset_after_map_fall(lan.position)
	var deadline := 12.0
	while deadline > 0.0 and not (arena.active and arena.game_on and arena.state == PandaGoArena.STATE_PLAYING):
		await _wait(0.1)
		deadline -= 0.1
	check(arena.active and arena.game_on, "对弈 board ready after 弈")
	_log("board_ready")
	# Need yin to place.
	await _switch_to(MirrorLake.Side.YIN)
	lan.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	lan.air_state = LanPlayer.AirState.GROUNDED
	arena.enter_planar()
	await _wait(0.25)
	var sol: Vector2i = arena.session.puzzle.solution
	lan.position = arena.board_world_origin() + arena.board_view.point_local(sol) + Vector2(12, 6)
	await _wait(0.2)
	var res: Dictionary = arena.place_at_feet()
	check(bool(res.get("ok", false)), "solution stone placed")
	_log("stone_placed")
	deadline = 3.0
	while deadline > 0.0 and arena.state != PandaGoArena.STATE_BROKEN:
		await _wait(0.05)
		deadline -= 0.05
	check(arena.state == PandaGoArena.STATE_BROKEN and arena.glyph.kind == &"po", "破 + yang_weak")
	_log("po_weak")
	# Hold 破 on screen, then skip remaining WEAK_SECONDS.
	var pull_left := 2.0
	while pull_left > 0.0 and (arena.pulling or arena.planar):
		await _wait(0.05)
		pull_left -= 0.05
	await _wait(1.2)
	_log("take_end")

func _beat_bizou() -> void:
	stage = "bizou"
	caption.text = "镜湖熊猫 · 笔走龙蛇 · 震刀连反"
	_log("take_start")
	await _switch_to(MirrorLake.Side.YANG)
	lan.combat_stats.restore_health()
	lan.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	lan.reset_after_map_fall(lan.position)
	arena.round_index = 1
	arena._enter_yin()
	check(arena.yin_skill == 1, "yin skill 笔走龙蛇")
	# Wait glyph write + yin_idle → skill start.
	var deadline := 14.0
	while deadline > 0.0 and not arena.skill_started:
		await _wait(0.1)
		deadline -= 0.1
	check(arena.skill_started, "笔走龙蛇 started")
	_log("skill_started")
	skill_parries = 0
	cue_armed = true
	driving = true
	deadline = 14.0
	while deadline > 0.0 and arena.state == PandaGoArena.STATE_YIN and not arena.skills.is_finished():
		await _wait(0.05)
		deadline -= 0.05
	driving = false
	_release_inputs()
	# Let settle into yin_weak briefly.
	deadline = 4.0
	while deadline > 0.0 and arena.state == PandaGoArena.STATE_YIN:
		await _wait(0.05)
		deadline -= 0.05
	await _wait(0.8)
	_log("take_end")
	check(skill_parries > 0, "笔走龙蛇 parries: %d" % skill_parries)

func _beat_yibi() -> void:
	stage = "yibi"
	caption.text = "镜湖熊猫 · 一笔山河 · 千里江山五连"
	_log("take_start")
	await _switch_to(MirrorLake.Side.YANG)
	lan.combat_stats.restore_health()
	lan.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	lan.reset_after_map_fall(lan.position)
	# Cut any leftover yin_weak / writing and jump to ultimate.
	if arena.skills.running:
		arena.skills.clear()
	arena.round_index = 3
	arena._enter_yin()
	check(arena.yin_skill == 3, "yin skill 一笔山河")
	var deadline := 14.0
	while deadline > 0.0 and not arena.skill_started:
		await _wait(0.1)
		deadline -= 0.1
	check(arena.skill_started, "一笔山河 started")
	_log("skill_started")
	skill_parries = 0
	cue_armed = true
	driving = true
	deadline = 16.0
	while deadline > 0.0 and arena.state == PandaGoArena.STATE_YIN and not arena.skills.is_finished():
		await _wait(0.05)
		deadline -= 0.05
	driving = false
	_release_inputs()
	await _wait(1.2)
	_log("take_end")
	check(skill_parries > 0, "一笔山河 parries: %d" % skill_parries)

func _switch_to(side: int) -> void:
	if scene.side == side:
		return
	# Bypass cooldown / finish any wipe, then flip (request_switch sets side immediately).
	scene.switch_cooldown_left = 0.0
	scene.switch_elapsed = -1.0
	scene.advance_switch(3.0)
	var ok := scene.request_switch()
	check(ok, "request_switch ok toward %d" % side)
	scene.advance_switch(3.0)
	check(scene.side == side, "switched to side %d" % side)
	scene.refresh_controls()
	await _wait(0.15)

func _wait(seconds: float) -> void:
	for i in ceili(seconds * 60.0):
		await physics_frame

func _physics_process(delta: float) -> bool:
	if not running:
		return false
	elapsed += delta
	for action in release_actions:
		Input.action_release(action)
	release_actions.clear()
	if not driving:
		return false
	if arena == null or arena.state != PandaGoArena.STATE_YIN or not arena.skills.running:
		return false
	var nxt := INF
	for s in arena.skills.strikes:
		if int(s.state) == 1:
			nxt = minf(nxt, float(s.t) - arena.skills.clock)
	if nxt > PARRY_LEAD or nxt < 0.0:
		cue_armed = true
	if cue_armed and nxt <= PARRY_LEAD and nxt >= PARRY_MIN and lan.defense_state == LanPlayer.DefenseState.NONE:
		cue_armed = false
		lan.start_parry()
		Input.action_press(&"parry")
		release_actions.append(&"parry")
		_log("parry_input")
	return false

func _release_inputs() -> void:
	for action in [&"parry", &"ui_left", &"ui_right", &"ui_up", &"ui_down"]:
		Input.action_release(action)
	release_actions.clear()

func _on_parry(_r: DamageReceiver2D, _a: CombatAttackData, _p: Vector2, red: bool) -> void:
	total_parries += 1
	skill_parries += 1
	_log("red_parry" if red else "parry")

func _log(event: String) -> void:
	events.append({
		"event": event,
		"take": stage,
		"frame": Engine.get_process_frames(),
		"t": elapsed,
		"hp": lan.combat_stats.health if lan else 0,
		"arena": String(arena.state) if arena else "",
		"yin_skill": arena.yin_skill if arena else -1,
		"skill_clock": arena.skills.clock if arena and arena.skills else -1.0,
		"cue": lan.parry_cue.time_to_contact if lan else -1.0,
		"side": scene.side if scene else -1,
		"parries": total_parries,
	})


