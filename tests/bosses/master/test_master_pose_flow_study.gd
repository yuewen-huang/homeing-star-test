extends "../../support/harness.gd"
var room: BossDevelopmentRoom
var master: MasterBoss
var study_action := 2
var study_id := &"inertia_combo"
var contact_count := 3

func run() -> void:
	var save := use_memory_progress()
	var before := save._config.encode_to_text()
	room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.play_action(study_action)
	master = room.adapter.master
	master.set_process(false)
	master.attack_hitbox.set_physics_process(false)
	var r := master.clash_rhythm
	check(r.id == study_id and MasterClashRhythm.ORDER.has(r.id), "Motion sample is part of the production move table")
	check(master.manual_control and r.strikes.size() == contact_count, "Sample has the designed contact count, independent of the retired six-beat template")
	var previous := master.position
	var planted := true
	var stable_body := true
	var static_art := true
	var checked_pause := false
	var registered := true
	for i in 370:
		master._process(1.0 / 120.0)
		room._process(0.0)
		planted = planted and r.direction * (master.position.x - previous.x) >= -0.001 and master.position.y == previous.y
		stable_body = stable_body and is_zero_approx(master.animated_sprite.rotation)
		previous = master.position
		if not checked_pause and not r.winds.is_empty() and r.elapsed > 0.45:
			var age: float = r.winds[0].node.age
			var time := r.elapsed
			var at := master.position
			master.start_parry_feedback()
			master._process(0.01)
			check(r.elapsed == time and master.position == at and r.winds[0].node.age == age, "Real parry hit-stop holds body, displacement and ribbons together")
			master.parry_pause_remaining = 0.0
			checked_pause = true
		for wind: Dictionary in r.winds:
			if not is_instance_valid(wind.node): continue
			static_art = static_art and wind.node is MasterBakedEffect
			if wind.node is MasterBakedEffect:
				var node: MasterBakedEffect = wind.node
				registered = registered and node.display.texture is AtlasTexture and node.get_child_count() == 1
				registered = registered and node.clip.cell[0] > 1 and node.clip.cell[1] > 1
		await process_frame
	check(planted and stable_body, "One planted forward step, no body rotation, vertical wobble or back-and-forth shuffle")
	check(static_art, "All reviewed sword smears play static production frames")
	check(registered, "Baked frames retain a fixed pivot and allocate no viewport or runtime mesh")
	check(checked_pause and room.dummy.contacts.size() == contact_count, "Development dummy receives exactly the designed number of production hit identities")
	check_source_registration(r)
	master._interrupt_for_special(0.0)
	check(is_zero_approx(master.animated_sprite.rotation), "Interrupt restores the body's normal rotation")
	room.reset_room()
	await process_frame
	check(room.specimen.get_child_count() == 2, "Reset removes the study, retained trails and specimen")
	check(save._config.encode_to_text() == before, "Pose study never changes story progress or inventory")
	current_scene = null
	room.free()
	expect_save_untouched()
	finish("MASTER POSE FLOW STUDY")

func check_source_registration(_rhythm: MasterClashRhythm) -> void:
	pass
