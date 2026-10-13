extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func hit(model: RuneLockModel, kind: RuneLockModel.RuneKind) -> Dictionary:
	for bar in model.bars:
		if int(bar.kind) == kind:
			model.angle = float(bar.angle)
			return model.strike()
	return {}

func _initialize() -> void:
	var model := RuneLockModel.new()
	model.prepare(123)
	check(model.bars.size() == 4, "Four starting runes")
	model.advance(5)
	check(model.time_left == 15, "Ready does not tick")
	check(model.strike().kind == "ignored", "Ready rejects strikes")
	model.start(123)
	check(hit(model, RuneLockModel.RuneKind.SCORE).kind == "score", "Gold hit")
	check(model.score == 1000 and model.direction == -1 and model.combo == 1, "Gold points and reversal")
	check(hit(model, RuneLockModel.RuneKind.TIME).kind == "time", "Blue hit")
	check(model.time_left == 16.5 and model.direction == 1, "Blue time and reversal")
	model.time_left = 29.5
	hit(model, RuneLockModel.RuneKind.TIME)
	check(model.time_left == 30, "Bonus cap")
	model.angle = 0
	model.bars = [{"angle": PI-0.03, "width": 0.2, "kind": 0, "ttl": 4}]
	model.angle = -PI+0.03
	check(model.strike().kind == "score", "Wrap-around hit")
	model.bars = [{"angle": 0.0, "width": 0.2, "kind": 0, "ttl": 4}]
	model.angle = 0.1
	check(model.strike().kind == "score", "Inclusive edge")
	model.bars = [{"angle": 0.0, "width": 0.2, "kind": 0, "ttl": 4}]
	model.angle = 1
	check(model.strike().kind == "miss", "Miss")
	check(model.combo == 0 and model.strike().kind == "ignored", "Cooldown and combo reset")
	model.advance(0.5)
	check(model.lock_remaining == 0, "Cooldown expires")
	check(is_equal_approx(model.get_angular_speed(true), model.get_angular_speed()*2), "Double speed")
	var signal_count := [0]
	var pass_result := [false]
	model.round_finished.connect(func(passed: bool): signal_count[0] += 1; pass_result[0] = passed)
	model.score = 6000
	model.advance(60)
	model.finish()
	check(model.phase == RuneLockModel.Phase.FINISHED and signal_count[0] == 1 and pass_result[0], "Pass emits once")
	check(model.strike().kind == "ignored", "Finished rejects input")
	model.start(456)
	check(model.score == 0 and model.misses == 0 and model.combo == 0, "Restart resets")
	model.advance(15.1)
	check(model.phase == RuneLockModel.Phase.FINISHED and not pass_result[0], "Timeout failure")
	model.start(1)
	model.time_left = 30
	model.elapsed = 59
	model.advance(2)
	check(model.phase == RuneLockModel.Phase.FINISHED and is_equal_approx(model.elapsed,60), "Absolute duration cap")
	var a := RuneLockModel.new()
	var b := RuneLockModel.new()
	a.start(789)
	b.start(789)
	for i in range(300): a.advance(1.0/30.0)
	for i in range(1440): b.advance(1.0/144.0)
	check(abs(a.time_left-b.time_left)<0.0001 and RuneLockModel.angular_distance(a.angle,b.angle)<0.0001, "30 and 144 FPS consistency")
	check(a.bars.size()==4 and b.bars.size()==4, "Expired runes replenish")
	for seed_value in range(1,101):
		model.start(seed_value)
		for i in range(10):
			hit(model, RuneLockModel.RuneKind.SCORE)
			check(model.bars.size()==4, "Population seed %d" % seed_value)
			for x in range(model.bars.size()):
				for y in range(x+1,model.bars.size()):
					check(RuneLockModel.angular_distance(model.bars[x].angle,model.bars[y].angle) > (model.bars[x].width+model.bars[y].width)*0.5, "No overlapping runes")

	var minimum_bot_score := 1000000
	for seed_value in range(1,31):
		model.start(seed_value)
		var ticks := 0
		while model.phase == RuneLockModel.Phase.RUNNING and ticks < 7201:
			model.advance(1.0/120.0)
			for bar in model.bars:
				if model.phase == RuneLockModel.Phase.RUNNING and RuneLockModel.angular_distance(model.angle,bar.angle) < bar.width*0.4:
					model.strike()
					break
			ticks += 1
		minimum_bot_score = mini(minimum_bot_score,model.score)
		check(model.score>=6000 and ticks<=7201, "Natural timed completion seed %d" % seed_value)
	print("Natural timing bot minimum: %d" % minimum_bot_score)
	print("RUNE MODEL: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
