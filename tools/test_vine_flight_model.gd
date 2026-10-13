extends SceneTree
const MODEL = preload("res://scripts/minigames/vine_flight_model.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	print("OK " if ok else "FAIL ", message)
	if not ok: failures += 1

func _initialize() -> void:
	var m := MODEL.new()
	m.start(1)
	var selected := m.candidate()
	var before := m.position
	m.advance(MODEL.STEP, true)
	check(m.attached < 0 and m.shot_target == selected and m.shot_progress > 0 and m.shot_progress < 1, "press shoots toward the highlighted anchor instead of instant attachment")
	check(m.position.distance_to(before) > 0, "player continues moving while the vine flies")
	check(m.shot_tip().distance_to(m.hand_position()) > 0 and m.shot_tip().distance_to(m.vines[selected].at) > 0, "shooting vine has separate hand and traveling tip endpoints")
	m.vines.append({"at": m.hand_position() + Vector2(25,-55), "fragile":false, "broken_until":0})
	m.advance(0.05, true)
	check(m.shot_target == selected, "in-flight shot keeps its original target")
	m.advance(0.1, true)
	check(m.attached == selected and m.shot_target < 0, "short flight ends in attachment")
	var hand := m.hand_position()
	check(hand.distance_to(m.vines[selected].at) <= m.radius + 0.001, "attached hand stays within the captured rope length")
	m.start(1)
	m.advance(0.04, true)
	m.advance(0.2, false)
	check(m.attached < 0 and m.shot_target < 0, "releasing during the shot cancels it")
	m.start(1)
	m.position = Vector2(500,260)
	m.velocity = Vector2(300,-120)
	m.vines = [{"at":Vector2(650,100),"fragile":false,"broken_until":0}]
	var incoming := m.velocity
	before = m.position
	var tangent := Vector2((m.hand_position()-m.vines[0].at).y, -(m.hand_position()-m.vines[0].at).x).normalized()
	m._attach(0)
	check(m.position == before, "attachment does not teleport the body")
	check(m.velocity.dot(tangent) >= 360 and m.velocity.dot(tangent) >= incoming.length()*0.85, "catch converts arrival energy into an immediate forward swing")
	before = m.position
	incoming = m.velocity
	m.release()
	check(m.position == before and is_equal_approx(m.velocity.x, incoming.x) and is_equal_approx(m.velocity.y, incoming.y-100), "release preserves momentum with only a small upwards hop")
	check(m.candidate() < 0, "released anchor cannot be targeted again")
	m.vines.append({"at":m.hand_position()+Vector2(-20,-100),"fragile":false,"broken_until":0})
	check(m.candidate() < 0, "behind-body anchors are excluded")
	m.start(1)
	m.vines = [{"at":Vector2(700,100),"fragile":false,"broken_until":0}]
	m.velocity = Vector2(300,0)
	m.advance(0.1,true)
	check(m.shot_target < 0, "out-of-range press cannot attach or teleport")
	m.position.x = 440
	m.advance(MODEL.STEP,true)
	check(m.shot_target == 0, "early held input shoots on entering reach")
	m.start(1)
	m.vines = [{"at":Vector2(700,100),"fragile":false,"broken_until":0}]
	m.velocity = Vector2.ZERO
	m.advance(0.4,true)
	m.position = Vector2(440,260)
	m.advance(MODEL.STEP,true)
	check(m.shot_target == 0 and m.attached < 0, "holding early waits for a reachable anchor without needing another press")
	m.advance(MODEL.STEP,false)
	m.advance(MODEL.STEP,true)
	check(m.shot_target == 0, "release cancels the waiting input and a new press can shoot")
	m.start(1)
	m._attach(0)
	m.position = m.vines[0].at + Vector2(sin(1.315),cos(1.315))*m.radius - MODEL.HAND_OFFSET
	m.velocity = Vector2(cos(1.315),-sin(1.315))*m.radius*1.5
	m.angle = 1.315
	m.omega = 1.5
	m.advance(MODEL.STEP,true)
	check(m.angle > 1.32 and m.omega > 0, "old angle boundary no longer forcibly reflects the swing")
	m.start(1)
	m._attach(0)
	m.velocity = Vector2(220,-220)
	m.combo = 4
	m.release()
	check(m.combo == 5 and is_equal_approx(m.rush_left,8), "fifth perfect release starts rush")
	m.position.y = MODEL.NET_Y + 1
	m.velocity = Vector2(300,400)
	m.advance(MODEL.STEP,false)
	check(m.falls == 1 and m.combo == 0 and m.rush_left == 0 and m.velocity.y < 0 and m.velocity.x >= 230, "leaf net recovers the player with useful forward momentum")
	check(MODEL.is_perfect(Vector2.from_angle(deg_to_rad(-25))) and MODEL.is_perfect(Vector2.from_angle(deg_to_rad(-65))), "perfect interval includes both boundaries")
	check(not MODEL.is_perfect(Vector2.from_angle(deg_to_rad(-24.9))) and not MODEL.is_perfect(Vector2(-100,-100)), "ordinary and backward release directions do not earn perfect")
	# Reproduce the reported hold-only stall: score alone is not a swing test.
	m.start(1)
	m.advance(0.1,true)
	var catch_x := m.position.x
	var cross_time := -1.0
	var peak_angle := m.angle
	var last_min := INF
	var last_max := -INF
	var slow_window := 0.0
	var longest_slow := 0.0
	for tick in 960:
		m.advance(MODEL.STEP,true)
		peak_angle = maxf(peak_angle,m.angle)
		if cross_time < 0 and m.angle >= 0.65: cross_time = tick*MODEL.STEP
		if tick >= 600:
			last_min = minf(last_min,m.position.x)
			last_max = maxf(last_max,m.position.x)
		if m.velocity.length() < 60: slow_window += MODEL.STEP
		else: slow_window = 0
		longest_slow = maxf(longest_slow,slow_window)
	print("SWING first-forward=",cross_time," peak=",peak_angle," sustained-width=",last_max-last_min," longest-slow=",longest_slow)
	check(cross_time >= 0 and cross_time < 0.6 and peak_angle >= 1.1,"first held catch reaches a clear forward upswing within 0.6 seconds")
	check(last_max-last_min > 200 and longest_slow < 0.5 and m.falls == 0,"continued holding keeps a broad swing without settling or requiring a leaf-net bounce")
	m.start(1)
	m.velocity = Vector2.ZERO
	m._attach(0)
	catch_x = m.position.x
	for tick in 72: m.advance(MODEL.STEP,true)
	check(m.position.x-catch_x > 150 and m.angle > 0.6,"even a stopped catch starts swinging instead of hanging motionless")
	var reference: Vector2
	var scores: Array[int] = []
	for fps in [30,60,144]:
		m = MODEL.new()
		m.start(42)
		var finished := [0]
		m.round_finished.connect(func(_passed): finished[0]+=1)
		for frame in fps * 46:
			m.advance(1.0/fps, frame % fps < fps * 2 / 3)
		check(m.phase == MODEL.Phase.FINISHED and is_equal_approx(m.elapsed,45) and finished[0] == 1, "%d FPS finishes once at 45 seconds" % fps)
		if fps == 30: reference = m.position
		else: check(m.position.distance_to(reference)<0.001, "%d FPS repeated-input trajectory matches" % fps)
		scores.append(m.score)
		m.start(42)
		check(m.score == 0 and m.combo == 0 and m.falls == 0 and m.shot_target < 0 and m.attached < 0, "restart clears movement, shooting and score")
	check(scores[0] == scores[1] and scores[1] == scores[2], "frame rates give equal scores for repeated presses and releases")
	var unreachable := 0
	var casual_passes := 0
	var casual_min := 999999
	var expert_passes := 0
	var idle_passes := 0
	var timed_passes := 0
	var ordinary_perfects := 0
	var ordinary_falls := 0
	var ordinary_base_passes := 0
	var minimum_y := 9999.0
	for seed_value in range(1,31):
		m = MODEL.new()
		m.start(seed_value)
		for i in m.vines.size()-1:
			m.attached = i
			m.radius = 240
			m.angle = 0.2
			m.omega = 1.8
			m.position = m.vines[i].at + Vector2(sin(0.2),cos(0.2))*240 - MODEL.HAND_OFFSET
			m.velocity = Vector2(cos(0.2),-sin(0.2))*240*1.8
			m.release()
			m.advance(MODEL.STEP,false)
			for tick in 120:
				m.advance(MODEL.STEP,true)
				if m.attached >= 0: break
			if m.attached != i+1: unreachable += 1
		for mode in ["casual","expert","ordinary","idle","timed"]:
			m = MODEL.new()
			m.start(seed_value)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var target := rng.randf_range(0.4,1.05)
			var perfect_bonus := [0]
			var bonus_callback := func(kind,_at):
				if kind == "perfect": perfect_bonus[0] += 200 * mini(m.combo,10) * (2 if m.rush_left > 0 else 1)
			m.feedback.connect(bonus_callback)
			var previous := -1
			for tick in 5400:
				if m.attached >= 0 and m.attached != previous:
					previous = m.attached
					if mode == "casual": target = rng.randf_range(0.4,1.05)
				var held: bool = m.shot_target >= 0 or m.candidate() >= 0
				if m.attached >= 0:
					if mode == "ordinary": held = not (m.omega > 0 and m.angle >= 0.2)
					elif mode == "expert": held = not ((m.held_time >= 0.2 and MODEL.is_perfect(m.velocity)) or m.held_time >= 1.0)
					else: held = m.held_time < target
				if mode == "idle": held = false
				if mode == "timed": held = tick % 108 < 96
				m.advance(MODEL.STEP,held)
				minimum_y = minf(minimum_y,m.position.y)
			m.feedback.disconnect(bonus_callback)
			var passed := m.score >= MODEL.TARGET_SCORE
			match mode:
				"casual":
					casual_passes += int(passed)
					casual_min = mini(casual_min,m.score)
				"expert": expert_passes += int(passed)
				"ordinary":
					ordinary_perfects += m.perfect_count
					ordinary_falls += m.falls
					ordinary_base_passes += int(m.score-perfect_bonus[0] >= MODEL.TARGET_SCORE)
					if not passed: unreachable += 1
				"idle": idle_passes += int(passed)
				"timed": timed_passes += int(passed)
	print("CASUAL pass=",casual_passes,"/30 min=",casual_min," EXPERT=",expert_passes," TIMED=",timed_passes," idle=",idle_passes," ordinary-perfects=",ordinary_perfects," ordinary-falls=",ordinary_falls," base-pass=",ordinary_base_passes," min-y=",minimum_y)
	check(unreachable == 0, "30 seeds: ordinary releases can reach every following anchor and pass the round")
	check(ordinary_base_passes == 30, "ordinary relay passes all seeds even without perfect-release bonuses")
	check(casual_passes >= 24 and expert_passes == 30, "varied hold durations and velocity-guided releases are accessible")
	check(timed_passes == 30, "simple timed hold/release pattern passes all seeds")
	check(minimum_y >= 30, "even high leaps keep the body inside the playfield")
	check(idle_passes == 0, "automatic leaf-net bounces alone cannot pass")
	print("VINE FLIGHT MODEL: ",checks," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)
