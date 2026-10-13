extends SceneTree

var failures := 0

func check(ok: bool, message: String) -> void:
	print("OK " if ok else "FAIL ",message)
	if not ok:
		failures += 1

func _initialize() -> void:
	var model := WindFlightModel.new()
	model.start(7)
	var initial := model.altitude
	model.advance(0.5,true,false,false)
	check(model.altitude<initial,"W raises flight altitude")
	model.advance(1.0,false,true,false)
	check(model.altitude>initial,"S lowers flight altitude")
	model.walls = [{"x":WindFlightModel.PLAYER_X,"width":52.0,"gap":70.0,"height":100.0}]
	model.advance(WindFlightModel.STEP)
	check(model.phase==WindFlightModel.Phase.FINISHED and model.failure_reason=="撞上障碍墙","Wall collision ends flight")
	model.start(11)
	model.walls = [{"x":180.0,"width":52.0,"gap":235.0,"height":190.0}]
	model.advance(WindFlightModel.STEP)
	check(model.is_running(),"Passing through wall opening is safe")
	model._enter_turbulence()
	check(model.walls.is_empty(),"Turbulence has no obstacle walls")
	var first_width := model.bar_height
	var novice := WindFlightModel.new()
	novice.start(4)
	novice._enter_turbulence()
	var experienced := WindFlightModel.new()
	experienced.start(4)
	experienced.cycle = 1
	experienced._enter_turbulence()
	check(first_width > experienced.bar_height,"First turbulence gives a wider control bar")
	novice._wind_goal = 0.9
	experienced._wind_goal = 0.9
	novice._wind_timer = 2
	experienced._wind_timer = 2
	novice.advance(0.2,false,false,true)
	experienced.advance(0.2,false,false,true)
	check(absf(novice.wind_speed)<absf(experienced.wind_speed),"First turbulence target accelerates more gently")
	model.bar_center = 0.6
	model.bar_speed = 0
	model.advance(0.1,false,false,true)
	check(model.bar_speed<0 and model.bar_center<0.6,"Holding fishing button accelerates bar upward")
	var rising_speed := model.bar_speed
	model.advance(WindFlightModel.STEP,false,false,false)
	check(model.bar_speed<0 and model.bar_speed>rising_speed,"Release applies gravity while retaining inertia")
	model.bar_center = 1-model.bar_height*0.5-0.001
	model.bar_speed = 0.7
	model.advance(WindFlightModel.STEP)
	check(model.bar_speed<0,"Control bar bounces off bottom")
	model.bar_center = 0.5
	model.bar_speed = 0
	model.wind_target = 0.5
	model._wind_goal = 0.5
	model.wind_speed = 0
	var previous := model.stamina
	model.advance(WindFlightModel.STEP,false,false,false)
	check(model.covered and model.stamina>previous,"Covering target replenishes stamina")
	model.bar_center = 0.85
	model.wind_target = 0.2
	model._wind_goal = 0.2
	model.bar_speed = 0
	previous = model.stamina
	model.advance(WindFlightModel.STEP)
	check(not model.covered and model.stamina<previous,"Losing target drains stamina")
	model.stamina = 0.0001
	model.advance(WindFlightModel.STEP)
	check(model.phase==WindFlightModel.Phase.FINISHED and model.failure_reason.contains("体力耗尽"),"Empty stamina causes fall failure")
	model.start(5)
	model._enter_turbulence()
	model.stamina = 0.9999
	model.advance(WindFlightModel.STEP,false,false,true)
	check(model.phase==WindFlightModel.Phase.RECOVERY and model.cycle==1,"Full stamina clears turbulence")
	check(is_equal_approx(model.boost_left,2.0) and model.flight_speed()>253,"Turbulence clear grants two-second speed boost")
	var before_travel := model.travel_distance
	var before_score_distance := model.distance
	model.advance(1.0)
	check(absf((model.distance-before_score_distance)-2*(model.travel_distance-before_travel))<0.00001,"Boost doubles credited distance, without doubling background travel")
	check(absf((model.travel_distance-before_travel)-37.95)<0.00001,"Boost speed is 1.5 times normal flight speed")
	model.advance(1.1)
	check(model.boost_left==0 and is_equal_approx(model.flight_speed(),253.0),"Boost expires and restores normal speed")
	model.advance(0.5)
	check(model.phase==WindFlightModel.Phase.FLIGHT,"Clear recovery returns to flight")
	var milestone := [0]
	model.target_reached.connect(func(): milestone[0]+=1)
	model.distance = WindFlightModel.TARGET_SCORE-0.001
	model.advance(0.1)
	model.advance(0.1)
	check(milestone[0]==1,"Distance threshold fires once while flight continues")
	var seeded_a := WindFlightModel.new()
	var seeded_b := WindFlightModel.new()
	seeded_a.start(42)
	seeded_b.start(42)
	seeded_a._enter_turbulence()
	seeded_b._enter_turbulence()
	for i in 120:
		seeded_a.advance(1.0/60.0,false,false,i%2==0)
	for i in 240:
		seeded_b.advance(1.0/120.0,false,false,i%4<2)
	check(absf(seeded_a.wind_target-seeded_b.wind_target)<0.00001 and absf(seeded_a.stamina-seeded_b.stamina)<0.00001,"Fixed steps preserve seeded behavior at 60 and 120 Hz")
	for seed_value in [1,7,19,42,81]:
		model = WindFlightModel.new()
		model.start(seed_value)
		var steps := 0
		var stages: Array[int] = []
		while model.is_running() and model.score<1200 and steps<30000:
			if model.phase not in stages:
				stages.append(model.phase)
			var goal := 235.0
			for wall in model.walls:
				if wall.x+wall.width >= WindFlightModel.PLAYER_X-20:
					goal = wall.gap
					break
			var predicted := model.altitude+model.vertical_speed*0.12
			var hold := model.bar_center+model.bar_speed*0.18>model.wind_target+model.wind_speed*0.12
			model.advance(WindFlightModel.STEP,predicted>goal+6,predicted<goal-6,hold)
			steps+=1
		check(model.score>=1000 and WindFlightModel.Phase.TURBULENCE in stages and WindFlightModel.Phase.RECOVERY in stages,"Seed %d: reachable distance target through both stages (%d m, %s)" % [seed_value,model.score,model.failure_reason])
	print("WIND FLIGHT MODEL CHECKS: ",failures," failures")
	quit(1 if failures else 0)
