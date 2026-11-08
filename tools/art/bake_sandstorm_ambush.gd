extends SceneTree
class Stage extends Node2D:
    var TIMELINE: Array = []
    var attacker := Node2D.new()
    var target := Node2D.new()
    const GROUND_Y := 520.0
    const TARGET_SIZE := Vector2(44,96)
    func _init() -> void:
        add_child(attacker)
        add_child(target)
func _initialize() -> void: call_deferred("run")
func run() -> void:
    for kind: String in ["veil","gust"]:
        var folder := "res://combos/sandstorm_ambush_"+kind+"/"
        var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"combo.json"))
        ComboStyle.data = JSON.parse_string(FileAccess.get_file_as_string(folder+"style.json"))
        var out := ProjectSettings.globalize_path("res://../homeing-star-test/artifacts/sandstorm-ambush/"+kind)
        DirAccess.make_dir_recursive_absolute(out)
        var view := SubViewport.new()
        view.size = Vector2i(640,360) if kind=="veil" else Vector2i(256,256)
        view.transparent_bg = true
        view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
        root.add_child(view)
        view.canvas_transform = Transform2D(Vector2(.5,0),Vector2(0,.5),Vector2.ZERO) if kind=="veil" else Transform2D(0,Vector2(-512,-232))
        var stage := Stage.new()
        stage.TIMELINE = doc.events
        view.add_child(stage)
        var effects: Array[Node2D] = []
        for event: Dictionary in doc.events:
            var effect: Node2D = load("res://vfx/swarm_effect.gd").new().configure(event,stage)
            view.add_child(effect)
            effects.append(effect)
            effect.advance(.2 if kind=="veil" else .001)
        for i in (48 if kind=="veil" else 24):
            for effect in effects:
                if i>0: effect.advance(1.0/(24.0 if kind=="veil" else 40.0))
            await process_frame
            await RenderingServer.frame_post_draw
            view.get_texture().get_image().save_png(out.path_join("frame_%03d.png"%i))
        view.queue_free()
        await process_frame
    print("AMBUSH STUDIO BAKE: veil 48 frames, gust 24 frames")
    quit()
