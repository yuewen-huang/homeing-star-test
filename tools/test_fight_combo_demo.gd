extends SceneTree

## Fighting-game combo demo (scenes/dev/fight_combo_demo.tscn). Optional user args:
## snapshot directory, then "frames" to save every frame of one playthrough for GIFs.

var demo: FightComboDemo
var checks := 0
var failures := 0
var output := ""
var capture_frames := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", label)

func step(count: int) -> void:
	for i in count: demo.advance(1.0 / 60.0)

func snapshot(name: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	capture_frames = args.size() > 1 and args[1] == "frames"
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	demo = load("res://scenes/dev/fight_combo_demo.tscn").instantiate()
	root.add_child(demo); current_scene = demo
	await process_frame
	demo.set_process(false)
	var hit_events: int = FightComboDemo.TIMELINE.filter(func(e: Dictionary) -> bool: return e.do == "hit").size()
	check(hit_events == 9, "Combo has nine hits (five cuts, three delayed cuts, finisher)")

	demo.play()
	var start := demo.attacker.position
	# First cut: a crescent grown from the attacker, not a projectile.
	step(2)
	var crescent: PixelSlash = demo.attacker.get_child(0) if demo.attacker.get_child_count() > 0 else null
	check(crescent != null and crescent.shape == &"crescent", "First cut is a crescent attached to the attacker")
	step(1)
	check(crescent.get_parent() == demo.attacker and crescent.global_position == demo.attacker.global_position, "The crescent moves with the attacker")
	while demo.hits < 1: step(1)
	await snapshot("hit_1")
	var held_clock := demo.clock
	var held_target := demo.target.position
	step(2)
	check(is_equal_approx(demo.clock, held_clock) and demo.target.position == held_target, "Hit-stop holds the combo clock and the target")
	check(demo.counter.visible and demo.counter.text == "1 HITS", "Counter shows the first hit")
	step(6)
	check(demo.target.position.x > held_target.x, "The target is pushed back after the hit-stop")
	check(demo.attacker.position.x > start.x, "The attacker steps in with the cut")
	while demo.hits < 3: step(1)
	step(12)
	check(demo.target.position.y < FightComboDemo.GROUND_Y - 20.0, "The uppercut launches the target")
	await snapshot("launch")
	while demo.hits < 5: step(1)
	await snapshot("thrust")
	var before_flash := demo.attacker.position.x
	while demo.clock < 1.37: step(1)
	check(demo.attacker.position.x > demo.target.position.x and demo.attacker.position.x - before_flash > 100.0, "一闪 puts the attacker past the target in one step")
	await snapshot("flash_step")
	while demo.hits < 8: step(1)
	await snapshot("delayed_cuts")
	while demo.hits < 9: step(1)
	step(3)
	await snapshot("finisher")
	check(demo.counter.text == "9 HITS", "Counter reaches 9 HITS")
	step(30)
	check(demo.target.position.y < FightComboDemo.GROUND_Y - 40.0, "The finisher throws the target")
	for i in 400:
		if demo.is_settled(): break
		step(1)
	check(demo.is_settled() and demo.target.position.y == FightComboDemo.GROUND_Y, "Everything finishes and the target lands")

	# Same clock in slow motion: the first hit lands at the same combo time.
	demo.play()
	for i in 600:
		demo.advance(1.0 / 240.0)
		if demo.hits >= 1: break
	check(absf(demo.clock - FightComboDemo.TIMELINE[2].t) < 0.006, "Slow motion keeps the hit on its combo time")
	demo.reset()
	check(demo.hits == 0 and demo.fx.get_child_count() == 0 and demo.attacker.get_child_count() == 0 and not demo.counter.visible, "Reset clears effects and the counter")

	if capture_frames:
		demo.play()
		var f := 0
		while not demo.is_settled() and f < 400:
			step(1)
			await snapshot("frame_%03d" % f)
			f += 1
	current_scene = null
	demo.free()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Demo leaves progress untouched")
	print("FIGHT COMBO: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
