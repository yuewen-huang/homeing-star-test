extends SceneTree
## Historical stationary-three-ring fixture. For the current moving emitter,
## run test_sandstorm_moving_waves.gd; its world-centre/route checks supersede this.
## Real Lan movement only: no frozen physics, position writes during the cast,
## invulnerability, dodge, parry, forced velocity, or animation-clock edits.
var failures := 0
var room: Node2D
var output := ""
var native := false
var reports: Array = []
var held := 0
var film: Array = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
    if not ok:
        failures += 1
        push_error(message)
func walk(direction: int) -> void:
    if held == direction: return
    Input.action_release("ui_left")
    Input.action_release("ui_right")
    held = direction
    if held != 0: Input.action_press("ui_left" if held<0 else "ui_right")
func capture(name: String) -> void:
    if not native: return
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
    output = ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-rings")
    DirAccess.make_dir_recursive_absolute(output)
    native = DisplayServer.get_name() != "headless"
    root.size = Vector2i(1280,720)
    room = load("res://scenes/dev/sandstorm_fighter_room.tscn").instantiate()
    root.add_child(room)
    current_scene = room
    await process_frame
    await process_frame
    var cases := [{"name":"walk_default","x":380.0},{"name":"walk_near","x":600.0},
        {"name":"walk_left_edge","x":100.0},{"name":"walk_right_edge","x":1180.0},
        {"name":"walk_outer_gap","x":260.0},{"name":"stand_control","x":380.0}]
    if "--visual-only" in OS.get_cmdline_user_args(): cases = cases.slice(0,1)
    for entry in cases:
        walk(0)
        if room.combat_simulation: room.set_combat_simulation(false)
        room.reset_room()
        room.select_combo(1)
        room.set_combat_simulation(true)
        # Spawn fixture BEFORE the cast advances. All subsequent travel is input-driven.
        room.player.global_position = Vector2(entry.x,room.FLOOR_Y)
        var actor: SandstormFighter = room.adapter.boss
        actor.set_process(false) # Suppress practice replay only; skill/player physics stay live.
        var skill: SandstormThomas = actor.thomas
        var centre := skill.global_position
        var start_x: float = room.player.global_position.x
        var side := -1.0 if start_x<centre.x else 1.0
        var desired_radius := 270.0 if side>0 or absf(start_x-centre.x)<400 else 530.0
        var contacts: Array = []
        skill.wave_emitted.connect(func(wave: SandstormWave):
            wave.hitbox.hit_resolved.connect(func(_victim: Node,result: int): contacts.append({"result":result,"time":skill.elapsed})))
        var health: int = room.player.combat_stats.health
        var minimum_health := health
        var max_speed := 0.0
        var min_clearance := INF
        var min_x := start_x
        var max_x := start_x
        var captures := {}
        var travel := 0.0
        var prior_x := start_x
        var decision_at := .75 # Human reaction after the field appears, not frame-perfect steering.
        var samples: Array = []
        for tick in 650:
            if not is_instance_valid(skill): break
            var t := skill.elapsed
            var player_x: float = room.player.global_position.x
            if entry.name != "stand_control" and t >= decision_at:
                decision_at = t+.12
                var drift := maxf(0,t-float(skill.config.field_start)-float(skill.config.warning_time))*float(skill.config.ring_speed)
                var goal := clampf(centre.x+side*(desired_radius+drift),64,1216)
                var difference := goal-player_x
                if held == 0:
                    if absf(difference)>22: walk(-1 if difference<0 else 1)
                elif difference*held <= 7: walk(0)
            await physics_frame
            minimum_health = mini(minimum_health,room.player.combat_stats.health)
            max_speed = maxf(max_speed,absf(room.player.velocity.x))
            min_x = minf(min_x,room.player.global_position.x)
            max_x = maxf(max_x,room.player.global_position.x)
            travel += absf(room.player.global_position.x-prior_x)
            prior_x = room.player.global_position.x
            check(room.player.is_physics_processing(),entry.name+": player physics disabled")
            check(not room.player.is_invulnerable(),entry.name+": invulnerability invalidates walk test")
            check(not room.player.ultimate_active,entry.name+": ultimate immunity invalidates test")
            if is_instance_valid(skill):
                check(skill.get_action_time_scale()==1.0,entry.name+": slowed hazard invalidates walk test")
                check(skill.global_position.distance_to(centre)<.001,"Boss root changed during spin")
                if not skill.resting:
                    var foot := skill.body.to_global(Vector2(0,float(skill.config.frame_bottoms[skill.shown_frame])-128))
                    check(absf(foot.y-room.FLOOR_Y)<.001,"Ground support drift")
                    check(skill.shown_frame not in range(15,22),"Airborne knee appeared")
                for wave in skill.waves:
                    if wave.hitbox.monitoring:
                        var torso: Vector2 = room.player.global_position+Vector2(0,-29)
                        var clearance: float = absf(torso.distance_to(centre)-wave.radius)-wave.half_width-32
                        min_clearance = minf(min_clearance,clearance)
                if tick%12==0: samples.append({"t":skill.elapsed,"x":room.player.global_position.x,"speed":room.player.velocity.x,"input":held})
                if entry.name == "walk_default":
                    if "--film" in OS.get_cmdline_user_args() and tick%5==0:
                        film.append({"file":"film_%04d.png" % tick,"time":skill.elapsed})
                        await capture("film_%04d" % tick)
                    for shot in [1.0,1.7,2.3,3.3,4.4,5.2]:
                        # Capturing yields; natural completion may free the skill meanwhile.
                        if not is_instance_valid(skill): break
                        if skill.elapsed>=shot and not captures.has(shot):
                            captures[shot]=true
                            await capture("walk_%04d" % int(shot*1000))
                if entry.name == "walk_right_edge" and is_instance_valid(skill) and skill.elapsed>4.4 and not captures.has("edge"):
                    captures.edge=true
                    await capture("right_edge")
        walk(0)
        check(not is_instance_valid(skill) and actor.looping_idle,entry.name+": skill failed to complete")
        if entry.name == "stand_control":
            check(minimum_health<health and not contacts.is_empty(),"Standing control must take real damage")
        else:
            check(contacts.is_empty(),entry.name+": walking collided with a ring")
            check(minimum_health==health,entry.name+": walking lost health")
            check(max_speed<=LanPlayer.WALK_SPEED+.01,entry.name+": needed running instead of walking")
            check(min_x>=50 and max_x<=1230,entry.name+": escaped outside the visible arena")
            check(travel>100,entry.name+": test did not actually walk")
        reports.append({"case":entry.name,"health_before":health,"minimum_health":minimum_health,
            "contacts":contacts,"max_speed":max_speed,"distance_walked":travel,"x_range":[min_x,max_x],
            "minimum_conservative_clearance":min_clearance,"samples":samples})
        print("RING WALK CASE: ",entry.name," contacts=",contacts.size()," hp=",minimum_health," speed=",max_speed," travel=",travel)
    # Reset during a live field removes the actual hazards and keeps skill selection.
    room.reset_room()
    var previous: Node = room.adapter.boss.thomas
    for tick in 140: await physics_frame
    var old_waves: Array = previous.waves.duplicate()
    room.reset_room()
    await process_frame
    check(not is_instance_valid(previous),"Reset leaked ring executor")
    for wave in old_waves: check(not is_instance_valid(wave),"Reset leaked ring collider")
    check(room.adapter.boss.practice_skill==1,"Reset lost selected skill")
    print("SANDSTORM RING WALK: ",failures," failures; real physics/input; no dodge, parry or immunity")
    var report_name := "visual_walk_report.json" if "--visual-only" in OS.get_cmdline_user_args() else "walk_report.json"
    FileAccess.open(output.path_join(report_name),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"native":native,"cases":reports},"\t"))
    if not film.is_empty(): FileAccess.open(output.path_join("film.json"),FileAccess.WRITE).store_string(JSON.stringify(film))
    room.free()
    quit(0 if failures==0 else 1)
