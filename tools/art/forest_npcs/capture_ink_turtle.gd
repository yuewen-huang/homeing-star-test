extends SceneTree
## Native sprite-only review. Does not instantiate a gameplay map or write saves.
var output := "D:/HomingStar/homeing-star-temp-assert/artifacts/ink_turtle"
var actors: Array[AnimatedSprite2D] = []
var seen: Array[Dictionary] = [{}, {}]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 720)
	var stage := Node2D.new()
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color("e8e3d6")
	bg.size = Vector2(1280,720)
	stage.add_child(bg)
	var positions := [210.0, 420.0, 640.0, 850.0, 1060.0]
	var ids := ["ali", "ink_turtle idle", "ink_turtle talk", "yupo", "lingwei"]
	var scales := [0.68857, 0.7, 0.7, 0.635837, 0.777778]
	for i in 5:
		var actor: AnimatedSprite2D
		if i in [1,2]:
			var npc := (load("res://scenes/story/npcs/ink_turtle_npc.tscn") as PackedScene).instantiate() as Node2D
			stage.add_child(npc)
			npc.position = Vector2(positions[i],430)
			actor = npc.get_node("Body") as AnimatedSprite2D
			actor.play(&"idle" if i==1 else &"talk")
			actors.append(actor)
		else:
			actor = AnimatedSprite2D.new()
			actor.sprite_frames = load("res://assets/characters/forest_npcs/"+ids[i]+"/idle_frames.tres") as SpriteFrames
			actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			actor.position = Vector2(positions[i],430.0-72.0*scales[i])
			actor.scale = Vector2.ONE*scales[i]
			stage.add_child(actor)
			actor.play(&"idle")
		var label := Label.new()
		label.text = ids[i]
		label.position = Vector2(positions[i]-65,460)
		label.add_theme_color_override("font_color",Color("383c35"))
		stage.add_child(label)
	var title := Label.new()
	title.text = "Ink Turtle | production scale / native Godot playback"
	title.position = Vector2(330,220)
	title.add_theme_color_override("font_color",Color("383c35"))
	stage.add_child(title)
	for i in 192:
		await process_frame
		for j in 2: seen[j][actors[j].frame] = true
		if i%6==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("playback_%03d.png" % (i/6)))
	for j in 2:
		if seen[j].size()!=4:
			push_error("Animation missing frames: "+str(seen[j])); quit(1); return
	print("PASS native idle/talk playback: both visited all four frames; saves untouched")
	quit()
