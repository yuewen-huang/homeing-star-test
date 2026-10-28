extends SceneTree
## Panda BOSS yang-state go endgame: rules, puzzle bank (brute force), panda reply, session / settlement
## tiers and the preview scene. Headless: godot --headless --path <game> --script <this>.

const B := GoEndgameBoard.BLACK
const W := GoEndgameBoard.WHITE

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func board_of(rows: Array) -> GoEndgameBoard:
	return GoEndgameBoard.from_rows(rows)

func puzzle_board(index: int) -> GoEndgameBoard:
	return GoEndgamePuzzles.build_board(index)

func run() -> void:
	test_rules()
	test_opponent()
	test_puzzle_bank()
	test_choice_wrong_direction()
	test_double_atari()
	test_trap()
	test_symmetries()
	test_session()
	await test_scene()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ------------------------------------------------------------ brute force helpers

## Player's winning first moves: some black line captures a white group within `moves` stones, with the
## panda answering by its rule (or not answering when `responds` is false).
func winning_firsts(board: GoEndgameBoard, moves: int, responds: bool) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for m in board.legal_moves(B):
		if first_wins(board, m, moves, responds): out.append(m)
	return out

func first_wins(board: GoEndgameBoard, m: Vector2i, moves: int, responds: bool) -> bool:
	var result := board.would_play(B, m.x, m.y)
	if int(result.captured_groups) > 0: return true
	if moves <= 1: return false
	var next: GoEndgameBoard = result.board
	if responds: GoEndgameOpponent.play_reply(next)
	for n in next.legal_moves(B):
		if first_wins(next, n, moves - 1, responds): return true
	return false

## True when black still wins within `moves` stones whatever white does (any legal reply, or none) after m.
func first_wins_against_any_defence(board: GoEndgameBoard, m: Vector2i, moves: int) -> bool:
	var result := board.would_play(B, m.x, m.y)
	if int(result.captured_groups) > 0: return true
	if moves <= 1: return false
	var next: GoEndgameBoard = result.board
	var replies: Array = [null]
	for w in next.legal_moves(W): replies.append(w)
	for reply in replies:
		var after := next.duplicate()
		if reply != null: after.play(W, reply.x, reply.y)
		var any := false
		for n in after.legal_moves(B):
			if first_wins_against_any_defence(after, n, moves - 1):
				any = true
				break
		if not any: return false
	return true

func transform_point(p: Vector2i, t: int, n: int) -> Vector2i:
	var q := p
	if t >= 4: q = Vector2i(n - 1 - q.x, q.y)
	for _i in t % 4: q = Vector2i(n - 1 - q.y, q.x)
	return q

func transform_board(board: GoEndgameBoard, t: int) -> GoEndgameBoard:
	var out := GoEndgameBoard.create(board.size)
	for y in board.size:
		for x in board.size:
			var q := transform_point(Vector2i(x, y), t, board.size)
			out.set_at(q.x, q.y, board.get_at(x, y))
	return out

# ------------------------------------------------------------ rules

func test_rules() -> void:
	var rows := [". # . . .", "# O # . .", ". # . . .", ". . . . .", ". . . . O"]
	check(board_of(rows).to_rows() == rows and board_of(rows).size == 5, "ASCII rows parse and print back unchanged")
	check(board_of(["O . . . .", ". . . . .", ". . . . .", ". . . . .", ". . . . ."]).group_at(0, 0).liberties.size() == 2, "a corner stone has 2 liberties")
	check(board_of([". O . . .", ". . . . .", ". . . . .", ". . . . .", ". . . . ."]).group_at(1, 0).liberties.size() == 3, "an edge stone has 3 liberties")
	check(board_of([". . . . .", ". . . . .", ". . O . .", ". . . . .", ". . . . ."]).group_at(2, 2).liberties.size() == 4, "a centre stone has 4 liberties")
	var chain := board_of([". . . . .", ". # # . .", ". . . . .", ". . . . .", ". . . . ."])
	check(chain.group_at(1, 1).stones.size() == 2 and chain.group_at(2, 1).liberties.size() == 6, "a two-stone chain shares its 6 liberties")
	check(chain.group_at(0, 0).stones.is_empty() and chain.groups(B).size() == 1, "an empty point has no group; one black group")
	var atari := board_of([". # . . .", "# O . . .", ". # . . .", ". . . . .", ". . . . ."])
	check(atari.atari_groups(W).size() == 1 and atari.atari_groups(W)[0].liberties == [Vector2i(2, 1)], "a group with one liberty is in atari (its liberty is C2)")
	check(atari.atari_stone_count(W) == 1 and atari.atari_stone_count(B) == 0 and atari.min_liberties(W) == 1, "atari stone counts and weakest liberty count")
	var hit := atari.would_play(B, 2, 1)
	check(hit.ok and hit.captured_groups == 1 and hit.captured == [Vector2i(1, 1)], "filling the last liberty captures the group")
	check(atari.get_at(2, 1) == GoEndgameBoard.EMPTY and atari.get_at(1, 1) == W, "would_play leaves the original board untouched")
	var played := atari.duplicate()
	played.play(B, 2, 1)
	check(played.get_at(1, 1) == GoEndgameBoard.EMPTY and played.get_at(2, 1) == B and played.group_at(2, 1).liberties.size() == 4, "play() removes captured stones, places the mover and frees liberties")
	var wall := board_of([". # # . .", "# O O # .", ". # . . .", ". . . . .", ". . . . ."])
	var duo := wall.would_play(B, 2, 2)
	check(duo.ok and duo.captured.size() == 2 and duo.captured_groups == 1, "a two-stone group is captured as ONE group")
	var split := board_of([". # # # .", "# O . O #", ". # # # .", ". . . . .", ". . . . ."])
	var two_groups := split.would_play(B, 2, 1)
	check(two_groups.ok and two_groups.captured_groups == 2 and two_groups.captured.size() == 2, "one move can capture two groups at once")
	var hole := board_of([". O . . .", "O . O . .", ". O . . .", ". . . . .", ". . . . ."]).would_play(B, 1, 1)
	check(not hole.ok and hole.reason == &"suicide", "suicide is illegal")
	var eat := board_of(["O . O . .", "# O . . .", ". . . . .", ". . . . .", ". . . . ."]).would_play(B, 1, 0)
	check(eat.ok and eat.captured == [Vector2i(0, 0)], "a move with no liberties of its own is legal when it captures first")
	var ko := board_of([". # O . .", "# O . O .", ". # O . .", ". . . . .", ". . . . ."])
	ko.play(B, 2, 1)
	var back := ko.would_play(W, 1, 1)
	check(back.ok and back.captured == [Vector2i(2, 1)], "no ko rule: immediate recapture is legal")
	check(not atari.would_play(B, 1, 1).ok and atari.would_play(B, 1, 1).reason == &"occupied", "an occupied point is illegal")
	check(not atari.would_play(B, 5, 0).ok and atari.would_play(B, 5, 0).reason == &"out", "a point off the board is illegal")
	check(GoEndgameBoard.create(5).legal_moves(B).size() == 25 and GoEndgameBoard.create(9).size == GoEndgameBoard.MAX_SIZE, "empty 5x5 has 25 legal moves; boards are capped at 5x5")

# ------------------------------------------------------------ panda reply

func test_opponent() -> void:
	var quiet := GoEndgameOpponent.respond(GoEndgameBoard.create(5))
	check(not quiet.has_move and quiet.kind == &"pass" and quiet.reason == &"quiet", "no white stones: the panda does not move (quiet)")
	var extend := GoEndgameOpponent.respond(board_of([". O . . .", ". . . . .", ". # . . .", ". . . . .", ". . . . ."]))
	check(extend.kind == &"extend" and extend.move == Vector2i(2, 0), "with nothing to attack the panda extends (C1: ties on liberties go to the point farther from the centre)")
	var counter := GoEndgameOpponent.respond(board_of(["# . . . .", ". . . . .", ". . . . .", ". . . . .", ". . . . ."]))
	check(counter.kind == &"counter_atari" and counter.move == Vector2i(1, 0), "a lone black corner stone gets put in atari (B1 beats A2 by row-major order)")
	var take := GoEndgameOpponent.respond(board_of(["# O . . .", ". . . . .", ". . . . .", ". . . . .", ". . . . ."]))
	check(take.kind == &"capture" and take.move == Vector2i(0, 1) and take.captured == 1, "a black stone in atari is captured")
	var l2 := puzzle_board(1)
	var right := l2.duplicate()
	right.play(B, 2, 0)
	var stuck := GoEndgameOpponent.respond(right)
	check(not stuck.has_move and stuck.reason == &"no_escape", "L2 after the right atari: the panda has no way out (no_escape)")
	var wrong := l2.duplicate()
	wrong.play(B, 0, 0)
	var out := GoEndgameOpponent.respond(wrong)
	check(out.kind == &"escape" and out.move == Vector2i(0, 1) and out.captured == 1, "L2 after the corner atari: the panda captures the corner stone and escapes (A2)")
	var again := GoEndgameOpponent.respond(wrong)
	check(again.move == out.move and again.kind == out.kind, "the reply is deterministic")
	var bad := 0
	var tested := 0
	for i in GoEndgamePuzzles.count():
		var start := puzzle_board(i)
		for m in start.legal_moves(B):
			var after: GoEndgameBoard = start.would_play(B, m.x, m.y).board
			var base := GoEndgameOpponent.respond(after)
			if base.kind == &"counter_atari": continue # a lone stone's two mirror-image points are an unavoidable exact tie
			for t in 8:
				var moved := GoEndgameOpponent.respond(transform_board(after, t))
				tested += 1
				var same: bool = moved.has_move == base.has_move and moved.kind == base.kind
				if same and base.has_move: same = moved.move == transform_point(base.move, t, 5)
				if not same: bad += 1
	check(bad == 0, "the panda's reply to every first move of every puzzle is the same under all 8 symmetries (%d cases, %d differ; mirror-image counter_atari ties excluded)" % [tested, bad])

# ------------------------------------------------------------ puzzle bank

func test_puzzle_bank() -> void:
	check(GoEndgamePuzzles.count() == 5, "five puzzles: guide, choice, double atari, chase, trap")
	var ids := {}
	for i in GoEndgamePuzzles.count():
		var puzzle := GoEndgamePuzzles.get_puzzle(i)
		var board := puzzle_board(i)
		ids[puzzle.id] = true
		var dead := 0
		for color in [B, W]:
			for group in board.groups(color):
				if group.liberties.is_empty(): dead += 1
		check(board.size <= 5 and board.count(W) >= 1 and board.count(B) >= 1 and dead == 0, "%s: at most 5x5, both colours present, no dead group at the start" % puzzle.id)
		var solution: Vector2i = puzzle.solution
		check(board.is_legal(B, solution.x, solution.y), "%s: the designed first move %s is legal" % [puzzle.id, GoEndgamePuzzles.point_label(solution)])
		var wins := winning_firsts(board, int(puzzle.max_moves), bool(puzzle.panda_responds))
		check(wins == [solution], "%s: brute force finds exactly one winning first move, the designed %s (found %s)" % [puzzle.id, GoEndgamePuzzles.point_label(solution), wins])
		if int(puzzle.max_moves) > 1:
			check(winning_firsts(board, int(puzzle.max_moves) - 1, bool(puzzle.panda_responds)).is_empty(), "%s: one move fewer is not enough (the move budget is tight)" % puzzle.id)
		var hint: Vector2i = puzzle.hint
		check(hint == GoEndgamePuzzles.NO_POINT or hint == solution, "%s: a vermilion hint, when present, marks the answer" % puzzle.id)
		check(first_wins_against_any_defence(board, solution, int(puzzle.max_moves)), "%s: the designed first move wins against EVERY white defence, not only the panda's rule" % puzzle.id)
	check(ids.size() == 5, "puzzle ids are unique")
	var guide := puzzle_board(0)
	check(guide.atari_groups(W).size() == 1 and guide.atari_groups(W)[0].liberties == [GoEndgamePuzzles.get_puzzle(0).hint], "guide: one white group in atari, its liberty is the hint point")
	check(not GoEndgamePuzzles.get_puzzle(0).panda_responds and not GoEndgamePuzzles.get_puzzle(0).timed, "guide: the panda does not respond and there is no timer")
	for i in range(1, 5): check(GoEndgamePuzzles.get_puzzle(i).panda_responds and GoEndgamePuzzles.get_puzzle(i).timed, "%s: the panda responds and the window is timed" % GoEndgamePuzzles.get_puzzle(i).id)

func test_choice_wrong_direction() -> void:
	var board := puzzle_board(1)
	check(board.atari_groups(W).is_empty() and board.groups(W)[0].liberties.size() == 2, "choice: the white stone starts with 2 liberties (not yet in atari)")
	var atari_points: Array[Vector2i] = []
	for m in board.legal_moves(B):
		var r := board.would_play(B, m.x, m.y)
		if r.captured_groups == 0 and not (r.board as GoEndgameBoard).atari_groups(W).is_empty(): atari_points.append(m)
	check(atari_points.size() == 2 and atari_points.has(Vector2i(0, 0)) and atari_points.has(Vector2i(2, 0)), "choice: exactly two atari directions, A1 and C1")
	check(first_wins(board, Vector2i(2, 0), 2, true) and not first_wins(board, Vector2i(0, 0), 2, true), "choice: C1 wins, A1 really fails (brute force, panda answers)")
	var wrong: GoEndgameBoard = board.would_play(B, 0, 0).board
	var reply := GoEndgameOpponent.play_reply(wrong)
	check(reply.has_move and wrong.get_at(0, 1) == W and wrong.get_at(0, 0) == GoEndgameBoard.EMPTY, "choice: after A1 the panda's visible escape stone is A2 and it removes your corner stone")
	check(wrong.groups(W)[0].liberties.size() >= 2 and winning_firsts(wrong, 1, true).is_empty(), "choice: the escaped white group has 2+ liberties and the last move cannot capture it")

func test_double_atari() -> void:
	var board := puzzle_board(2)
	check(board.atari_groups(W).is_empty() and board.groups(W).size() == 2, "double atari: two white groups, neither in atari at the start")
	var after: GoEndgameBoard = board.would_play(B, 3, 2).board
	check(after.atari_groups(W).size() == 2, "double atari: D3 puts BOTH white groups in atari")
	var every_reply_loses := true
	var replies: Array = [null]
	for w in after.legal_moves(W): replies.append(w)
	for reply in replies:
		var b := after.duplicate()
		if reply != null: b.play(W, reply.x, reply.y)
		var can_capture := false
		for m in b.legal_moves(B):
			if b.would_play(B, m.x, m.y).captured_groups > 0: can_capture = true
		if not can_capture: every_reply_loses = false
	check(every_reply_loses, "double atari: whatever the panda plays (%d replies incl. pass), black can still capture a group" % replies.size())
	var line := after.duplicate()
	var reply2 := GoEndgameOpponent.play_reply(line)
	check(reply2.kind == &"escape" and line.atari_groups(W).size() == 1, "double atari: the panda saves only one group (%s), the other stays in atari" % GoEndgamePuzzles.point_label(reply2.move))
	check(first_wins(board, Vector2i(3, 2), 2, true), "double atari: D3 then a capture wins")
	var single: GoEndgameBoard = board.would_play(B, 1, 2).board
	check(single.atari_groups(W).size() == 1 and not first_wins(board, Vector2i(1, 2), 2, true), "double atari: a single atari (B3) is saved by the panda and loses")

func test_trap() -> void:
	var board := puzzle_board(4)
	check(board.atari_groups(B).size() == 1 and board.atari_groups(W).is_empty(), "trap: your two stones are in atari and the white group is not")
	var greedy: Array[Vector2i] = []
	for m in board.legal_moves(B):
		var r := board.would_play(B, m.x, m.y)
		if r.captured_groups == 0 and not (r.board as GoEndgameBoard).atari_groups(W).is_empty(): greedy.append(m)
	check(greedy.size() == 2, "trap: two ways to atari the white group (the greedy moves)")
	for m in greedy:
		var after: GoEndgameBoard = board.would_play(B, m.x, m.y).board
		var reply := GoEndgameOpponent.play_reply(after)
		check(reply.kind == &"escape" and reply.move == Vector2i(0, 2) and reply.captured == 2, "trap: greedy atari %s lets the panda escape by capturing your stones at A3" % GoEndgamePuzzles.point_label(m))
		check(winning_firsts(after, 2, true).is_empty() and not first_wins(board, m, 3, true), "trap: after greedy atari %s black can no longer win" % GoEndgamePuzzles.point_label(m))
	var save: GoEndgameBoard = board.would_play(B, 0, 2).board
	check(save.atari_groups(B).is_empty() and GoEndgameOpponent.respond(save).kind == &"pass", "trap: saving first (A3) takes you out of atari and the panda has no useful reply")
	check(first_wins(board, Vector2i(0, 2), 3, true) and winning_firsts(board, 3, true) == [Vector2i(0, 2)], "trap: save first wins, capture first loses (only A3 wins)")

func test_symmetries() -> void:
	for i in GoEndgamePuzzles.count():
		var puzzle := GoEndgamePuzzles.get_puzzle(i)
		var ok := true
		var detail := ""
		for t in 8:
			var board := transform_board(puzzle_board(i), t)
			var want := transform_point(puzzle.solution, t, board.size)
			var wins := winning_firsts(board, int(puzzle.max_moves), bool(puzzle.panda_responds))
			if wins != [want]:
				ok = false
				detail += " t%d:%s" % [t, wins]
		check(ok, "%s: still exactly one winning first move under all 8 rotations / mirrors%s" % [puzzle.id, detail])

# ------------------------------------------------------------ session

func play_line(session: GoEndgameSession) -> void:
	while not session.is_settled():
		var firsts := winning_firsts(session.board, session.moves_left(), bool(session.puzzle.panda_responds))
		if firsts.is_empty(): break
		session.try_place(firsts[0].x, firsts[0].y)
		session.advance(session.reply_delay + 0.01)

func test_session() -> void:
	var expected := [GoEndgameSession.TIER_SHORT, GoEndgameSession.TIER_SHORT, GoEndgameSession.TIER_LONG, GoEndgameSession.TIER_SHORT, GoEndgameSession.TIER_SHORT]
	for i in 5:
		var session := GoEndgameSession.new(i)
		var actions: Array[StringName] = []
		session.panda_action_requested.connect(func(a: StringName) -> void: actions.append(a))
		play_line(session)
		check(session.phase == GoEndgameSession.PHASE_SOLVED and session.tier == expected[i] and session.settle_reason == &"captured", "puzzle %d solved by its designed line: tier %s" % [i + 1, session.tier])
		check(not actions.is_empty() and actions.back() == &"yang_weak" and session.moves_used <= session.max_moves, "puzzle %d ends with the panda's yang_weak (actions %s)" % [i + 1, actions])
	var s := GoEndgameSession.new(2)
	s.try_place(3, 2)
	check(s.double_atari and s.phase == GoEndgameSession.PHASE_REPLYING and s.weak_window_seconds() == 0.0, "double atari is flagged on the move and the panda is replying")
	s.advance(0.7)
	check(s.last_reply.kind == &"escape" and s.phase == GoEndgameSession.PHASE_PLAYING and s.moves_left() == 1, "the reply lands after the delay (0.6 s placeholder)")
	var first := winning_firsts(s.board, 1, true)[0]
	s.try_place(first.x, first.y)
	check(s.tier == GoEndgameSession.TIER_LONG and is_equal_approx(s.weak_window_seconds(), s.weak_long_seconds), "double atari then capture = long weak window (8 s placeholder)")
	var f := GoEndgameSession.new(1)
	var f_actions: Array[StringName] = []
	f.panda_action_requested.connect(func(a: StringName) -> void: f_actions.append(a))
	f.try_place(0, 0)
	check(f_actions == [&"yang_place_stone"], "the panda starts placing as soon as your stone lands")
	f.advance(1.0)
	f.try_place(3, 3)
	check(f.phase == GoEndgameSession.PHASE_REPLYING or f.phase == GoEndgameSession.PHASE_FAILED, "last stone placed: the panda answers / the puzzle settles")
	f.advance(1.0)
	check(f.phase == GoEndgameSession.PHASE_FAILED and f.tier == GoEndgameSession.TIER_NONE and f.settle_reason == &"out_of_moves" and f.weak_window_seconds() == 0.0, "out of moves: failed, no weak window")
	check(f_actions.back() == &"yang_victory" and f.black_stones_lost >= 1, "failure plays yang_victory; the lost stones are only counted, no HP")
	check(f.try_place(4, 4).reason == GoEndgameSession.BLOCK_SETTLED, "a settled puzzle accepts no more stones")
	f.reset()
	check(f.phase == GoEndgameSession.PHASE_PLAYING and f.moves_used == 0 and f.board.to_rows() == puzzle_board(1).to_rows(), "reset restores the puzzle")
	var g := GoEndgameSession.new(0)
	check(g.player_is_yin and g.placement_blocked_reason() == &"", "the player starts in yin and may place")
	check(g.set_player_yin(false) and not g.player_is_yin and g.placement_blocked_reason() == GoEndgameSession.BLOCK_NEED_YIN, "in yang the placement is blocked with need_yin")
	var blocked := g.try_place(3, 2)
	check(not blocked.ok and blocked.reason == GoEndgameSession.BLOCK_NEED_YIN and g.moves_used == 0 and g.board.get_at(3, 2) == GoEndgameBoard.EMPTY, "a blocked placement changes nothing")
	check(not g.set_player_yin(true) and not g.can_switch(), "switching back is blocked during the cooldown (2 s placeholder)")
	g.advance(1.0)
	check(not g.set_player_yin(true), "still cooling down after 1 s")
	g.advance(1.1)
	check(g.set_player_yin(true) and g.try_place(3, 2).ok, "after the cooldown the player is back in yin and can place")
	check(not g.controls_inverted and g.map_direction(Vector2i(1, 0)) == Vector2i(1, 0), "cursor directions are not inverted by default")
	g.controls_inverted = true
	check(g.map_direction(Vector2i(1, 0)) == Vector2i(-1, 0) and g.map_direction(Vector2i(0, -1)) == Vector2i(0, 1), "the inversion flag flips both axes")
	var t := GoEndgameSession.new(1)
	var warnings := [0]
	var settles: Array[StringName] = []
	t.warning_started.connect(func() -> void: warnings[0] += 1)
	t.settled.connect(func(_tier: StringName, reason: StringName) -> void: settles.append(reason))
	check(t.timed and is_equal_approx(t.time_left, 30.0), "timed puzzles start with the 30 s window (placeholder)")
	t.advance(28.9)
	check(not t.warning and warnings[0] == 0, "no warning more than 1 s before the flip")
	t.advance(0.2)
	check(t.warning and warnings[0] == 1 and t.phase == GoEndgameSession.PHASE_PLAYING, "the panda raises its brush 1 s before the flip")
	t.advance(0.5)
	check(warnings[0] == 1, "the warning fires once")
	t.advance(0.5)
	check(t.phase == GoEndgameSession.PHASE_FAILED and t.settle_reason == &"timeout" and t.tier == GoEndgameSession.TIER_NONE and settles == [&"timeout"], "window out: timeout, no weak window")
	check(t.needs_parry() and t.last_action == &"yang_to_yin", "a player still in yin must switch back to yang to parry; the panda plays yang_to_yin")
	t.advance(2.1)
	t.set_player_yin(false)
	check(not t.needs_parry(), "after switching to yang the parry is no longer needed")
	var u := GoEndgameSession.new(0)
	u.advance(500.0)
	check(u.phase == GoEndgameSession.PHASE_PLAYING and not u.warning, "the guide puzzle has no timer")
	var late := GoEndgameSession.new(3)
	late.advance(29.0)
	late.try_place(2, 2)
	late.advance(0.5)
	check(late.phase == GoEndgameSession.PHASE_REPLYING or late.phase == GoEndgameSession.PHASE_PLAYING, "the clock keeps running while the panda answers")
	late.advance(1.0)
	check(late.settle_reason == &"timeout", "an unsolved puzzle times out even mid-line")

# ------------------------------------------------------------ preview scene

func test_scene() -> void:
	if not FileAccess.file_exists("res://scenes/bosses/panda/panda_boss.tscn"):
		print("SKIP scene checks (PandaBoss scene not in this project)")
		return
	var scene := load("res://scenes/bosses/panda/go_endgame_preview.tscn") as PackedScene
	check(scene != null, "go_endgame_preview.tscn loads")
	var preview := scene.instantiate() as GoEndgamePreview
	preview.manual_clock = true
	preview.exit_scene = ""
	root.add_child(preview)
	await process_frame
	await process_frame
	check(preview.panda != null and preview.panda.get_parent() == preview and preview.panda.action == &"yang_idle", "the real PandaBoss is embedded and idles")
	check(preview.title_label.text.contains("引导") and preview.goal_label.text.contains("1 手"), "HUD shows the puzzle name and goal")
	check(preview.status_label.text.contains("剩余落子 1 / 1") and preview.timer_label.text.contains("无计时"), "HUD shows moves left and that the guide is untimed")
	check(preview.handle_key(KEY_RIGHT) and preview.cursor == Vector2i(3, 2), "Right moves the cursor to D3")
	preview.handle_key(KEY_TAB)
	check(not preview.session.player_is_yin, "Tab switches the simulated player to yang")
	preview.handle_key(KEY_ENTER)
	check(preview.session.board.get_at(3, 2) == GoEndgameBoard.EMPTY and preview.prompt_label.text.contains("需切阴才能落子"), "in yang: Enter places nothing and shows the 需切阴才能落子 prompt")
	preview.handle_key(KEY_TAB)
	check(not preview.session.player_is_yin, "Tab during the cooldown does not switch")
	preview.step(2.5)
	preview.handle_key(KEY_TAB)
	check(preview.session.player_is_yin, "Tab switches back to yin after the cooldown")
	preview.handle_key(KEY_SPACE)
	check(preview.session.tier == GoEndgameSession.TIER_SHORT and preview.panda.action == &"yang_weak" and preview.settle_label.text.contains("短弱点窗口"), "placing the answer solves it: short window and the panda plays yang_weak")
	preview.handle_key(KEY_R)
	check(preview.session.moves_used == 0 and preview.panda.action == &"yang_idle", "R resets the puzzle and the panda")
	preview.handle_key(KEY_3)
	check(preview.session.puzzle_index == 2 and preview.handle_key(KEY_BRACKETRIGHT) and preview.session.puzzle_index == 3, "number keys and ] switch puzzles")
	preview.handle_key(KEY_1)
	preview.handle_key(KEY_BRACKETLEFT)
	check(preview.session.puzzle_index == 4, "[ wraps from the first to the last puzzle")
	preview.open_puzzle(2)
	preview.cursor = Vector2i(3, 2)
	preview.place_at_cursor()
	check(preview.session.phase == GoEndgameSession.PHASE_REPLYING and preview.panda.action == &"yang_place_stone", "a reply is pending and the panda plays yang_place_stone")
	preview.step(0.7)
	check(preview.session.phase == GoEndgameSession.PHASE_PLAYING and preview.event_label.text.contains("熊猫"), "the panda's reply is written to the event log")
	preview.open_puzzle(1)
	preview.session.time_left = 1.2
	preview.step(0.3)
	check(preview.session.warning and preview.timer_label.text.contains("举笔"), "the brush-raise warning shows in the HUD")
	preview.step(1.0)
	check(preview.session.settle_reason == &"timeout" and preview.prompt_label.text.contains("阳") and preview.settle_label.text.contains("无"), "timeout shows the parry prompt and no weak window")
	preview.handle_key(KEY_I)
	var before := preview.cursor
	preview.handle_key(KEY_LEFT)
	check(preview.session.controls_inverted and preview.cursor == before + Vector2i(1, 0), "I inverts the cursor directions")
	check(not preview.handle_key(KEY_F12), "unknown keys are not consumed")
	var panel_script := load("res://scripts/dev/panda_development_panel.gd") as GDScript
	check(panel_script.get_script_constant_map().get("GO_ENDGAME_SCENE", "") == "res://scenes/bosses/panda/go_endgame_preview.tscn", "the panda debug panel points at the preview scene")
	var panel = panel_script.new()
	var boss := (load("res://scenes/bosses/panda/panda_boss.tscn") as PackedScene).instantiate() as PandaBoss
	root.add_child(boss)
	root.add_child(panel)
	panel.setup(boss)
	check(panel.go_endgame_button != null and panel.go_endgame_button.text.contains("围棋残局"), "the panda debug panel has the go endgame entry button")
	panel.queue_free()
	boss.queue_free()
	preview.queue_free()
	await process_frame
