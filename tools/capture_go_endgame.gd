extends SceneTree
## Screenshots of the panda yang-state go endgame preview: every puzzle (initial, after the player's move, after
## the panda's reply, settlement) plus the window warning, timeout, yin-required prompt and the debug-room entry.
## Usage: godot --path <game> --script <this> -- <output_dir>   (needs a real window, not --headless)

const B := GoEndgameBoard.BLACK
const W := GoEndgameBoard.WHITE

var preview: GoEndgamePreview
var out_dir := ""
var shots := 0

func _initialize() -> void:
	call_deferred("run")

func grab(name: String) -> void:
	preview.refresh()
	preview.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	shots += 1

func open(index: int) -> void:
	preview.open_puzzle(index)
	preview.step(0.05)

func play(x: int, y: int) -> void:
	preview.cursor = Vector2i(x, y)
	preview.place_at_cursor()

func settle_reply() -> void:
	preview.step(0.35)

## First winning move for the player (brute force against the panda's rule), used for the follow-up moves of a line.
func winning(board: GoEndgameBoard, moves: int, responds: bool) -> Vector2i:
	for m in board.legal_moves(B):
		if wins(board, m, moves, responds): return m
	return board.legal_moves(B)[0]

func wins(board: GoEndgameBoard, m: Vector2i, moves: int, responds: bool) -> bool:
	var result := board.would_play(B, m.x, m.y)
	if int(result.captured_groups) > 0: return true
	if moves <= 1: return false
	var next: GoEndgameBoard = result.board
	if responds: GoEndgameOpponent.play_reply(next)
	for n in next.legal_moves(B):
		if wins(next, n, moves - 1, responds): return true
	return false

func follow_up() -> void:
	var s := preview.session
	var m := winning(s.board, s.moves_left(), s.puzzle.panda_responds)
	play(m.x, m.y)

func run() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	preview = (load("res://scenes/bosses/panda/go_endgame_preview.tscn") as PackedScene).instantiate() as GoEndgamePreview
	preview.manual_clock = true
	preview.exit_scene = ""
	root.add_child(preview)
	current_scene = preview
	await process_frame
	await process_frame
	# 1 guide
	open(0)
	await grab("01_guide_1_initial")
	play(3, 2)
	await grab("01_guide_2_after_move")
	preview.step(0.9)
	await grab("01_guide_3_settle_short_window")
	# 2 choice: wrong direction, then right direction
	open(1)
	await grab("02_choice_a1_initial")
	play(0, 0)
	preview.step(0.1)
	await grab("02_choice_a2_wrong_after_move")
	preview.step(0.6)
	await grab("02_choice_a3_wrong_panda_escapes")
	follow_up()
	preview.step(1.0)
	await grab("02_choice_a4_wrong_settle_no_window")
	open(1)
	play(2, 0)
	preview.step(0.1)
	await grab("02_choice_b2_right_after_move")
	preview.step(0.7)
	await grab("02_choice_b3_right_panda_cannot_escape")
	follow_up()
	preview.step(0.9)
	await grab("02_choice_b4_right_settle_short_window")
	# 3 double atari
	open(2)
	await grab("03_double_1_initial")
	play(3, 2)
	preview.step(0.1)
	await grab("03_double_2_after_move")
	preview.step(0.7)
	await grab("03_double_3_panda_saves_one")
	follow_up()
	preview.step(0.9)
	await grab("03_double_4_settle_long_window")
	# 4 chase
	open(3)
	await grab("04_chase_1_initial")
	play(2, 2)
	preview.step(0.1)
	await grab("04_chase_2_after_move")
	preview.step(0.7)
	await grab("04_chase_3_panda_runs_to_edge")
	follow_up()
	preview.step(0.8)
	follow_up()
	preview.step(0.9)
	await grab("04_chase_4_settle")
	# 5 trap: greedy atari, then the right order
	open(4)
	await grab("05_trap_a1_initial")
	play(1, 2)
	preview.step(0.1)
	await grab("05_trap_a2_greedy_after_move")
	preview.step(0.7)
	await grab("05_trap_a3_panda_captures_and_escapes")
	follow_up()
	preview.step(1.0)
	follow_up()
	preview.step(1.0)
	await grab("05_trap_a4_greedy_settle_no_window")
	open(4)
	play(0, 2)
	preview.step(0.1)
	await grab("05_trap_b2_save_first_after_move")
	preview.step(0.7)
	await grab("05_trap_b3_panda_has_no_reply")
	follow_up()
	preview.step(0.8)
	follow_up()
	preview.step(0.9)
	await grab("05_trap_b4_save_first_settle")
	# window warning, timeout, yin required
	open(1)
	preview.session.time_left = 1.6
	preview.step(0.9)
	await grab("06_warning_brush_raised")
	preview.step(1.0)
	await grab("06_timeout_parry_needed")
	open(0)
	preview.handle_key(KEY_TAB)
	preview.handle_key(KEY_ENTER)
	await grab("06_yang_cannot_place_need_yin")
	preview.step(2.1)
	preview.handle_key(KEY_TAB)
	await grab("06_back_to_yin")
	preview.queue_free()
	# the entry in the panda debug room
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.player.set_physics_process(false)
	room.boss_picker.item_selected.emit(9)
	await process_frame
	await process_frame
	room.adapter.boss.set_process(false)
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("07_debug_room_entry_button.png"))
	shots += 1
	print("Captured %d go endgame screenshots" % shots)
	quit()
