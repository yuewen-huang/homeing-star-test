extends SceneTree

## 拼刀 prototype (scenes/dev/clash_prototype.tscn). Optional user args: snapshot
## directory, then "frames" to save every frame of each rhythm (subfolder p1..p5).

var demo: ClashPrototype
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

func play_out(index: int) -> void:
	demo.play(index)
	for i in 600:
		if demo.is_settled(): return
		step(1)

func snapshot(path: String) -> void:
	if output.is_empty(): return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(path + ".png"))

func crescent_on(node: Node2D) -> PixelSlash:
	for child in node.get_children():
		if child is PixelSlash and child.shape == &"crescent" and not child.is_queued_for_deletion(): return child
	return null

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output = args[0]; DirAccess.make_dir_recursive_absolute(output)
	capture_frames = args.size() > 1 and args[1] == "frames"
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	demo = load("res://scenes/dev/clash_prototype.tscn").instantiate()
	root.add_child(demo); current_scene = demo
	await process_frame
	demo.set_process(false)
	check(ClashPrototype.PATTERNS.size() == 5, "Five clash rhythms")

	# Escalation is monotonic and turns gold.
	var rising := true
	for n in range(2, 7):
		var a := ClashPrototype.tier(n - 1)
		var b := ClashPrototype.tier(n)
		rising = rising and b.spark >= a.spark and b.stop >= a.stop and b.shake >= a.shake and b.rays >= a.rays
	check(rising and ClashPrototype.tier(1).spark < ClashPrototype.tier(5).spark and ClashPrototype.tier(5).palette == &"gold", "Each consecutive clash is bigger, longer and harder, ending gold")

	# Rhythm 1: both smears are open when the blades meet, between the fighters.
	demo.play(0)
	var first_t: float = ClashPrototype.PATTERNS[0].events[0].t
	while demo.clashes < 1: step(1)
	var deer_cut := crescent_on(demo.deer)
	var lan_cut := crescent_on(demo.lan)
	check(deer_cut != null and lan_cut != null, "Clash has a deer crescent and Lan's answering crescent")
	check(deer_cut.age >= deer_cut.duration - 0.001 and lan_cut.age >= lan_cut.duration - 0.001, "Both smears are fully open at contact")
	var at: Vector2 = demo.last_clash.at
	check(at.x > demo.lan.position.x and at.x < demo.deer.position.x, "The clash bursts between Lan and the deer")
	check(absf(demo.clock - first_t) < 0.02, "Contact lands on the rhythm's beat")
	await snapshot("clash_1")
	var held := demo.clock
	var lan_at := demo.lan.position
	var deer_at := demo.deer.position
	step(2)
	check(is_equal_approx(demo.clock, held) and demo.lan.position == lan_at and demo.deer.position == deer_at, "Shared hit-stop holds the clock and both fighters")
	step(10)
	check(demo.deer.position.x > deer_at.x and demo.lan.position.x < lan_at.x, "Both slide apart after the clash")
	for i in 600:
		if demo.is_settled(): break
		step(1)
	check(demo.clashes == 3 and demo.chain == 3 and demo.counter.text == "3 拼刀", "三连叮: three clashes counted")

	# Rhythm 2: five accelerating clashes, counter turns gold.
	play_out(1)
	check(demo.clashes == 5 and demo.counter.text == "5 拼刀" and demo.counter.get_theme_color("font_color") == Color("ffe189"), "加速五连: five clashes, gold counter")

	# Rhythm 3: feint pause then two quick cuts.
	play_out(2)
	check(demo.clashes == 4, "迟滞变招: four clashes around the pause")

	# Rhythm 4: red finisher parried → 一闪 through the deer, cuts, stagger.
	demo.play(3)
	var deer_before := 0.0
	while demo.counters < 1:
		step(1)
		if demo.counters == 0: deer_before = demo.deer.position.x
	check(demo.last_clash.red and demo.clashes == 5, "Red finisher is the fifth clash")
	for i in 30: step(1)
	check(demo.lan.position.x > demo.deer.position.x, "一闪 puts Lan behind the deer")
	await snapshot("counter")
	play_out(3)
	check(demo.deer.position.x < deer_before - 60.0, "The counter knocks the deer back")
	check(demo.counter.text == "5 拼刀", "Counter keeps the five-clash chain")

	# Rhythm 5: a miss lands on Lan and breaks the chain.
	demo.play(4)
	while demo.misses < 1: step(1)
	check(demo.chain == 0 and demo.counter.text == "拼刀中断", "A miss breaks the chain")
	await snapshot("miss")
	for i in 600:
		if demo.is_settled(): break
		step(1)
	check(demo.clashes == 3 and demo.chain == 1, "The next clash starts a new chain")

	# Slow motion keeps contacts on their beats.
	demo.play(0)
	for i in 2000:
		demo.advance(1.0 / 240.0)
		if demo.clashes >= 1: break
	check(absf(demo.clock - first_t) < 0.006, "Slow motion keeps the clash on its beat")
	demo.reset()
	check(demo.chain == 0 and demo.fx.get_child_count() == 0 and crescent_on(demo.deer) == null and crescent_on(demo.lan) == null and not demo.counter.visible, "Reset clears everything")

	if capture_frames:
		for p in ClashPrototype.PATTERNS.size():
			DirAccess.make_dir_recursive_absolute(output.path_join("p%d" % (p + 1)))
			demo.play(p)
			var f := 0
			while not demo.is_settled() and f < 400:
				step(1)
				await snapshot("p%d/frame_%03d" % [p + 1, f])
				f += 1
	current_scene = null
	demo.free()
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH) == save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) == saved), "Prototype leaves progress untouched")
	print("CLASH PROTOTYPE: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
