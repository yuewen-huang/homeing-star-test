extends SceneTree
## 镜湖熊猫棋盘战（第一阶段）：触发 + 区域锁死 / 阳 20 秒、阴一招（详见 test_mirror_lake_panda_yin） / 熊猫转阴拉回基线 / 非阴不能落子 / 棋盘上 K 不触发震刀。
## 用法：homeing-star-test/run-tests.ps1 -Test test_mirror_lake_panda_go
class MemoryProgress extends SaveProgressService:
	func _ready() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	var mirror := false
	func get_equipped_special_item() -> StringName: return ItemCatalog.NINGXIN_MIRROR if mirror else &""
	func get_item_count(item_id: StringName) -> int: return 1 if mirror and item_id == ItemCatalog.NINGXIN_MIRROR else 0
var failures := 0
var mem
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
## Runs the current yin skill to its end with Lan not parrying (0 parries -> straight to yang).
func run_yin() -> float:
	player.combat_stats.refill_health_on_depletion = true
	var t := 0.0
	while arena.state == PandaGoArena.STATE_YIN and t < 60.0:
		arena.tick(0.05)
		t += 0.05
	return t
func run() -> void:
	var old := root.get_node_or_null("SaveProgress")
	if old != null: old.name = "SaveProgressOld"
	var memory := MemoryProgress.new()
	memory.name = "SaveProgress"
	root.add_child(memory)
	mem = memory
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	await process_frame
	player = scene.player as LanPlayer
	arena = scene.panda_arena
	check(arena != null and arena.get_parent() == scene.world_root, "arena lives on the Mirror Lake map (no separate room)")
	check(PandaGoArena.ARENA_MIN_X > MirrorLakeInkTrial.STELE_X, "arena is right of the Bixi")
	check(arena.panda.view_scale == PandaActions.DEFAULT_SCALE and arena.panda.position.x > arena.board_rect().end.x, "panda at dev-room scale, standing right of the board")
	check(arena.board_view.size_points() == 5, "5x5 board")
	check(GoBoardView.CELL_X == 110.0 and GoBoardView.STONE_RADIUS == 44.0, "110 px spacing, 44 px stones")
	check(not arena.board_view.visible and not arena.game_on, "no board before the fight")
	# --- trigger + lock
	player.position = Vector2(PandaGoArena.TRIGGER_X - 300, MirrorLake.STAND_Y)
	arena.tick(0.016)
	check(not arena.active, "not triggered left of the arena")
	player.position = Vector2(PandaGoArena.TRIGGER_X + 10, MirrorLake.STAND_Y)
	arena.tick(0.016)
	check(arena.active, "entering the arena starts the encounter")
	scene._process(0.016)
	check(is_equal_approx(scene.camera_x, MirrorLake.camera_x_for(player.position.x)) and absf(scene.camera_y - MirrorLake.camera_y_for(player.position.y)) < 0.01, "camera keeps its normal follow behaviour (not moved for the board)")
	check(not arena.has_method(&"camera_x") and not arena.has_method(&"camera_y"), "arena exposes no camera override")
	# --- 弈字书写中：无棋盘、不能上棋盘
	check(arena.state == PandaGoArena.STATE_WRITING and arena.glyph.visible and arena.glyph.kind == &"yi" and not arena.glyph.is_written(), "fight starts yang: 弈 being written")
	check(not arena.game_on and not arena.board_view.visible, "no board before 弈 is fully written")
	var gs := arena.glyph_size()
	check(is_equal_approx(gs, PandaGoArena.BOSS_HEIGHT * 1.5) and is_equal_approx(arena.glyph.texture.get_width() * arena.glyph.scale.x, gs), "glyph box = 1.5 x BOSS height")
	var grect := Rect2(arena.glyph.position - Vector2(gs, gs) * 0.5, Vector2(gs, gs))
	var prect := Rect2(PandaGoArena.PANDA_X - PandaGoArena.BOSS_HALF_WIDTH, -PandaGoArena.BOSS_HEIGHT, PandaGoArena.BOSS_HALF_WIDTH * 2.0, PandaGoArena.BOSS_HEIGHT)
	var ov := grect.intersection(prect)
	check(grect.get_center().x < prect.get_center().x and grect.get_center().y < prect.position.y and ov.has_area() and ov.get_area() < prect.get_area() * 0.25, "glyph up-left of the panda, overlapping it slightly")
	var held0 := scene.control_inverter.real_held
	held0.clear()
	for code in [KEY_S, KEY_W, KEY_DOWN, KEY_UP]: held0[code] = true
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	arena.tick(0.016)
	check(not arena.planar, "cannot step on while 弈 is written")
	held0.clear()
	arena.tick(arena.glyph.draw_duration)
	check(arena.glyph.is_written() and arena.state == PandaGoArena.STATE_PLAYING and arena.game_on and arena.board_view.visible, "弈 written -> board appears, game on")
	check(arena.session.puzzle_index == PandaGoArena.puzzle_for_round(0), "round 1 uses the easiest puzzle")
	arena.tick(PandaGoArena.BOARD_FADE_TIME)
	check(is_equal_approx(arena.board_alpha, 1.0) and arena.glyph.visible, "board faded in, 弈 stays")
	# --- 棋盘上平面移动
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	player.air_state = LanPlayer.AirState.GROUNDED
	arena.enter_planar()
	check(arena.planar and not player.is_physics_processing(), "on the board: planar, Lan physics paused (K cannot parry)")
	for i in 120: arena.move_planar(Vector2(1, 1).normalized(), 0.05)
	var r := arena.board_rect()
	check(is_equal_approx(player.position.x, r.end.x) and is_equal_approx(player.position.y, r.end.y), "planar move clamped to the board corner")
	# --- 落子需玩家阴
	side(MirrorLake.Side.YANG)
	var before := arena.session.board.to_rows()
	var res := arena.place_at_feet()
	check(not res.ok and res.reason == GoEndgameSession.BLOCK_NEED_YIN, "yang player cannot place")
	check(arena.prompt.visible and arena.prompt.text == "需切阴", "need-yin prompt shown")
	check(arena.session.board.to_rows() == before, "board unchanged when blocked")
	side(MirrorLake.Side.YIN)
	# --- 破局：破字 + 虚弱 5 秒 -> 字消失 -> 切阴
	var won := []
	arena.game_won.connect(func(i: int) -> void: won.append(i))
	var lost := []
	arena.game_lost.connect(func(i: int, why: StringName) -> void: lost.append(why))
	var sol: Vector2i = arena.session.puzzle.solution
	player.position = arena.board_world_origin() + arena.board_view.point_local(sol) + Vector2(20, 8)
	check(arena.nearest_point(player.position) == sol, "feet snap to the nearest intersection")
	var on_board_y := player.position.y
	res = arena.place_at_feet()
	check(res.ok and arena.session.phase == GoEndgameSession.PHASE_SOLVED, "solution solves (session PHASE_SOLVED)")
	arena.tick(0.016)
	check(arena.state == PandaGoArena.STATE_BROKEN and arena.glyph.kind == &"po" and arena.panda.action == &"yang_weak" and won.size() == 1, "solved: 破 + panda yang_weak")
	check(not arena.game_on and arena.pulling and player.input_frozen, "board starts fading, Lan pulled back")
	arena.tick(PandaGoArena.PULL_TIME * 0.5)
	check(player.position.y < on_board_y and player.position.y > MirrorLake.STAND_Y and arena.board_alpha < 1.0, "mid-pull, board fading")
	arena.tick(PandaGoArena.PULL_TIME)
	check(not arena.planar and is_equal_approx(player.position.y, MirrorLake.STAND_Y) and not player.input_frozen and player.is_physics_processing(), "Lan back on the baseline, side view restored")
	check(not arena.is_board_present() and not arena.board_view.visible, "board gone")
	for code in [KEY_S, KEY_W, KEY_DOWN, KEY_UP]: held0[code] = true
	arena.tick(0.016)
	check(not arena.planar, "no board: cannot step onto it")
	held0.clear()
	side(MirrorLake.Side.YANG)
	scene.refresh_controls()
	var stones := arena.session.board.to_rows()
	player.defense_state = LanPlayer.DefenseState.NONE
	Input.action_press(&"parry")
	arena.tick(0.016)
	player._physics_process(1.0 / 60.0)
	Input.action_release(&"parry")
	check(not arena.planar and arena.session.board.to_rows() == stones and player.defense_state != LanPlayer.DefenseState.NONE, "no board: K places nothing and opens the normal parry")
	side(MirrorLake.Side.YIN)
	arena.tick(PandaGoArena.WEAK_SECONDS - arena.state_clock - 0.05)
	check(arena.state == PandaGoArena.STATE_BROKEN and arena.glyph.visible and not arena.panda_yin, "破 and weakness last WEAK_SECONDS")
	arena.tick(0.1)
	check(arena.state == PandaGoArena.STATE_YIN and arena.glyph.kind == &"moqi" and arena.panda_yin and arena.panda.action == &"yang_to_yin", "after 5 s: 破 gone (yin skill glyph instead), panda yang_to_yin")
	# --- 阴：一招（墨起云生），0 次弹反 -> 直接回阳，换更难的题
	check(arena.yin_skill == 0 and arena.glyph.visible and arena.glyph.kind == &"moqi", "first yin: 墨起云生 glyph being written")
	run_yin()
	check(arena.state == PandaGoArena.STATE_WRITING and not arena.panda_yin and arena.panda.action == &"yin_to_yang" and arena.glyph.kind == &"yi" and arena.round_index == 1, "yin over: yin_to_yang, 弈 rewritten, round 2")
	check(not arena.game_on and not arena.board_view.visible, "no board until the new 弈 is written")
	arena.tick(arena.glyph.draw_duration)
	var p0 := GoEndgamePuzzles.get_puzzle(PandaGoArena.puzzle_for_round(0))
	check(arena.game_on and arena.session.puzzle_index == PandaGoArena.puzzle_for_round(1) and int(arena.session.puzzle.max_moves) >= int(p0.max_moves) and arena.session.puzzle_index != PandaGoArena.puzzle_for_round(0), "round 2: next, harder puzzle")
	# --- 熊猫回白子：yang_place_stone，白子在落子帧出现
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	arena.enter_planar()
	var whites := arena.session.board.count(GoEndgameBoard.WHITE)
	var far := Vector2i(4, 4)
	player.position = arena.board_world_origin() + arena.board_view.point_local(far)
	res = arena.place_at_feet()
	check(res.ok and arena.session.phase == GoEndgameSession.PHASE_REPLYING and arena.panda.action == &"yang_place_stone", "panda answers with yang_place_stone")
	var hit := float(PandaGoArena.STONE_FRAME) / float(PandaActions.spec(&"yang_place_stone").fps)
	arena.tick(hit - 0.05)
	check(arena.session.board.count(GoEndgameBoard.WHITE) == whites, "white stone not yet before the hit frame")
	arena.tick(0.1)
	check(arena.session.board.count(GoEndgameBoard.WHITE) == whites + 1, "white stone appears on the hit frame")
	arena.panda.tick(2.0)
	check(arena.panda.action == &"yang_idle", "yang_place_stone returns to yang_idle")
	# --- 失败（步数用完）：困 + 大笑（结果动作优先于落子动作）-> 大笑结束字消失 -> 切阴
	var next := Vector2i(-1, -1)
	for m in [Vector2i(4, 3), Vector2i(3, 4), Vector2i(3, 3), Vector2i(4, 2)]:
		if arena.session.board.is_legal(GoEndgameBoard.BLACK, m.x, m.y): next = m; break
	player.position = arena.board_world_origin() + arena.board_view.point_local(next)
	res = arena.place_at_feet()
	arena.tick(hit + 0.05)
	check(arena.session.phase == GoEndgameSession.PHASE_FAILED and arena.state == PandaGoArena.STATE_TRAPPED, "out of moves: session failed -> trapped")
	check(arena.glyph.kind == &"kun" and arena.panda.action == &"yang_victory" and lost == [arena.session.settle_reason], "困 + yang_victory (overrides yang_place_stone)")
	check(not arena.game_on and arena.pulling, "board fades, Lan pulled back")
	arena.tick(arena.victory_seconds() - arena.state_clock - 0.05)
	check(arena.state == PandaGoArena.STATE_TRAPPED and arena.glyph.visible, "困 stays while the laugh plays")
	arena.tick(0.1)
	check(arena.state == PandaGoArena.STATE_YIN and arena.glyph.kind == &"bizou" and arena.panda_yin and not arena.planar and not arena.is_board_present(), "laugh over: 困 gone, yin, Lan on baseline, no board")
	# --- 阳 20 秒超时（从阳开始就计时）-> 困
	check(arena.yin_skill == 1 and arena.glyph.kind == &"bizou", "second yin: 笔走龙蛇")
	run_yin()
	check(arena.state == PandaGoArena.STATE_WRITING and arena.round_index == 2, "round 3 starts")
	arena.tick(PandaGoArena.YANG_SECONDS - 0.1)
	check(arena.state == PandaGoArena.STATE_PLAYING and arena.game_on, "still playing just before 20 s from yang start")
	arena.tick(0.2)
	check(arena.state == PandaGoArena.STATE_TRAPPED and arena.glyph.kind == &"kun" and arena.panda.action == &"yang_victory" and lost.back() == PandaGoArena.REASON_YANG_TIMEOUT and not arena.game_on, "yang time up -> 困 + laugh, board fades")
	arena.tick(arena.victory_seconds() + 0.01)
	check(arena.state == PandaGoArena.STATE_YIN, "-> yin")
	# --- 题序
	var order := PandaGoArena.difficulty_order()
	var sorted_ok := true
	for k in range(1, order.size()):
		if int(GoEndgamePuzzles.get_puzzle(order[k]).max_moves) < int(GoEndgamePuzzles.get_puzzle(order[k - 1]).max_moves): sorted_ok = false
	check(order.size() == GoEndgamePuzzles.count() and sorted_ok, "difficulty order covers the library, moves non-decreasing")
	var n := order.size()
	check(PandaGoArena.puzzle_for_round(n) == order[n - 2] and PandaGoArena.puzzle_for_round(n + 1) == order[n - 1] and PandaGoArena.puzzle_for_round(n + 2) == order[n - 2], "past the library: cycle the hardest two")
	# 阴时棋盘平面移动与镜湖同一颠倒规则（MirrorLake.controls_inverted），凝心镜抵消；与熊猫阶段无关。
	var held := scene.control_inverter.real_held
	held.clear()
	held[KEY_D] = true
	held[KEY_W] = true
	side(MirrorLake.Side.YIN)
	mem.mirror = false
	check(scene.controls_inverted() and arena.planar_input().is_equal_approx(Vector2(-1, 1).normalized()), "yin, no 凝心镜: board D+W read as left+down (all four inverted)")
	arena.set_panda_yin(true)
	check(arena.planar_input().is_equal_approx(Vector2(-1, 1).normalized()), "inversion independent of panda phase")
	arena.set_panda_yin(false)
	mem.mirror = true
	check(not scene.controls_inverted() and arena.planar_input().is_equal_approx(Vector2(1, -1).normalized()), "yin + 凝心镜 equipped: board not inverted")
	mem.mirror = false
	side(MirrorLake.Side.YANG)
	check(not scene.controls_inverted() and arena.planar_input().is_equal_approx(Vector2(1, -1).normalized()), "yang: board not inverted")
	held.clear()
	held[KEY_LEFT] = true
	held[KEY_DOWN] = true
	side(MirrorLake.Side.YIN)
	check(arena.planar_input().is_equal_approx(Vector2(1, -1).normalized()), "yin: arrow keys inverted too")
	held.clear()
	# 熊猫水平翻转面朝左（棋盘/玩家），位置与脚底锚点不变。
	check(arena.panda.scale.x < 0.0 and is_equal_approx(arena.panda.position.x, PandaGoArena.PANDA_X), "panda mirrored to face left, still at PANDA_X")
	for id in [&"yang_idle", &"yang_to_yin", &"yin_idle", &"yin_to_yang"]:
		arena.panda.play_action(id)
		var spr := arena.panda.animated_sprite
		var foot := spr.get_global_transform() * (spr.offset + PandaActions.foot_anchor(PandaActions.spec(id)))
		check(foot.distance_to(arena.panda.global_position) < 0.01, "feet stay on the panda origin after flip: %s" % id)
	arena.panda.play_action(&"yang_idle")
	# 入口区不再例外：阴且无凝心镜即颠倒，凝心镜抵消。
	var keep_x := player.position.x
	player.position.x = MirrorLake.SPAWN_X
	side(MirrorLake.Side.YIN)
	mem.mirror = false
	scene.refresh_controls()
	check(MirrorLake.zone_at(player.position.x) == MirrorLake.Zone.ENTRY and scene.controls_inverted() and scene.control_inverter.inverted, "entry zone, yin, no 凝心镜: inverted")
	mem.mirror = true
	scene.refresh_controls()
	check(not scene.controls_inverted() and not scene.control_inverter.inverted, "entry zone, yin + 凝心镜: not inverted")
	mem.mirror = false
	player.position.x = keep_x
	scene.refresh_controls()
	print("\n结果：%d 项检查，%d 项失败" % [checks, failures])
	quit(1 if failures > 0 else 0)
