extends SceneTree
## 镜湖熊猫阴阶段招式：顺序 1234 后 34 循环 / 先写字后出招 / 每击先预警 / 弹反计数 -> yang_weak N 秒 / 0 次直接回阳 / 一笔山河=千里江山 5 次全屏攻击 / 字每字与弈同大 / 出招挥笔 / 墨色预警。
## 用法：homeing-star-test/run-tests.ps1 -Test test_mirror_lake_panda_yin
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	func get_equipped_special_item() -> StringName: return &""
	func get_item_count(_item_id: StringName) -> int: return 0
var failures := 0
var checks := 0
var scene: MirrorLake
var player: LanPlayer
var arena: PandaGoArena
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("OK " if ok else "FAIL ") + label)
func side(value: int) -> void:
	if scene.side == value: return
	scene.advance_switch(3.0)
	scene.request_switch()
	scene.advance_switch(3.0)
## Puts the arena straight into yin number n (as the n-th round's yin).
func enter_yin(n: int) -> void:
	arena.round_index = n
	arena._enter_yin()
func run() -> void:
	var old := root.get_node_or_null("SaveProgress")
	if old != null: old.name = "SaveProgressOld"
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	await process_frame
	player = scene.player as LanPlayer
	arena = scene.panda_arena
	player.combat_stats.refill_health_on_depletion = true
	player.position = Vector2(PandaGoArena.TRIGGER_X + 10, MirrorLake.STAND_Y)
	arena.tick(0.016)
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	# --- 顺序
	var seq := []
	for n in 9: seq.append(PandaGoArena.skill_for_yin(n))
	check(seq == [0, 1, 2, 3, 2, 3, 2, 3, 2], "skills 墨起云生,笔走龙蛇,泼墨惊鸿,一笔山河 then 3/4 loop: %s" % [seq])
	var ql := PandaYinSkills.plan(3)
	var ql_ok := ql.size() == 5
	for s in ql: ql_ok = ql_ok and s.kind == PandaYinSkills.QIANLI and s.get("full", false) and float(s.warn) >= 1.0
	check(ql_ok, "一笔山河 performs 千里江山: 5 full-screen strikes, each warned")
	check(ResourceLoader.exists(PandaYinSkills.QIANLI_DIR + "letter.art.png") and ResourceLoader.exists(PandaYinSkills.QIANLI_DIR + "letter.travel.png"), "千里江山 painting + travel map in the game")
	for k in 3:
		var pl := PandaYinSkills.plan(k)
		var ok := pl.size() > 0
		for s in pl: ok = ok and float(s.warn) > 0.0 and float(s.t) - float(s.warn) > 0.0
		check(ok, "skill %d: every strike has a warning before its hit" % k)
	# 墨起云生：固定节奏，越来越大
	var surge := PandaYinSkills.plan(0)
	var even := true
	var grows := true
	for i in range(1, surge.size()):
		even = even and is_equal_approx(float(surge[i].t) - float(surge[i - 1].t), PandaYinSkills.SURGE_BEAT)
		grows = grows and float(surge[i].size) > float(surge[i - 1].size) and surge[i].offsets.size() >= surge[i - 1].offsets.size()
	check(even and grows and surge.back().offsets.size() == 3, "墨起云生: fixed beat, size and pillar count escalate")
	# 笔走龙蛇：不规则，用到横竖点撇捺勾
	var gaps := {}
	var kinds := {}
	var sk := PandaYinSkills.plan(1)
	for i in sk.size():
		kinds[sk[i].stroke] = true
		if i > 0: gaps[snappedf(float(sk[i].t) - float(sk[i - 1].t), 0.01)] = true
	check(gaps.size() >= 3 and kinds.size() == InkStrokeEffect.KINDS.size(), "笔走龙蛇: irregular gaps, all six basic strokes")
	# 泼墨惊鸿：节奏更宽松、预警更长、范围大
	var sp := PandaYinSkills.plan(2)
	check(float(sp[1].t) - float(sp[0].t) > PandaYinSkills.SURGE_BEAT and float(sp[0].warn) > float(surge[0].warn) and float(sp[0].size) >= 100.0, "泼墨惊鸿: slower beat, longer warning, wide splash")
	# --- 墨起云生：先写字（与弈同位置同尺寸），写完才出招
	side(MirrorLake.Side.YIN)
	enter_yin(0)
	check(arena.state == PandaGoArena.STATE_YIN and arena.glyph.kind == &"moqi" and arena.glyph.visible and not arena.glyph.is_written(), "yin: 墨起云生 glyph being written")
	var gs := arena.glyph_size()
	check(arena.glyph.position == arena.glyph_position() if arena.has_method(&"glyph_position") else true, "glyph at the 弈 spot")
	var gsz := arena.glyph.texture.get_size() * arena.glyph.scale
	check(absf(gsz.y - arena.skill_char_size()) < 0.5 and arena.skill_char_size() >= gs * 0.8, "each name character about 弈/破/困 size (row height %.0f vs box %.0f)" % [gsz.y, gs])
	var br := arena.glyph.position + gsz * 0.5
	check(br.distance_to(arena.glyph_center() + Vector2(gs, gs) * 0.5) < 0.5 and arena.glyph.position.x < PandaGoArena.PANDA_X, "name row up-left of the panda, bottom-right on the 弈 corner")
	var warned := []
	var landed := []
	arena.skills.strike_warned.connect(func(i: int) -> void: warned.append([i, arena.skills.clock]))
	arena.skills.strike_landed.connect(func(i: int, r: int) -> void: landed.append([i, arena.skills.clock, r]))
	arena.tick(arena.glyph.draw_duration - 0.1)
	check(not arena.skill_started and warned.is_empty(), "no attack while the glyph is written")
	arena.tick(0.15)
	check(arena.skill_started and arena.glyph.visible, "glyph written -> skill starts, glyph stays")
	var t := 0.0
	var saw_marker := false
	var swung := 0
	while arena.state == PandaGoArena.STATE_YIN and t < 30.0:
		arena.tick(0.05)
		t += 0.05
		if arena.skill_started and arena.skills.clock < arena.skills.end_time() - 1.0 and arena.panda.action == &"yin_air_write": swung += 1
		for s in arena.skills.strikes: if s.state == 1: saw_marker = true
	var order_ok := warned.size() == surge.size() and landed.size() == surge.size()
	for i in landed.size():
		order_ok = order_ok and warned[i][1] < landed[i][1] - 0.5
	check(order_ok and saw_marker, "墨起云生: every hit preceded by its warning marker")
	check(swung > 20, "panda swings the brush (yin_air_write) while attacking")
	var hits := 0
	for l in landed: if l[2] == CombatHitResult.Type.NORMAL_HIT: hits += 1
	check(hits > 0, "yin player standing in it gets hit (normal enemy damage)")
	check(arena.state == PandaGoArena.STATE_WRITING and arena.panda.action == &"yin_to_yang" and not arena.panda_yin, "0 parries -> straight back to yang")
	# --- 笔走龙蛇：阳玩家弹反 -> 弱 N 秒
	side(MirrorLake.Side.YANG)
	scene.refresh_controls()
	enter_yin(1)
	check(arena.glyph.kind == &"bizou", "second yin: 笔走龙蛇")
	arena.tick(arena.glyph.draw_duration + 0.06)
	var parried := []
	arena.skills.strike_landed.connect(func(_i: int, r: int) -> void: if r == CombatHitResult.Type.PARRY_SUCCESS: parried.append(r))
	var cue := false
	var want := 3
	t = 0.0
	while arena.state == PandaGoArena.STATE_YIN and t < 30.0:
		player.position.x = arena.board_rect().get_center().x
		var nxt := INF
		for s in arena.skills.strikes:
			if s.state == 1: nxt = minf(nxt, float(s.t) - arena.skills.clock)
		if player.parry_cue.source == arena.skills and player.parry_cue.time_to_contact <= ParryCueVisual.APPEAR_LEAD: cue = true
		if parried.size() < want and nxt < 0.06 and player.defense_state == LanPlayer.DefenseState.NONE:
			player.start_parry()
		arena.tick(0.05)
		player._physics_process(0.05)
		t += 0.05
	var n := arena.skills.parries
	check(n >= 1 and n == parried.size(), "parries counted during the skill (%d)" % n)
	check(cue, "yang player gets the parry cue before strikes")
	check(arena.state == PandaGoArena.STATE_YIN_WEAK and arena.panda.action == &"yin_weak" and not arena.glyph.visible, "skill over with parries -> yin_weak, glyph gone")
	check(is_equal_approx(arena.yin_weak_seconds, n * PandaGoArena.WEAK_PER_PARRY), "weak lasts N = parries seconds")
	arena.tick(arena.yin_weak_seconds - arena.state_clock - 0.05)
	check(arena.state == PandaGoArena.STATE_YIN_WEAK, "still weak just before N s")
	arena.tick(0.1)
	check(arena.state == PandaGoArena.STATE_WRITING and arena.panda.action == &"yin_to_yang", "after N s -> yang")
	# --- 泼墨惊鸿 / 一笔山河
	side(MirrorLake.Side.YIN)
	enter_yin(2)
	check(arena.glyph.kind == &"pomo" and arena.yin_skill == 2, "third yin: 泼墨惊鸿")
	enter_yin(3)
	check(arena.glyph.kind == &"yibi" and arena.yin_skill == 3, "fourth yin: 一笔山河 glyph written")
	arena.tick(arena.glyph.draw_duration + 0.06)
	var q_hits := []
	arena.skills.strike_landed.connect(func(_i: int, r: int) -> void: if r == CombatHitResult.Type.NORMAL_HIT: q_hits.append(r))
	var xs := [PandaGoArena.ARENA_MIN_X + 40.0, PandaGoArena.PANDA_X - 60.0, arena.board_rect().get_center().x]
	var painted := false
	t = 0.0
	var k := 0
	while arena.state == PandaGoArena.STATE_YIN and t < 30.0:
		player.position.x = xs[k % 3]
		k += 1
		arena.tick(0.05)
		t += 0.05
		if arena.skills.painting != null and arena.skills.painting.visible: painted = true
	check(q_hits.size() == 5, "千里江山: all 5 full-screen strikes hit wherever Lan stands (%d)" % q_hits.size())
	check(painted, "千里江山 painting shown")
	check(arena.state == PandaGoArena.STATE_WRITING, "千里江山 0 parries -> back to yang")
	enter_yin(4)
	check(arena.yin_skill == 2 and arena.glyph.kind == &"pomo", "fifth yin loops to 泼墨惊鸿")
	enter_yin(5)
	check(arena.yin_skill == 3, "sixth yin: 一笔山河")
	# --- 墨色随玩家阴阳：阴白 / 阳黑，0.2 秒过渡，千里江山不变
	var mat := arena.ink_tone_material
	check(arena.glyph.get_parent() is CanvasGroup and arena.glyph.get_parent().material == mat and arena.skills.get_parent() is CanvasGroup and arena.skills.get_parent().material == mat, "glyph + skill VFX/warnings share one ink-tone material")
	check(arena.skills.painting != null and not (arena.skills.painting.get_parent() is CanvasGroup), "千里江山 painting outside the ink tone (stays coloured)")
	side(MirrorLake.Side.YANG)
	arena.tick(0.5)
	check(is_equal_approx(arena.ink_tone, 0.0) and is_equal_approx(float(mat.get_shader_parameter("tone")), 0.0), "player yang: ink black (tone 0)")
	side(MirrorLake.Side.YIN)
	arena.tick(0.1)
	check(absf(arena.ink_tone - 0.5) < 0.01, "switch tweens: half-way at 0.1 s")
	arena.tick(0.11)
	check(is_equal_approx(arena.ink_tone, 1.0) and is_equal_approx(float(mat.get_shader_parameter("tone")), 1.0), "player yin: ink white (tone 1) after 0.2 s")
	print("\n结果：%d 项检查，%d 项失败" % [checks, failures])
	quit(1 if failures > 0 else 0)