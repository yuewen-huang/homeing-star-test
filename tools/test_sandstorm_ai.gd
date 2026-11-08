extends SceneTree
var failures:=0
var room: Node2D
var out:=""
var held:=0.0
var film: Array=[]
var contacts: Array=[]
var bound: Dictionary={}
var parry_keys: Dictionary={}
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
    if not ok:
        failures+=1
        push_error(message)
func walk(direction: float) -> void:
    if direction==held: return
    held=direction
    Input.action_release("ui_left")
    Input.action_release("ui_right")
    if direction!=0: Input.action_press("ui_left" if direction<0 else "ui_right")
func attack(pressed: bool) -> void:
    var event:=InputEventMouseButton.new()
    event.button_index=MOUSE_BUTTON_LEFT
    event.pressed=pressed
    Input.parse_input_event(event)
func bind_hitbox(box: CombatHitbox2D,label: String) -> void:
    if bound.has(box.get_instance_id()): return
    bound[box.get_instance_id()]=true
    box.hit_resolved.connect(func(_victim: Node,result: int): contacts.append({"action":label,"result":result}))
func parry(key: String,until: float) -> void:
    if until<.11 and until>=0 and not parry_keys.has(key):
        parry_keys[key]=true
        Input.action_press("parry")
func capture(name: String) -> void:
    if DisplayServer.get_name()=="headless": return
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(out.path_join(name+".png"))
func run() -> void:
    out=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-ai")
    DirAccess.make_dir_recursive_absolute(out)
    root.size=Vector2i(1280,720)
    room=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    await process_frame
    root.get_node("BattleAssist").set_difficulty(1) # Every parry is actual input.
    # Authored melee attacks must reach a stationary real Lan at their contact geometry.
    for key: String in ["pressure","counter"]:
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.set_combat_simulation(true)
        var actor: SandstormFighter=room.adapter.boss
        actor.set_process(false)
        room.player.global_position=Vector2(688,room.FLOOR_Y)
        actor.play_combat_combo(key)
        var skill: SandstormMelee=actor.melee
        bind_hitbox(skill.attack_hitbox,key)
        var hp: int=room.player.combat_stats.health
        for tick in 400:
            await physics_frame
            if not is_instance_valid(skill): break
        check(not is_instance_valid(skill),key+": melee did not finish")
        check(room.player.combat_stats.health<hp,key+": no real melee collision")
        print("MELEE ",key," HP ",room.player.combat_stats.health)
    if "--melee-only" in OS.get_cmdline_user_args():
        print("MELEE CHECK: ",failures," failures")
        room.free()
        quit(0 if failures==0 else 1)
        return
    room.set_combat_simulation(false)
    room.reset_room()
    room.select_combo(3)
    room.adapter.boss.brain.rng.seed=773
    if "--low-health" in OS.get_cmdline_user_args(): room.adapter.boss.combat_stats.set_health_ratio(.45)
    room.set_combat_simulation(true)
    var actor: SandstormFighter=room.adapter.boss
    var starting_hp: int=actor.combat_stats.health
    if "--low-health" in OS.get_cmdline_user_args():
        check(actor.brain.recovery(.45)<actor.brain.recovery(1),"Low HP pressure did not increase")
    var min_player_hp:=100
    var max_speed:=0.0
    var last_size:=0
    var until_attack:=0.0
    for tick in 4800:
        Input.action_release("parry")
        attack(false)
        var direction:=0.0
        if actor.defeated_state: break
        check(not root.get_node("BattleAssist").player_invincible,"AI test used global immunity")
        if is_instance_valid(actor.ambush):
            var skill: SandstormAmbush=actor.ambush
            bind_hitbox(skill.attack_hitbox,"ambush")
            if skill.phase==skill.Phase.ATTACK: parry("a%d_%d"%[skill.get_instance_id(),skill.count],skill.CONTACT-skill.clock)
            elif skill.phase==skill.Phase.FINISH_DROP: parry("af%d"%skill.get_instance_id(),skill.FINISH_FALL-skill.clock)
        elif is_instance_valid(actor.descent):
            var skill: SandstormDescent=actor.descent
            bind_hitbox(skill.attack_hitbox,"descent")
            if skill.phase==skill.Phase.FALL: parry("d%d_%d"%[skill.get_instance_id(),skill.drop_index],skill.FALL_TIME-skill.clock)
            elif skill.phase==skill.Phase.PUNCH:
                parry("p%d"%skill.get_instance_id(),skill.time_to_punch_contact())
        elif is_instance_valid(actor.thomas):
            var skill: SandstormThomas=actor.thomas
            for wave in skill.waves: bind_hitbox(wave.hitbox,"thomas")
            var px: float=room.player.global_position.x
            var side: float=-1 if px<skill.global_position.x else 1
            var radius: float=270 if absf(px-skill.global_position.x)<400 else 530
            var goal: float=clampf(skill.global_position.x+side*(radius+maxf(0,skill.elapsed-1.848)*70),64,1216)
            if absf(goal-px)>15: direction=signf(goal-px)
        elif is_instance_valid(actor.melee):
            var skill: SandstormMelee=actor.melee
            bind_hitbox(skill.attack_hitbox,"melee")
            var clip: Node2D=skill.playback.current
            for i in clip.document.events.size():
                var when: float=clip._contact_at(clip.document.events[i])
                if clip.body_limit>=0 and when>=clip.body_limit: continue
                parry("m%d_%d_%d"%[skill.get_instance_id(),skill.playback.slot,i],when-clip.clock+maxf(0,skill.windup-skill.elapsed))
        else:
            var difference: float=actor._feet().x-room.player.global_position.x
            if absf(difference)>90: direction=signf(difference)
            elif tick%20==0: attack(true)
        walk(direction)
        await physics_frame
        min_player_hp=mini(min_player_hp,room.player.combat_stats.health)
        max_speed=maxf(max_speed,absf(room.player.velocity.x))
        check(room.player.is_physics_processing(),"Player physics was disabled")
        var active:=int(is_instance_valid(actor.ambush))+int(is_instance_valid(actor.thomas))+int(is_instance_valid(actor.descent))+int(is_instance_valid(actor.melee))
        check(active<=1,"AI stacked unrelated casts")
        for tail in actor.retired_melee:
            if is_instance_valid(tail): check(not tail.attack_hitbox.monitoring,"Decorative tail retained damage")
        if actor.brain.history.size()!=last_size:
            last_size=actor.brain.history.size()
            print("AI ACTION ",actor.brain.history[-1]," player HP ",room.player.combat_stats.health," boss HP ",actor.combat_stats.health)
        if tick%12==0 and tick<2100:
            film.append({"file":"film_%04d.png"%tick,"time":actor.brain.clock})
            await capture("film_%04d"%tick)
    walk(0)
    attack(false)
    Input.action_release("parry")
    var used: Dictionary={}
    for entry: Dictionary in actor.brain.history: used[entry.action]=true
    check(actor.brain.history.size()>=8,"Too little autonomous pressure")
    check(used.has("ambush") and used.has("thomas") and used.has("descent"),"AI failed to exercise all three skills")
    check(used.has("pressure") or used.has("counter"),"AI never used melee")
    check(actor.combat_stats.health<starting_hp,"Real player attacks could not damage boss")
    check(actor.combat_stats.poise==actor.combat_stats.max_poise,"Unexpected poise damage")
    var history:=actor.brain.history.duplicate(true)
    var end_hp: int=actor.combat_stats.health
    # Explicit lifecycle fixture: defeat must clear its owned attack and screen overlay.
    actor.hurtbox.monitorable=true
    actor.receive_hit(10000,room.player.global_position)
    await process_frame
    check(actor.defeated_state,"Boss defeat failed")
    check(not is_instance_valid(actor.ambush) and not is_instance_valid(actor.melee) and not is_instance_valid(actor.thomas) and not is_instance_valid(actor.descent),"Defeat leaked attack")
    room.reset_room()
    await process_frame
    check(room.adapter.boss.practice_skill==3,"Retry lost AI selection")
    room.set_combat_simulation(false)
    FileAccess.open(out.path_join("low_health_report.json" if "--low-health" in OS.get_cmdline_user_args() else "report.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"history":history,"contacts":contacts,"min_player_hp":min_player_hp,"boss_hp":end_hp,"max_player_speed":max_speed},"\t"))
    if DisplayServer.get_name()!="headless": FileAccess.open(out.path_join("film.json"),FileAccess.WRITE).store_string(JSON.stringify(film))
    print("SANDSTORM AI: ",failures," failures; actions=",history.size()," boss HP=",end_hp," player minimum=",min_player_hp)
    room.free()
    quit(0 if failures==0 else 1)
