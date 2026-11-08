extends SceneTree
class Stage extends Node2D:
    var TIMELINE: Array=[]
    var attacker:=Node2D.new()
    var target:=Node2D.new()
    const GROUND_Y:=520.0
    const TARGET_SIZE:=Vector2(44,96)
    func _init() -> void:
        add_child(attacker)
        add_child(target)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.unfocusable=true
    root.position=Vector2i(-1500,-1500)
    for key: String in ["kick","arrival","peel_knee","peel_roll","peel_kick","scorpion","slam_impact"]:
        if "--tail-only" in OS.get_cmdline_user_args() and key not in ["scorpion","slam_impact"]: continue
        if "--legacy-check" in OS.get_cmdline_user_args() and key not in ["kick","arrival"]: continue
        var folder:="res://combos/sandstorm_signature_"+key
        var doc: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/combo.json"))
        ComboStyle.data=JSON.parse_string(FileAccess.get_file_as_string(folder+"/style.json"))
        var out:=ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-signature/bake/"+key)
        DirAccess.make_dir_recursive_absolute(out)
        var view:=SubViewport.new()
        view.size=Vector2i(doc.bake.cell[0],doc.bake.cell[1])
        view.transparent_bg=true
        view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
        root.add_child(view)
        view.canvas_transform=Transform2D(0,Vector2(doc.bake.origin[0]-640,doc.bake.origin[1]-360))
        var stage:=Stage.new()
        stage.TIMELINE=doc.events
        view.add_child(stage)
        var effects: Dictionary={}
        var dispatched: Dictionary={}
        for frame in int(doc.bake.frames):
            var t:=frame/float(doc.bake.fps)
            for effect: Node2D in effects.values(): effect.advance(1.0/float(doc.bake.fps))
            for i in doc.events.size():
                var event: Dictionary=doc.events[i]
                if float(event.t)>t+.00001 or dispatched.has(i): continue
                dispatched[i]=true
                if event.do=="quake":
                    var quake: Node2D=load("res://vfx/quake_effect.gd").new().configure(event)
                    quake.set_look("cel","balanced")
                    view.add_child(quake)
                    effects["quake_"+str(i)]=quake
                    continue
                if effects.has(event.id): effects[event.id].morph(event)
                else:
                    var effect: Node2D=load("res://vfx/swarm_effect.gd").new().configure(event,stage)
                    view.add_child(effect)
                    effects[event.id]=effect
                    effect.advance(.001)
            await process_frame
            await RenderingServer.frame_post_draw
            view.get_texture().get_image().save_png(out.path_join("frame_%03d.png"%frame))
        view.queue_free()
        await process_frame
        print("BAKED signature ",key)
    quit()
