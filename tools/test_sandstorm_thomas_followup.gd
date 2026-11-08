extends SceneTree
var failures:=0
var room: BossDevelopmentRoom
var out:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-thomas-followup"
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        push_error(message)
func dodge(pressed: bool) -> void:
    var e:=InputEventKey.new()
    e.physical_keycode=KEY_L
    e.pressed=pressed
    Input.parse_input_event(e)
func run() -> void:
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--tag="): out=out.path_join(arg.trim_prefix("--tag="))
    DirAccess.make_dir_recursive_absolute(out)
    root.size=Vector2i(1280,720)
    room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    root.get_node("BattleAssist").set_difficulty(1)
    var modes: Array=["near","near_right","edge","edge_left","far","leave","walk_out","dodge","parry","finish_parry","manual"]
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--only="): modes=[arg.trim_prefix("--only=")]
    if DisplayServer.get_name()!="headless": modes=["near"]
    if "--knee-only" in OS.get_cmdline_user_args():
        modes.erase("far")
        modes.erase("leave")
    for mode: String in modes:
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.select_combo(1)
        if mode=="manual": room.adapter.boss.play_thomas()
        else: room.set_combat_simulation(true)
        room.player.global_position=Vector2(360 if mode=="far" else 670,room.FLOOR_Y)
        var actor: SandstormFighter=room.adapter.boss
        actor.set_process(false)
        var skill: SandstormThomas=actor.thomas
        if mode=="near_right": room.player.global_position.x=970
        if mode=="edge":
            actor.position.x+=280
            skill.global_position.x+=280
            room.player.global_position.x=1180
        if mode=="edge_left":
            actor.position.x-=620
            skill.global_position.x-=620
            room.player.global_position.x=120
        if "--knee-only" in OS.get_cmdline_user_args():
            skill.elapsed=skill._span(skill.config.intro_durations)+int(skill.config.spin_cycles)*skill._span(skill.config.loop_durations)
            skill.next_emission=INF
            skill.emitted=3
            skill.branch_checked=true
            skill._start_followup(room.player.position)
        var state: Dictionary={"bound":false,"gold":false,"strikes":0,"ghosts":0,"contacts":[],"start_hp":100,"frames":[],"signature":{}}
        var pressed:=false
        var last:=Vector2.ZERO
        var teleports:=0
        var first_kick_direction:=0.0
        var previous_knee_vy:=-INF
        for tick in 1100:
            if not is_instance_valid(skill): break
            if mode=="leave" and skill.elapsed>4.50: Input.action_press("ui_left")
            var f: SandstormThomasFollowup=skill.follow
            if is_instance_valid(f):
                if not state.bound:
                    state.bound=true
                    state.start_hp=room.player.combat_stats.health
                    last=f.global_position
                    f.strike_released.connect(func(_number: int):
                        state.strikes+=1
                        if _number==4:
                            check(f.signature.scorpion_phase=="hold","Tail not in contact pose at finisher release")
                            check(f.signature.scorpion_tip().distance_to(Vector2(f.global_position.x,f.floor_y))<.02,"Tail contact differs from actual finisher landing")
                        if f.combat_enabled and _number==1: check(f.attack_hitbox.attack.danger_type==CombatAttackData.DangerType.UNPARRYABLE_DANGER,"Opening knee is not gold"))
                    f.attack_hitbox.hit_resolved.connect(func(_victim: Node,result: int):
                        var gap:=absf(room.player.global_position.x-f.global_position.x)
                        state.contacts.append({"strike":f.serial,"result":result,"player_y":room.player.global_position.y,"gap":gap})
                        if result==CombatHitResult.Type.NORMAL_HIT:
                            if f.serial==1: check(gap<64,"Knee hit before the knee reached the victim")
                            if f.serial in [2,3]:
                                check(gap>60 and gap<165,"Air kick contact missed the extended leg")
                                check((room.player.global_position.x-f.global_position.x)*f.facing>60,"Kick faces away from victim")
                            if f.serial==4: check(f.phase==f.Phase.LAND,"Elbow shockwave hit before landing"))
                state.gold=state.gold or f.danger.visible
                state.ghosts=maxi(state.ghosts,f.ghost_count)
                state.signature=f.signature.emitted.duplicate()
                if is_instance_valid(f.signature.scorpion_sprite):
                    var fx:=f.signature
                    check(fx.scorpion_sprite.global_position.distance_to(Vector2(f.locked_origin.x,f.floor_y))<.02,"Scorpion body followed the falling/recovering boss")
                    check(signf(fx.scorpion_sprite.scale.x)==f.facing,"Scorpion reflection lost attack facing")
                    if f.phase==f.Phase.SLAM_WIND:
                        check(fx.scorpion_phase=="wind","Tail wind-up clock is not bound to the attack")
                        check(fx.scorpion_tip().y<f.floor_y-40,"Tail hit the floor during wind-up")
                    elif f.phase==f.Phase.SLAM:
                        check(fx.scorpion_phase=="strike","Tail did not follow descending attack")
                        check(fx.scorpion_tip().y<f.floor_y-.01,"Tail contacted before the fighter landed")
                    elif f.phase==f.Phase.LAND and f.clock<f.LAND_HOLD:
                        check(fx.scorpion_phase=="hold","Tail failed to hold with landing hit-stop")
                        check(fx.scorpion_tip().distance_to(f.landing_origin)<.02,"Tail drifted away from landing impact")
                        check(fx.emitted.get("slam_impact",0)==1,"Tail contact and ground impact were separated")
                for visual: Dictionary in f.signature.live:
                    check(visual.sprite.z_index>room.z_index and visual.sprite.z_index<f.body.z_index and visual.sprite.z_index<room.player.z_index,"Sand spectacle was hidden by background or covered real combatants")
                    check(visual.sprite.global_position.is_finite(),"Signature effect lost its world origin")
                for ghost: Dictionary in f.ghosts:
                    check(ghost.sprite.material is ShaderMaterial,"Continuing ghost has no sand erosion")
                if f.phase==f.Phase.KNEE:
                    check(f.flight_velocity.y>=previous_knee_vy-.01,"Knee contact caused a second upward launch")
                    previous_knee_vy=f.flight_velocity.y
                if mode=="walk_out" and f.phase==f.Phase.CHARGE and f.clock>.10: Input.action_press("ui_left")
                if mode=="walk_out": check(not room.player.is_invulnerable(),"Walk escape acquired immunity")
                if mode in ["dodge","parry"] and not pressed and f.phase==f.Phase.CHARGE and f.clock>=.56:
                    pressed=true
                    if mode=="dodge": dodge(true)
                    else: Input.action_press("parry")
                else:
                    dodge(false)
                    Input.action_release("parry")
                if mode=="finish_parry" and not pressed and f.phase in [f.Phase.SLAM_WIND,f.Phase.SLAM] and not room.player.hit_reaction_active:
                    pressed=true
                    Input.action_press("parry")
                    print("FINISH PARRY INPUT time=",f.elapsed," hit_reaction=",room.player.hit_reaction_active," air=",room.player.air_state," y=",room.player.position.y)
                if f.teleport_count==teleports:
                    check(f.global_position.distance_to(last)<55,"Visible actor jumped without a flash step")
                else:
                    check(f.teleport_count==teleports+1,"Multiple relocation steps in one update")
                    var event: Dictionary=f.teleport_events.back()
                    check(event.hidden,"Relocation occurred while body was visible")
                    check(f.ghost_count>0,"Flash step left no outgoing silhouette")
                    teleports=f.teleport_count
                last=f.global_position
                if f.phase==f.Phase.FLASH:
                    check(not f.body.visible and not f.attack_hitbox.monitoring,"Invisible relocation can still strike")
                if f.phase==f.Phase.KICK: first_kick_direction=f.facing
                if f.phase==f.Phase.RETURN_KICK:
                    check(f.facing==-first_kick_direction,"Return kick failed to reverse direction")
                if f.phase==f.Phase.SLAM:
                    check(absf(f.global_position.x-f.locked_origin.x)<.01,"Elbow chases sideways during its fall")
                if f.phase==f.Phase.LAND and f.grounded():
                    var bottom: float=f.elbow_bottoms[f.shown_frame]
                    check(absf(f.body.to_global(Vector2(128,bottom)-Vector2(128,128)).y-room.FLOOR_Y)<.01,"Elbow support left the floor")
                if f.phase==f.Phase.LAND:
                    var source_origin:=f.body.to_global(Vector2(-128,-128))
                    check(absf(source_origin.x-(f.landing_origin.x-f.facing*197*f.SCALE))<.01,"Recovery changed drawing origin when support limb changed")
                if DisplayServer.get_name()!="headless" and tick%2==0:
                    state.frames.append({"file":"air_%04d.png"%tick,"phase":f.phase,"time":f.elapsed,"sample":f.sample(),"root":[f.global_position.x,f.global_position.y],"velocity":[f.flight_velocity.x,f.flight_velocity.y]})
                    await RenderingServer.frame_post_draw
                    root.get_texture().get_image().save_png(out.path_join("air_%04d.png"%tick))
            await physics_frame
        Input.action_release("ui_left")
        Input.action_release("parry")
        dodge(false)
        check(actor.looping_idle and absf(actor._feet().y-room.FLOOR_Y)<.01,mode+": did not return to arena floor")
        if mode in ["far","leave"]: check(not state.bound,mode+": ranged target incorrectly triggered followup")
        elif mode in ["walk_out","dodge"]:
            check(state.bound and state.strikes==1 and teleports==0,mode+": missed knee still pursued the player")
            check(state.signature.is_empty(),mode+": whiff displayed an unearned finisher")
        else:
            check(state.bound and state.strikes==4 and state.ghosts>=5,mode+": incomplete air sequence")
            check(state.gold,mode+": gold cue never appeared")
            check(teleports==3,mode+": missing authored flash step")
            check(state.signature.get("kick",0)==2 and state.signature.get("scorpion",0)==1,mode+": missing kick winds or finisher")
            check(state.signature.get("slam_impact",0)==1,mode+": missing actual landing impact")
            check(state.signature.get("arrival",0)==3 and state.signature.get("peel_knee",0)==1 and state.signature.get("peel_roll",0)==1 and state.signature.get("peel_kick",0)==1,mode+": missing sand flash handoff")
        if mode in ["near","near_right","edge","edge_left"]: check(state.contacts.size()==4,mode+": air sequence failed to reach the actual launched player")
        if mode in ["walk_out","manual"]: check(state.contacts.is_empty(),mode+": unexpected air hit")
        if mode=="parry":
            for hit in state.contacts:
                if hit.strike==1: check(hit.result!=CombatHitResult.Type.PARRY_SUCCESS,"Gold knee was parried")
        if mode=="dodge": check(room.player.combat_stats.health>=int(state.start_hp),"Actual dodge failed to escape gold followup")
        if mode=="finish_parry":
            check(state.contacts.any(func(hit: Dictionary): return hit.strike==4 and hit.result==CombatHitResult.Type.PARRY_SUCCESS),"Grounded victim could not parry the telegraphed elbow finisher")
        var summary: Dictionary=state.duplicate()
        summary.erase("frames")
        print("THOMAS FOLLOWUP ",mode," ",JSON.stringify(summary))
        FileAccess.open(out.path_join(mode+".json"),FileAccess.WRITE).store_string(JSON.stringify(state))
    # Reset mid-flash and mid-finisher: top-level decorative children must still
    # belong to the attack and disappear together with it.
    for wanted: int in [SandstormThomasFollowup.Phase.FLASH,SandstormThomasFollowup.Phase.SLAM_WIND]:
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.select_combo(1)
        room.set_combat_simulation(true)
        room.player.position=Vector2(670,room.FLOOR_Y)
        var actor: SandstormFighter=room.adapter.boss
        actor.set_process(false)
        var skill: SandstormThomas=actor.thomas
        skill.elapsed=skill._span(skill.config.intro_durations)+int(skill.config.spin_cycles)*skill._span(skill.config.loop_durations)
        skill.next_emission=INF
        skill.emitted=3
        skill.branch_checked=true
        skill._start_followup(room.player.position)
        var follow: SandstormThomasFollowup=skill.follow
        for tick in 300:
            if follow.phase==wanted: break
            await physics_frame
        check(follow.phase==wanted,"Reset fixture never reached target effect phase")
        var fx:=follow.signature
        var sprites: Array=[]
        for entry: Dictionary in fx.live: sprites.append(entry.sprite)
        check(not sprites.is_empty(),"Reset fixture had no live signature effect")
        room.reset_room()
        await process_frame
        await process_frame
        check(not is_instance_valid(fx),"Reset leaked signature effect owner")
        for sprite in sprites: check(not is_instance_valid(sprite),"Reset leaked top-level sand effect")
    print("SANDSTORM THOMAS FOLLOWUP: ",failures," failures")
    room.free()
    quit(1 if failures else 0)
