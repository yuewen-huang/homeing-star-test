extends "../../support/harness.gd"

func run() -> void:
	use_memory_progress()
	var clips := MasterBakedEffect.catalog()
	check(clips.size() == 15,"All twelve directional cuts and three air accompaniments are baked")
	var protected := true
	var aligned := true
	var dependencies := true
	var manual_source := true
	var count := 0
	for name: String in clips:
		var spec: Dictionary = clips[name]
		manual_source = manual_source and spec.get("art", "") == "user_edited_pre_painted_vfx"
		count += int(spec.frames)
		for time in spec.protected:
			var present := false
			for kept in spec.times: present = present or absf(float(time)-float(kept)) < 0.000001
			protected = protected and present
		for page: String in spec.pages:
			dependencies = dependencies and MasterBakedEffect.LIBRARY.get_meta("textures").has(page)
		var fx := MasterBakedEffect.new().configure(name)
		root.add_child(fx)
		var pivot := fx.display.position
		for time in spec.times:
			fx.setage(float(time))
			aligned = aligned and fx.display.position == pivot and fx.get_child_count() == 1
		fx.setage(fx.duration)
		aligned = aligned and not fx.visible and fx.is_done()
		fx.free()
	check(protected,"Exact authored contact, direction and ending times survive adaptive reduction")
	check(dependencies,"Every static texture is an explicit export dependency of the production library")
	check(manual_source,"Runtime library resolves the manually edited Aseprite manifest")
	check(aligned,"Variable-duration playback keeps one pivot, ends cleanly and builds no runtime viewport")
	check(count <= 110,"Art-frame budget removes at least half of the previous 221 shipped frames")
	var room = load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.select_boss(1)
	room.player.set_physics_process(false)
	room.player.position.x = 70
	var runtime_live := true
	for move: StringName in [&"inertia_combo",&"lunge_combo",&"air_qi_combo"]:
		for facing in [-1.0,1.0]:
			room.adapter._rebuild()
			var boss: MasterBoss = room.adapter.master
			boss.position.x = 640
			room.adapter.target.position.x = 640+facing*180
			boss.set_process(false)
			boss.attack_hitbox.set_physics_process(false)
			boss.start_clash_rhythm(move)
			for i in 80:
				boss._process(1.0/30.0)
				runtime_live = runtime_live and _no_baked_blade(boss)
	check(runtime_live,"Both facings use live slash trajectories; existing baked auxiliary accents remain available")
	room.free()
	current_scene = null
	expect_save_untouched()
	finish("MASTER BAKED EFFECTS")

func _no_baked_blade(node: Node) -> bool:
	if node is MasterBakedEffect:
		for name: String in MasterBakedEffect.catalog():
			if name.contains("/cut_") and node.clip == MasterBakedEffect.catalog()[name]: return false
	for child in node.get_children():
		if not _no_baked_blade(child): return false
	return true
