extends SceneTree
var failures := 0
var room: Node2D
var out := ""
var film: Array = []
var reports: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func capture(name: String) -> void:
    if DisplayServer.get_name()=="headless": return
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(out.path_join(name+".png"))
func walk(direction: float) -> void:
    Input.action_release("ui_left")
    Input.action_release("ui_right")
    if direction!=0: Input.action_press("ui_left" if direction<0 else "ui_right")
func run() -> void:
    out=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-ambush")
    DirAccess.make_dir_recursive_absolute(out)
    root.size=Vector2i(1280,720)
    room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    await process_frame
    for mode: String in ["walk","stand","parry","manual","manual_right"]:
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.select_combo(2)
        if mode.begins_with("manual"):
            room.adapter.boss.preview_target=Vector2(1120 if mode=="manual_right" else 688,room.FLOOR_Y)
            room.adapter.boss.play_ambush()
        else: room.set_combat_simulation(true)
        var actor: SandstormFighter=room.adapter.boss
        actor.set_process(false)
        var skill: SandstormAmbush=actor.ambush
        var counts := {"appeared":0,"kicked":0,"contacts":[],"frames":{},"finisher_appeared":0,"finisher_landed":0,"finisher_contacts":[]}
        skill.appeared.connect(func(_i: int):
            counts.appeared+=1
            check(skill.body.modulate.a==0,"Relocation must be invisible"))
        skill.kicked.connect(func(_i: int): counts.kicked+=1)
        skill.finisher_appeared.connect(func():
            counts.finisher_appeared+=1
            check(counts.kicked==4,"Finisher must follow all four kicks")
            check(skill.body.modulate.a==0,"Overhead relocation must be invisible")
            check(absf(skill.global_position.y-(room.FLOOR_Y-skill.FINISH_HEIGHT))<.01,"Wrong overhead height"))
        skill.finisher_landed.connect(func(): counts.finisher_landed+=1)
        skill.attack_hitbox.hit_resolved.connect(func(_v: Node,result: int): counts.contacts.append(result))
        skill.attack_hitbox.hit_resolved.connect(func(_v: Node,result: int):
            if skill.phase in [skill.Phase.FINISH_DROP,skill.Phase.FINISH_LAND]: counts.finisher_contacts.append(result))
        var health: int=room.player.combat_stats.health
        var held := 0.0
        var parried_count := 0
        var finisher_parried := false
        var last := skill.global_position
        var was_visible := true
        var last_time := 0.0
        var min_health := health
        var return_captured := false
        var return_facing := 0.0
        for tick in 900:
            if not is_instance_valid(skill): break
            if mode=="walk":
                var next := skill.facing if skill.phase==skill.Phase.ATTACK and skill.clock>.18 else 0.0
                if skill.phase in [skill.Phase.FINISH_WIND,skill.Phase.FINISH_DROP]:
                    next=1.0 if skill.locked_origin.x<640 else -1.0
                if next!=held:
                    walk(next)
                    held=next
                check(not room.player.is_invulnerable(),"walk test gained immunity")
            if mode=="parry" and skill.phase==skill.Phase.ATTACK and skill.clock>=skill.CONTACT-.09 and parried_count<skill.count:
                Input.action_press("parry")
                parried_count=skill.count
            elif mode=="parry" and skill.phase==skill.Phase.FINISH_DROP and skill.clock>=skill.FINISH_FALL-.09 and not finisher_parried:
                Input.action_press("parry")
                finisher_parried=true
            else: Input.action_release("parry")
            await physics_frame
            min_health=mini(min_health,room.player.combat_stats.health)
            if not is_instance_valid(skill): break
            check(skill.body.global_transform.y.y>0,"Body vertically inverted")
            check(absf(skill.body.global_transform.x.y)<.001,"Unexpected body rotation")
            if skill.phase==skill.Phase.CLEAR and skill.clock>0 and skill.body.visible:
                check(skill.body.modulate.a>.99,"Finisher recovery blinked before returning idle")
                var feet: Vector2=skill.body.to_global(skill.library.actions["待机"].feet-Vector2(128,128))
                check(absf(feet.y-room.FLOOR_Y)<.01,"Return idle feet detached from ground")
                return_facing=skill.facing
                if mode.begins_with("manual") and skill.clock>.4 and not return_captured:
                    return_captured=true
                    await capture("return_"+mode)
                    if not is_instance_valid(skill): break
            var visible_now: bool=skill.body.visible and skill.body.modulate.a>.05
            var speed_limit: float=skill.FINISH_HEIGHT*1.7/skill.FINISH_FALL if skill.phase in [skill.Phase.FINISH_DROP,skill.Phase.FINISH_LAND] else 32/skill.RELEASE_TIME
            if visible_now and was_visible and skill.elapsed-last_time<.035: check(skill.global_position.distance_to(last)<=maxf(12,speed_limit*(skill.elapsed-last_time)+.01),"Visible displacement exceeded the committed release speed")
            if skill.phase in [skill.Phase.FINISH_WIND,skill.Phase.FINISH_DROP]:
                check(absf(skill.global_position.x-skill.locked_origin.x)<.01,"Finisher retargeted while visible")
            if skill.phase==skill.Phase.FINISH_WIND:
                check(skill.global_position.distance_to(skill.locked_origin)<.01,"Raised-leg charge drifted")
                if skill.clock>=.07: check(skill.shown_frame==6,"Raised-leg hold changed pose")
            if skill.phase==skill.Phase.FINISH_LAND:
                if skill.clock<skill.FINISH_PLANT_HOLD: check(skill.shown_frame==9,"Planted impact pose released too early")
                var bottom: float=skill.finish_bottoms[skill.shown_frame]
                check(absf(skill.body.to_global(Vector2(82,bottom)-Vector2(128,128)).y-room.FLOOR_Y)<.01,"Finisher feet left the floor")
            last_time=skill.elapsed
            last=skill.global_position
            was_visible=visible_now
            if skill.phase==skill.Phase.ATTACK:
                counts.frames[skill.shown_frame]=true
                check(skill.shown_frame in [3,4,5,6,7],"Wrong kick frame")
            check(skill.veil.modulate.a<=.421,"Veil is too opaque")
            if mode=="walk" and tick%5==0:
                film.append({"file":"film_%04d.png"%tick,"time":skill.elapsed})
                await capture("film_%04d"%tick)
        walk(0)
        Input.action_release("parry")
        check(not is_instance_valid(skill),mode+": failed to finish")
        check(counts.appeared==4 and counts.kicked==4,mode+": incorrect attack count")
        check(counts.finisher_appeared==1 and counts.finisher_landed==1,mode+": missing or repeated finisher")
        check(counts.finisher_contacts.size()<=1,mode+": finisher hit twice")
        if mode in ["walk","manual","manual_right"]: check(min_health==health and counts.contacts.is_empty(),mode+": unexpected damage")
        if mode=="stand":
            check(min_health<health,"Standing control never hit")
            check(counts.finisher_contacts==[CombatHitResult.Type.NORMAL_HIT],"Standing control missed the finisher")
        if mode=="parry":
            check(CombatHitResult.Type.PARRY_SUCCESS in counts.contacts,"Real parry input failed")
            check(counts.finisher_contacts==[CombatHitResult.Type.PARRY_SUCCESS],"Finisher real parry input failed")
        check(return_facing!=0,mode+": return pose was not checked")
        if mode=="manual_right": check(return_facing==1,"Right-facing recovery not exercised")
        if mode=="manual": check(return_facing==-1,"Left-facing recovery not exercised")
        reports.append({"mode":mode,"minimum_health":min_health,"return_facing":return_facing,"counts":counts})
        print("AMBUSH ",mode," hp=",min_health," contacts=",counts.contacts)
    room.select_combo(2)
    room.play_action(SandstormFighter.COMBOS.size()+2)
    var previous: Node=room.adapter.boss.ambush
    var overlay: Node=previous.veil_layer
    room.reset_room()
    await process_frame
    check(not is_instance_valid(previous) and not is_instance_valid(overlay),"Reset leaked veil")
    FileAccess.open(out.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":reports},"\t"))
    if DisplayServer.get_name()!="headless": FileAccess.open(out.path_join("film.json"),FileAccess.WRITE).store_string(JSON.stringify(film))
    print("SANDSTORM AMBUSH: ",failures," failures")
    room.free()
    quit(0 if failures==0 else 1)
