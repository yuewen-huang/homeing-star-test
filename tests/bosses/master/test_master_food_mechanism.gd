extends "../../support/harness.gd"

class Spy extends Node2D:
	var calls := 0
	var result := CombatHitResult.Type.NORMAL_HIT
	var last: CombatAttackData
	func receive_combat_hit(hit: CombatAttackData) -> CombatHitResult.Type:
		calls += 1
		last = hit
		return result

func run() -> void:
	use_memory_progress()
	var dev := load("res://scenes/dev/boss_development_room.tscn").instantiate() as Node2D
	root.add_child(dev)
	current_scene = dev
	dev.select_boss(1)
	dev.select_combo(2)
	dev.set_combat_simulation(true)
	var boss := dev.adapter.master as MasterBoss
	var player := dev.player as LanPlayer
	boss.set_process(false)
	player.set_physics_process(false)
	boss.charged_power = 1
	boss._process(0.01)
	check(boss.food_mechanism == null,"Food event does not trigger before two completed drinks")
	boss._cancel_phase_1_action()
	boss.charged_power = 2
	boss.state = MasterBoss.State.CHASE
	boss._process(0.01)
	var food := boss.food_mechanism
	player.global_position = boss.global_position+Vector2(2000,0)
	check(food != null and boss.flying_sword_used and boss.state == MasterBoss.State.MECHANISM,"Two layers automatically enter the once-per-fight food event")
	check(food.stage == MasterFoodMechanism.Stage.SEATING and food.pickups.is_empty() and is_equal_approx(food.remaining,20),"Master sits before food appears; seating never consumes the countdown")
	check(food.formation == null,"No patrol sword exists before the sitting portion starts")
	boss._on_body_animation_finished()
	check(food.stage == MasterFoodMechanism.Stage.SEATING,"A stray animation-finished callback cannot skip seating or stand the master up")
	food.advance(food._seating_time+0.01)
	check(food.needed == 1 and food.rounds == 3 and food.pickups.size() == 3 and food.formation.swords.size() == 3,"After seating, each round requests one item and creates the patrol formation")
	check(food.display.bubble.visible and food.display.food_icon.texture.resource_path.ends_with(String(MasterFoodMechanism.FOODS[food.wanted])+".png") and food.display.countdown.digits.text == "20","Current food appears as an icon bubble with a separate numeric countdown")
	var labels := food.find_children("*","Label",true,false)
	check(labels.size() == 1 and (labels[0] as Label).text.is_valid_int(),"Food mechanism contains no text prompts, only countdown digits")
	food.advance(0.31)
	var seated_frame := boss.animated_sprite.frame
	food.advance(1.2)
	check(boss.state == MasterBoss.State.MECHANISM and seated_frame >= 22 and seated_frame <= 33 and absi(boss.animated_sprite.frame-seated_frame) <= 1,"Only authored seated frames 22 through 33 loop during collection")
	var before := food.remaining
	boss.parry_pause_remaining = 1
	boss._process(0.1)
	check(food.remaining == before,"Shared parry pause freezes food time and flying swords")
	boss.parry_pause_remaining = 0
	player.global_position = boss.global_position+Vector2(2000,0)
	check(not food.collect(0) and not food.submit(food.wanted),"Remote pickup and delivery cannot bypass movement")
	var item_index := 0
	for i in food.pickups.size():
		if food.pickups[i].kind == food.wanted: item_index = i
	var pickup_at: Vector2 = food.pickups[item_index].node.global_position
	player.global_position = pickup_at
	food.advance(0.6)
	check(food.selected == -1 and is_equal_approx(food.pickup_progress,0.6) and food.pickups[item_index].progress.visible,"Standing near food shows a real loading bar without an E press")
	player.global_position += Vector2(0,-150)
	food.advance(0.01)
	check(food.pickup_progress == 0 and not food.pickups[item_index].progress.visible,"Leaving pickup range resets loading")
	player.global_position = pickup_at
	food.advance(0.99)
	check(food.selected == -1,"Pickup cannot complete in less than one continuous second")
	food.advance(0.02)
	check(food.selected == food.wanted and food.bag[food.wanted] == 1 and not food.collect(item_index),"One second automatically picks exactly one item, never twice")
	for round_index in food.rounds:
		if round_index > 0:
			for i in food.pickups.size():
				if food.pickups[i].kind != food.wanted: continue
				player.global_position = food.pickups[i].node.global_position
				food.advance(1.01)
				break
		var old_wanted := food.wanted
		food.remaining = 0.2
		player.global_position = boss.global_position
		food.advance(0.01)
		if round_index < food.rounds-1:
			check(food.stage == MasterFoodMechanism.Stage.COLLECT and food.current_round == round_index+2 and food.wanted != old_wanted and food.selected == -1 and is_equal_approx(food.remaining,boss.food_time_limit),"Each automatic one-item delivery starts a fresh request and countdown")
			check(food.display.countdown.digits.text == str(ceili(boss.food_time_limit)) and is_equal_approx(food.display.countdown.seconds,boss.food_time_limit),"Last-moment delivery refills the displayed timer to a full new round")
	check(food.stage == MasterFoodMechanism.Stage.OPENING,"Only completing every round opens the stuffed-master window")
	check(not food.display.bubble.visible and not food.display.countdown.visible,"Success hides both request icon and collection countdown without a text message")
	food.advance(5.9)
	check(not food.finished,"Success gives the full six-second output window")
	food.advance(0.11)
	check(not food.finished and food.stage == MasterFoodMechanism.Stage.STANDING and boss.animated_sprite.frame == 34,"Success waits until the full output window ends before starting the authored getup")
	food.advance(1.61)
	check(boss.food_mechanism == null and boss.state == MasterBoss.State.RECOVER,"Success returns through normal recovery")
	boss.state = MasterBoss.State.CHASE
	boss._process(0.01)
	check(boss.food_mechanism == null and not boss.start_food_mechanism(),"The event cannot re-arm at later spirit layers")
	dev.reset_room()
	boss = dev.adapter.master
	boss.set_process(false)
	boss.start_food_mechanism()
	food = boss.food_mechanism
	food.begin_collect()
	food.remaining = 0.01
	food.advance(0.02)
	check(food.stage == MasterFoodMechanism.Stage.RAGE and boss.animated_sprite.frame >= 22 and boss.animated_sprite.frame <= 33,"Natural timeout triggers rage while the master remains seated")
	food.advance(0.01)
	check(food.formation.swords.size() == 1 and food.formation.barrage != null,"Rage clears patrol swords and starts the existing nine-cut executor")
	for i in 1600:
		if food.stage == MasterFoodMechanism.Stage.STANDING: break
		food.advance(1.0/120)
	check(food.stage == MasterFoodMechanism.Stage.STANDING and food.formation.barrage.finished,"Timeout path only starts standing after all nine rage slashes finish")
	food.advance(1.61)
	check(food.finished and boss.food_mechanism == null and boss.state == MasterBoss.State.RECOVER,"Failed food event executes all rage cuts then resumes ordinary AI")
	dev.reset_room()
	boss = dev.adapter.master
	boss.set_process(false)
	boss.start_food_mechanism()
	food = boss.food_mechanism
	food.begin_collect()
	var wrong := (food.wanted+1)%3
	for i in food.pickups.size():
		if food.pickups[i].kind == wrong:
			player.global_position = food.pickups[i].node.global_position
			food.advance(1.01)
			break
	player.global_position = boss.global_position
	food.advance(0.01)
	check(food.stage == MasterFoodMechanism.Stage.RAGE and boss.animated_sprite.frame >= 22 and boss.animated_sprite.frame <= 33,"Wrong automatic delivery triggers rage without prematurely standing up")
	# Exercise real hurtbox settlement without depending on Lan's changing invulnerability state.
	var spy := Spy.new()
	dev.add_child(spy)
	var hurtbox := CombatHurtbox2D.new()
	hurtbox.name = "Hurtbox"
	spy.add_child(hurtbox)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(30,80)
	collision.shape = rectangle
	hurtbox.add_child(collision)
	spy.global_position = Vector2(500,400)
	boss.combat_target = spy
	var combat := MasterFlyingSwordCombat.new()
	combat.boss = boss
	var a := Vector2(440,390)
	var b := Vector2(550,390)
	combat.strike("normal",a,b,a+Vector2(0,20),b+Vector2(0,20))
	combat.strike("normal",a,b,a,b)
	check(spy.calls == 1 and spy.last.health_damage > 0 and spy.last.danger_type == CombatAttackData.DangerType.NORMAL,"Blue blade uses shared damage and settles only once per cut")
	spy.result = CombatHitResult.Type.EVADED
	combat.strike("evade",a,b,a,b)
	check(not combat.settled.has("evade"),"Dodged contact can retry only while the current blade remains active")
	spy.result = CombatHitResult.Type.NORMAL_HIT
	combat.strike("gold",a,b,a,b,true)
	check(spy.last.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER,"Final gold cut uses the shared unparryable danger type")
	spy.result = CombatHitResult.Type.PARRY_SUCCESS
	var sword := food.formation.swords[0]
	sword.sweep(spy.global_position)
	combat.strike("parry",a,b,a,b,false,sword)
	check(sword.state == MasterFlyingSword.State.DEFLECTED and boss.parry_pause_remaining > 0,"Normal parry settles on the boss and deflects the patrol sword")
	boss._enter_phase_2()
	check(boss.food_mechanism == null and food.finished and food.is_queued_for_deletion(),"Phase transition cancels the timer, food and sword event")
	dev.reset_room()
	boss = dev.adapter.master
	boss.set_process(false)
	boss.start_food_mechanism()
	food = boss.food_mechanism
	dev.reset_room()
	await process_frame
	check(not is_instance_valid(food),"Retry frees mechanism HUD, bubble, pickups and sword descendants")
	boss = dev.adapter.master
	boss.set_process(false)
	boss.start_food_mechanism()
	food = boss.food_mechanism
	player.combat_stats.apply_health_damage(player.combat_stats.health)
	boss._process(0.01)
	check(boss.food_mechanism == null and food.finished,"Player death cancels the food event before another attack")
	dev.set_combat_simulation(false)
	dev.select_combo_library(9)
	dev.play_action(4)
	boss = dev.adapter.master
	check(boss.manual_control and boss.food_mechanism != null and boss.combat_target == player,"Full mechanism is also available as a safe manual preview")
	# Audit all three exits independently, including the whole seated rage and getup interval.
	for outcome: String in ["timeout","solved","wrong"]:
		dev.play_action(4)
		boss = dev.adapter.master
		boss.set_process(false)
		food = boss.food_mechanism
		food.advance(food._seating_time+0.01)
		player.global_position = boss.global_position
		if outcome == "solved":
			for i in food.rounds:
				food.selected = food.wanted
				food.bag[food.wanted] = 1
				food.submit(food.wanted)
		elif outcome == "wrong":
			food.selected = (food.wanted+1)%3
			food.bag[food.selected] = 1
			food.submit(food.selected)
		else:
			food.remaining = 0.001
			food.advance(0.01)
		var seated_through := true
		for i in 1800:
			if food.stage == MasterFoodMechanism.Stage.STANDING: break
			food.advance(1.0/120.0)
			if food.stage != MasterFoodMechanism.Stage.STANDING:
				seated_through = seated_through and boss.animated_sprite.frame >= 22 and boss.animated_sprite.frame <= 33
		check(seated_through and food.stage == MasterFoodMechanism.Stage.STANDING and boss.animated_sprite.frame == 34,"%s: the whole mechanism stays seated, then starts getup exactly once" % outcome)
		food.advance(1.59)
		check(not food.finished and food.stage == MasterFoodMechanism.Stage.STANDING,"%s: normal AI cannot interrupt the authored getup" % outcome)
		food.advance(0.02)
		check(food.finished and boss.food_mechanism == null and boss.state == MasterBoss.State.RECOVER,"%s: standing completes before ordinary combat recovery resumes" % outcome)
	dev.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER FOOD MECHANISM")
