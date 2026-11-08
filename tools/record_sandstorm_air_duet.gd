extends SceneTree
var rows: Array=[]
var contacts: Array=[]
var relocations: Array=[]
var scorpion_frames: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var tag:="before"
    var mode:="near"
    for arg in OS.get_cmdline_user_args():
        if arg.begins_with("--tag="): tag=arg.trim_prefix("--tag=")
        if arg.begins_with("--mode="): mode=arg.trim_prefix("--mode=")
    var out:="D:/HomingStar/homeing-star-test/artifacts/sandstorm-air-duet/"+tag
    DirAccess.make_dir_recursive_absolute(out)
    root.size=Vector2i(1280,720)
    root.unfocusable=true
    root.position=Vector2i(-1500,-1500)
    var room: BossDevelopmentRoom=load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene=room
    await process_frame
    room.select_combo(1)
    room.set_combat_simulation(true)
    # Review the real fight unobstructed; only recording UI is hidden.
    for child in room.get_children():
        if child is CanvasLayer: child.hide()
    room.player.get_node("PlayerStatusHUD").hide()
    room.player.global_position=Vector2(670,room.FLOOR_Y)
    var actor: SandstormFighter=room.adapter.boss
    actor.set_process(false)
    if mode=="edge":
        actor.position.x+=280
        actor.thomas.global_position.x+=280
        room.player.global_position.x=1180
    elif mode=="edge_left":
        actor.position.x-=620
        actor.thomas.global_position.x-=620
        room.player.global_position.x=120
    if "--knee-only" in OS.get_cmdline_user_args():
        # Isolate the production close-range branch for contact inspection.
        # Full moving-field play is recorded separately with real walk input.
        var skill: SandstormThomas=actor.thomas
        skill.elapsed=skill._span(skill.config.intro_durations)+int(skill.config.spin_cycles)*skill._span(skill.config.loop_durations)
        skill.next_emission=INF
        skill.emitted=3
        skill.branch_checked=true
        skill._start_followup(room.player.position)
    var bound:=false
    var tail:=0
    for tick in 900:
        await physics_frame
        if actor.looping_idle:
            tail+=1
            if tail>=30: break
        if not is_instance_valid(actor.thomas) or not is_instance_valid(actor.thomas.follow): continue
        var f: SandstormThomasFollowup=actor.thomas.follow
        if not bound:
            bound=true
            f.attack_hitbox.hit_resolved.connect(func(_victim: Node,result: int):
                contacts.append({"strike":f.serial,"time":f.elapsed,"frame":f.shown_frame,"result":result,"boss":[f.global_position.x,f.global_position.y],"player":[room.player.global_position.x,room.player.global_position.y]}))
        rows.append({"tick":tick,"phase":f.phase,"time":f.elapsed,"frame":f.shown_frame,"action":f.shown_action,
            "boss":[f.global_position.x,f.global_position.y],"boss_velocity":[f.flight_velocity.x,f.flight_velocity.y],
            "player":[room.player.global_position.x,room.player.global_position.y],"player_velocity":[room.player.velocity.x,room.player.velocity.y],
            "visible":f.body.visible,"facing":f.facing,"teleports":f.teleport_count,"ghosts":f.ghost_count})
        relocations=f.teleport_events.duplicate(true)
        if is_instance_valid(f.signature.scorpion_sprite):
            var fx:=f.signature
            var tip:=fx.scorpion_tip()
            scorpion_frames.append({"tick":tick,"time":f.elapsed,"phase":f.phase,"phase_clock":f.clock,
                "clip":fx.scorpion_phase,"frame":fx.scorpion_sprite.frame,"tip":[tip.x,tip.y],
                "anchor":[fx.scorpion_sprite.global_position.x,fx.scorpion_sprite.global_position.y],
                "floor":f.floor_y,"impact_count":fx.emitted.get("slam_impact",0),"facing":f.facing})
    FileAccess.open(out.path_join("telemetry.json"),FileAccess.WRITE).store_string(JSON.stringify({"frames":rows,"contacts":contacts,"relocations":relocations,"scorpion_frames":scorpion_frames}))
    print("AIR DUET RECORDING ",tag," ",JSON.stringify(contacts))
    room.free()
    quit()
