extends SceneTree
## Render the real shared feedback in the development room; no save writes.
var room
var feedback: CombatFeedbackService
var output := ""


func _initialize() -> void:
	call_deferred("run")


func clean() -> void:
	feedback.hit_stop_serial += 1
	Engine.time_scale = 1.0
	feedback.screen_fx.clear()
	feedback._reset_punch()
	feedback.shake_remaining = 0
	if is_instance_valid(feedback.shake_target):
		feedback.shake_target.offset = feedback.shake_base_offset
	for effect in get_nodes_in_group(CombatImpactEffect.GROUP):
		effect.free()


func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func freeze_boss() -> DamageReceiver2D:
	await process_frame
	await process_frame
	await process_frame
	var boss := room.adapter.boss as DamageReceiver2D
	boss.set_process(false)
	boss.set_physics_process(false)
	var sprite := boss.get_hit_reaction_visual() as AnimatedSprite2D
	sprite.pause()
	if boss is DeerBoss:
		(boss as DeerBoss).vfx.set_process(false)
	return boss


func render_event(receiver: DamageReceiver2D, event: int, label: String, mirrored := false) -> void:
	clean()
	feedback.clear_body_reaction(receiver.get_hit_reaction_visual())
	var at := receiver.global_position + Vector2(0,-120 if receiver is DeerBoss else -105)
	var source := at + Vector2(180 if mirrored else -180, 0)
	receiver.set("poise_broken", event in [CombatImpactEffect.Kind.BROKEN_HIT, CombatImpactEffect.Kind.POISE_BREAK])
	receiver.set_meta(CombatFeedbackService.WAS_BROKEN_META, event == CombatImpactEffect.Kind.BROKEN_HIT)
	if event in [CombatImpactEffect.Kind.PARRY, CombatImpactEffect.Kind.RED_PARRY]:
		var danger := CombatAttackData.DangerType.COUNTERABLE_DANGER if event == CombatImpactEffect.Kind.RED_PARRY else CombatAttackData.DangerType.NORMAL
		var attack := CombatAttackData.new(&"preview",receiver,12,12,180,0,danger)
		# Return force points into the attacker, opposite the incoming blow.
		at.x = receiver.global_position.x + (40 if mirrored else -40)
		feedback.emit_parry_success(receiver,attack,at)
	else:
		feedback.emit_receiver_hit(receiver,at,source)
	var effects := get_nodes_in_group(CombatImpactEffect.GROUP)
	assert(effects.size()==1)
	var effect := effects[0] as CombatImpactEffect
	effect.pause()
	await capture(label+"_contact")
	feedback.hit_stop_serial += 1
	Engine.time_scale = 1.0
	feedback.screen_fx.clear()
	feedback._reset_punch()
	feedback.shake_remaining=0
	feedback.shake_target.offset=feedback.shake_base_offset
	feedback.clear_body_reaction(receiver.get_hit_reaction_visual())
	var count := effect.sprite_frames.get_frame_count(effect.animation)
	for frame in [mini(1,count-1),count/2,count-1]:
		effect.set_frame_and_progress(frame,0)
		await capture(label+"_frame_%02d"%frame)


func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	var existed:=FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved:=FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if existed else PackedByteArray()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room);current_scene=room
	feedback=root.get_node("CombatFeedback")
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	var deer: DamageReceiver2D=await freeze_boss()
	room.player.position=Vector2(640,555)
	room._process(0)
	var labels := ["normal_hit","broken_hit","parry","red_parry","poise_break"]
	for event in labels.size():
		await render_event(deer,event,"deer_"+labels[event])
	await render_event(deer,CombatImpactEffect.Kind.RED_PARRY,"deer_red_mirrored",true)
	clean()
	room.select_boss(1)
	var master: DamageReceiver2D=await freeze_boss()
	await render_event(master,CombatImpactEffect.Kind.NORMAL_HIT,"master_normal")
	await render_event(master,CombatImpactEffect.Kind.RED_PARRY,"master_red")
	clean()
	room.adapter.boss.hide()
	var slime := load("res://scenes/sideview/back_alley_slime.tscn").instantiate() as BackAlleySlime
	slime.health=20;slime.position=Vector2(800,555)
	room.add_child(slime);slime.set_process(false);slime.animated_sprite.pause()
	slime.receive_hit(1,Vector2(640,555))
	var effect := get_nodes_in_group(CombatImpactEffect.GROUP)[0] as CombatImpactEffect
	effect.pause();await capture("slime_normal_contact")
	feedback.hit_stop_serial += 1;Engine.time_scale=1
	feedback.clear_body_reaction(slime.animated_sprite)
	slime.animated_sprite.pause()
	await capture("slime_normal_body")
	clean();slime.free()
	var bat := load("res://scenes/sideview/back_alley_bat.tscn").instantiate() as BackAlleyBat
	bat.health=20;room.add_child(bat);bat.position=Vector2(800,450)
	bat.set_process(false);bat.animated_sprite.pause()
	bat.receive_hit(1,Vector2(640,450))
	effect=get_nodes_in_group(CombatImpactEffect.GROUP)[0] as CombatImpactEffect
	effect.pause();await capture("bat_normal_contact")
	feedback.hit_stop_serial += 1;Engine.time_scale=1
	feedback.clear_body_reaction(bat.animated_sprite)
	bat.animated_sprite.pause()
	await capture("bat_normal_body")
	clean();bat.free()
	assert(FileAccess.file_exists(SaveProgressService.SAVE_PATH)==existed and (not existed or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)==saved))
	print("PASS Native shared art preview: deer, master, slime and bat; saved progress unchanged")
	current_scene=null;room.free();quit()
