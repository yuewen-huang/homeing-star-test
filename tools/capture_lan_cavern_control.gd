extends "level_design/capture_cavern_entrance.gd"
## One isolated setup on the real gate floor; inputs own all subsequent motion.
func run() -> void:
	use_memory_progress()
	output=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/lan_control_20261104/cavern_jump")
	DirAccess.make_dir_recursive_absolute(output)
	level=(load(SCENE) as PackedScene).instantiate()
	root.add_child(level)
	current_scene=level
	player=level.player
	await step(18)
	var gate: Vector2=level.marker("gate")
	player.reset_after_map_fall(Vector2(1900,gate.y))
	await step(3)
	var origin: Vector2=player.position
	Input.action_press(&"jump")
	await step(10)
	Input.action_press(&"ui_right")
	await step(10)
	await capture("01_steer_right")
	check(player.position.y<origin.y-60 and not player.aerial_dash_used,"Real gate jump rises while right input only steers")
	Input.action_release(&"ui_right")
	Input.action_press(&"ui_left")
	await step(10)
	await capture("02_reverse_near_apex")
	check(player.velocity.x<0 and not player.aerial_dash_used,"Real gate jump reverses without spending dash")
	Input.action_release(&"jump")
	for i in 60:
		await step(1)
		if player.air_state==LanPlayer.AirState.GROUNDED: break
	check(player.air_state==LanPlayer.AirState.GROUNDED and absf(player.position.y-origin.y)<1,"Real floor contact restores control without rolling")
	Input.action_press(&"jump")
	await step(3)
	Input.action_release(&"jump")
	await step(5)
	await capture("03_immediate_short_hop")
	check(player.position.y<origin.y and player.attack_state==LanPlayer.AttackState.NONE,"Immediate short hop responds after the real landing")
	release()
	for i in 60:
		await step(1)
		if player.air_state==LanPlayer.AirState.GROUNDED: break
	player.start_attack_1x(1.0)
	await step(10)
	await capture("04_attack_active")
	for i in 40:
		await step(1)
		if player.can_cancel_normal_attack_recovery(): break
	check(player.can_cancel_normal_attack_recovery(),"Gate attack reaches a cancellable recovery after its live effect")
	Input.action_press(&"jump")
	await step(5)
	await capture("05_attack_recovery_jump")
	check(player.velocity.y<0 and player.attack_state==LanPlayer.AttackState.NONE,"Jump leaves attack recovery in the production scene")
	check(player.get_node("StateTrace").report_count==0,"No animation-owner contradictions during the gate jump sequence")
	await end_entry_test()
