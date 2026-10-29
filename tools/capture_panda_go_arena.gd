extends SceneTree
## Screenshots of the Mirror Lake panda go fight: 弈 being written, 弈 done + board, 破 + weak, then the
## yin skills (glyph + strikes + warnings) 24-27 and the yang_weak settlement 28.
## Needs a real window. Usage: godot --path <game> -s <this> -- <output_dir>
var out_dir := ""
var scene: MirrorLake
var arena: PandaGoArena
func _initialize() -> void: call_deferred("run")
func grab(name: String) -> void:
	scene._process(0.0)
	scene.update_scroll()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
func step(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var d := minf(0.05, left)
		arena.tick(d)
		arena.panda.tick(d)
		left -= d
func run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else "user://panda_go"
	DirAccess.make_dir_recursive_absolute(out_dir)
	scene = load("res://scenes/levels/mirror_lake/mirror_lake.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	arena = scene.panda_arena
	var player := scene.player as LanPlayer
	player.position = Vector2(PandaGoArena.TRIGGER_X + 40, MirrorLake.STAND_Y)
	for i in 120:
		scene._process(1.0 / 60.0)
		await process_frame
	scene.set_process(false)
	arena.begin_yang()
	arena.game_on = false
	arena.board_alpha = 0.0
	arena.board_view.visible = false
	arena.tick(arena.glyph.draw_duration * 0.55)
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	await grab("20_yi_writing")
	arena.tick(arena.glyph.draw_duration + PandaGoArena.BOARD_FADE_TIME)
	player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
	arena.enter_planar()
	for i in 20: arena.move_planar(Vector2(0, 1), 0.05)
	arena.tick(0.0)
	await grab("21_yi_done_board")
	scene.advance_switch(3.0); scene.request_switch(); scene.advance_switch(3.0)
	var sol: Vector2i = arena.session.puzzle.solution
	player.position = arena.board_world_origin() + arena.board_view.point_local(sol)
	arena.place_at_feet()
	arena.tick(0.016)
	arena.tick(0.8)
	arena.panda.tick(0.8)
	scene.advance_switch(3.0); scene.request_switch(); scene.advance_switch(3.0)
	await grab("22_po_weak")
	player.combat_stats.refill_health_on_depletion = true
	var shots := [[0, "23_moqi_glyph", -0.08], [0, "24_moqi_surge", 8.15], [0, "24b_moqi_warn", 0.75], [1, "25_bizou_strokes", 2.95], [2, "26_pomo_splash", 3.2], [2, "26b_pomo_warn", 0.6], [3, "27_yibi_glyph", -0.08], [3, "27a_qianli_warn", 1.0], [3, "27b_qianli_hit2", 3.85], [3, "27c_qianli_hit4", 7.6], [3, "27d_qianli_full", 9.3]]
	for shot in shots:
		arena.round_index = shot[0]
		arena._enter_yin()
		player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
		step(arena.glyph.draw_duration + 0.06 + float(shot[2]))
		player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
		print(shot[1], " state ", arena.state, " glyph ", arena.glyph.kind, " clock ", arena.skills.clock, " panda ", arena.panda.action, " ", arena.panda.segment)
		await grab(shot[1])
	# Settlement: 笔走龙蛇 with 3 parries -> yin_weak for 3 s.
	arena.round_index = 1
	arena._enter_yin()
	step(arena.glyph.draw_duration + 0.06)
	step(arena.skills.end_time() - arena.skills.clock - 0.1)
	arena.skills.parries = 3
	step(0.8)
	print("weak state ", arena.state, " action ", arena.panda.action, " secs ", arena.yin_weak_seconds)
	await grab("28_yin_weak_settle")
	# Ink tone: the same skill (泼墨惊鸿 warning, then splash + bleed) with player yang vs yin.
	for want in [MirrorLake.Side.YANG, MirrorLake.Side.YIN]:
		if scene.side != want:
			scene.advance_switch(3.0); scene.request_switch(); scene.advance_switch(3.0)
		arena.round_index = 2
		arena._enter_yin()
		player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
		step(arena.glyph.draw_duration + 0.06 + 0.6)
		var tag := "yang" if want == MirrorLake.Side.YANG else "yin"
		print("tone ", tag, " ", arena.ink_tone)
		await grab("29_tone_%s_warn" % tag)
		step(3.4)
		player.position = Vector2(arena.board_rect().get_center().x, MirrorLake.STAND_Y)
		await grab("29_tone_%s_splash" % tag)
	print("saved to ", out_dir)
	quit(0)