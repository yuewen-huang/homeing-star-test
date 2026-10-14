extends SceneTree

var room
var deer: DeerBoss
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ", message)

func tick(count: int) -> void:
	for i in count:
		var delta := Engine.time_scale / 60.0
		deer._physics_process(delta)
		room._physics_process(delta)
		deer.vfx._process(delta)

## Wait in real time until CombatFeedback restores normal speed after a hit-stop.
func wait_hit_stop() -> void:
	await process_frame
	while Engine.time_scale < 1.0:
		await process_frame

func snapshot(name: String) -> void:
	if output.is_empty(): return
	room._process(0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): output=args[0];DirAccess.make_dir_recursive_absolute(output)
	var save_exists := FileAccess.file_exists(SaveProgressService.SAVE_PATH)
	var saved := FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH) if save_exists else PackedByteArray()
	room=load("res://scenes/dev/boss_development_room.tscn").instantiate()
	root.add_child(room);current_scene=room
	await process_frame;await process_frame
	room.set_physics_process(false);room.player.set_physics_process(false)
	deer=room.adapter.deer;deer.set_physics_process(false);deer.vfx.set_process(false)
	room.select_combo(2)
	check(room.adapter.action_names().size()==5 and room.charge_button.visible and room.ultimate_row.visible and not room.item_button.visible and not room.item_available.visible,"Wind has five manual actions and no inherited snare controls")
	var fx:=deer.clash_phase.pressure_fx
	check(DeerWindPressureFX.data().frames.size()==26 and (DeerWindPressureFX.ART.get_meta("texture") as Texture2D).resource_path.ends_with("deer_painted/wind_pressure.png"),"Wind uses the user's 26-frame texture rather than generated arcs")
	room.play_action(2);tick(36)
	check(deer.animated_sprite.animation==&"bind_push_ING" and deer.animated_sprite.frame==3 and fx.source_frame==3 and room.dummy.contacts.size()==1,"First painted peak and body F03 coincide with the first real damage beat")
	check(fx.position==deer.position and fx.sprite.position==Vector2(-82,-256) and fx.scale==Vector2(-1.4,1.4),"Left-facing art keeps the authored canvas pivot and common 1.4 scale")
	check(is_equal_approx(fx.sprite.modulate.a,110.0/255.0),"Native per-cel opacity is retained without doubling alpha")
	await snapshot("pressure_peak_1")
	tick(20)
	check(deer.animated_sprite.frame==10 and fx.source_frame==10 and room.dummy.contacts.size()==2,"Second painted peak F10 and second damage beat stay synchronized")
	await snapshot("pressure_peak_2")
	tick(19)
	check(deer.animated_sprite.frame==17 and fx.source_frame==17 and room.dummy.contacts.size()==3,"Third painted peak F17 and third damage beat stay synchronized")
	await snapshot("pressure_peak_3")
	var before_time:=deer.clash_phase.elapsed
	var before_frame:=fx.source_frame
	deer._parry_pause=0.2;tick(5)
	check(is_equal_approx(deer.clash_phase.elapsed,before_time) and fx.source_frame==before_frame,"Existing parry pause freezes the painted effect and body together")
	deer._parry_pause=0;tick(28)
	check(deer.animated_sprite.animation==&"thrust_END" and fx.sprite.modulate.a<110.0/255.0,"Standalone pressure uses the compatible END while fading the painted tail")
	await snapshot("pressure_release")
	tick(100)
	check(deer.state==DeerBoss.State.IDLE and not fx.visible and deer.attack_hitbox.attack==null,"Standalone recovery clears painted tails and real damage")
	room.play_action(3)
	check(deer.position==Vector2(820,555),"Standalone flick uses the standard manual starting position rather than the charge slot's carried position")
	tick(150)
	check(room.dummy.contacts.size()==1 and room.dummy.contacts[0].clip=="flick_lift_ING" and room.dummy.contacts[0].damage==14,"Standalone flick now opens one actual 14-damage upward contact")
	# Key 5 defaults to the improvised combo (v0.3); this checks the authored pressure combo.
	room.select_combo_library(DeerClashPhase.LIBRARY.find(&"pressure_flick_red"))
	for target in [688,1000]:
		room.dummy_x.value=target;room.play_action(4)
		var locked_direction:=deer.direction
		var previous_step:=-1
		var linked:=false
		var red_cued:=false
		var normal_four:=true
		var positions_stable:=true
		var last_position:=deer.position
		for i in 340:
			tick(1)
			# v0.3 steps in and lunges per strike; it must still never jump or turn around.
			positions_stable=positions_stable and absf(deer.position.x-last_position.x)<=40.0 and deer.direction==locked_direction
			last_position=deer.position
			if deer.clash_phase.step_index>=0 and deer.clash_phase.step_index!=previous_step:
				if deer.clash_phase.step_index==1:
					linked=deer.animated_sprite.animation==&"flick_sweep_ING" and not fx.visible
					await snapshot("combo_%d_low_link"%target)
				previous_step=deer.clash_phase.step_index
			if deer.attack_hitbox.attack!=null and deer.clash_phase.step_index in [0,1]:
				normal_four=normal_four and deer.attack_hitbox.attack.danger_type==CombatAttackData.DangerType.NORMAL
			if deer.clash_phase.step_index==2 and deer.vfx.red_warning.visible:
				red_cued=red_cued or room.dummy.contacts.size()==4
			if i in [129,210,240]:await snapshot("combo_%d_%03d"%[target,i])
		check(linked,"Full combo joins the low pressure pose directly to the authored sweep")
		check(positions_stable,"Full combo neither teleports nor turns around between attacks")
		check(red_cued and normal_four,"Four ordinary parry contacts precede a clearly cued red finisher")
		check(room.dummy.contacts.size()==5,"Full combo reaches five distinct real contacts in direction %d"%locked_direction)
		if room.dummy.contacts.size()==5:
			var hits: Array=room.dummy.contacts
			check([hits[0].damage,hits[1].damage,hits[2].damage,hits[3].damage,hits[4].damage]==[12,12,12,14,20],"Combo damage remains three pressure beats, one flick and one red finisher")
			check(hits[3].clip=="flick_lift_ING" and hits[4].clip=="rear_gore_ING" and hits[3].first_time>hits[2].first_time+0.7 and hits[4].first_time>hits[3].first_time+1.3,"Delayed lift and red startup provide readable rhythm changes")
			var ids: Array=[]
			for hit in hits:
				if not ids.has(hit.key):ids.append(hit.key)
			check(ids.size()==5,"Every combo contact has its own single-hit attack ID")
			print("COMBO CONTACTS ",target," ",JSON.stringify(hits))
		check(deer.state==DeerBoss.State.IDLE and deer.attack_hitbox.attack==null and not fx.visible,"Full combo finishes in clean manual idle")
	room.dummy_x.value=688
	for interrupt_time in [0.4,0.7,1.8,3.1]:
		room.play_action(4);tick(roundi(interrupt_time*60))
		var contacts: int=room.dummy.contacts.size()
		deer.enter_stagger(2.0);tick(180)
		check(room.dummy.contacts.size()==contacts and deer.clash_phase.steps.is_empty() and deer.attack_hitbox.attack==null and not fx.visible,"Stagger cancels all pending attacks at %.1fs"%interrupt_time)
	room.play_action(4);tick(56)
	deer.combat_stats.restore_poise()
	var ordinary_attack:=deer.attack_hitbox.attack
	deer.on_attack_parried(ordinary_attack,deer.position)
	# Let the real feedback hit-stop finish (it runs in unscaled time) before manual simulation.
	await wait_hit_stop()
	tick(340)
	check(room.dummy.contacts.size()==5 and deer.state==DeerBoss.State.IDLE,"An existing ordinary parry pauses then resumes the pending combo")
	room.play_action(4);tick(240)
	check(deer.attack_hitbox.attack!=null and deer.attack_hitbox.attack.danger_type==CombatAttackData.DangerType.COUNTERABLE_DANGER,"Combo finisher uses the existing red danger type")
	if deer.attack_hitbox.attack!=null:
		deer.on_attack_parried(deer.attack_hitbox.attack,deer.position)
		check(deer.state==DeerBoss.State.STAGGER and deer.red_parry_hold and deer.clash_phase.steps.is_empty(),"Existing red parry clears the combo and enters its normal stagger")
		deer.red_parry_hold=false
		await wait_hit_stop()
	for speed in [0,1]:
		room.set_playback_speed(speed);room.play_action(4);tick(1500 if speed==0 else 750)
		check(room.dummy.contacts.size()==5 and deer.state==DeerBoss.State.IDLE,"Slow playback preserves all five contacts and clean recovery")
	room.set_playback_speed(2)
	room.dummy_x.value=300;room.play_action(4);tick(340)
	check(room.dummy.contacts.is_empty(),"Far dummy is outside all combo hitboxes")
	room.dummy_x.value=688;room.play_action(4);tick(35)
	room.play_action(0);tick(180)
	check(room.dummy.contacts.size()==1 and deer.clash_phase.action_id==&"thrust","Replaying a single action cancels the entire queued combo")
	room.play_action(4);tick(40)
	room.select_combo(0);tick(340)
	check(deer.phase==1 and not fx.visible and deer.clash_phase.steps.is_empty(),"Changing phase clears pending wind attacks and art")
	check(not room.adapter.telemetry().contains("雾阶段大招"),"Returning from wind combo cannot leave the adapter in mist-hunt preview mode")
	room.select_combo(2)
	check(deer.start_phase_combo() and deer.clash_phase.action_id==&"pressure_flick_red","Production phase-combo entry shares the same real three-stage chain")
	room.reset_room();await process_frame;await process_frame
	check(room.adapter.deer.phase==3 and room.adapter.deer.clash_phase.steps.is_empty(),"Reset preserves phase and removes queued wind steps")
	room.select_boss(1);await process_frame;await process_frame
	check(not is_instance_valid(fx),"Switching BOSS frees the painted layer with the specimen subtree")
	check(room.player.combat_stats.health==100,"BOSS-only development leaves the observer player unharmed")
	check(FileAccess.file_exists(SaveProgressService.SAVE_PATH)==save_exists and (not save_exists or FileAccess.get_file_as_bytes(SaveProgressService.SAVE_PATH)==saved),"Painted integration and combo inspection leave saved progress unchanged")
	current_scene=null;room.free()
	print("WIND COMBO: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
