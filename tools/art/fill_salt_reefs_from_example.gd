extends SceneTree
## Extend the saved main-scene example; append nodes while preserving every existing block.
const SCENE := "res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn"
const PROJECTION := preload("res://scripts/levels/chapter_2_salt/salt_field_projection.gd")
var field: Node2D
var additions := ""
var added := 0
var occupied := [[],[]]
var regions: Array[Rect2] = []
const TEXTURE_IDS := ["6_8wpue","5_d23xp","3_4rwgu"]

func _initialize() -> void: run.call_deferred()

func visible_region(texture: Texture2D) -> Rect2:
	var image := texture.get_image()
	var minimum := Vector2i(image.get_width(),image.get_height())
	var maximum := Vector2i.ZERO
	for y in image.get_height():
		var count := 0
		for x in image.get_width():
			if image.get_pixel(x,y).a>0.5: count += 1
		if count<8: continue
		for x in image.get_width():
			if image.get_pixel(x,y).a>0.5:
				minimum = minimum.min(Vector2i(x,y)); maximum = maximum.max(Vector2i(x,y))
	return Rect2(Rect2i(minimum,maximum-minimum+Vector2i.ONE).grow(1).intersection(Rect2i(Vector2i.ZERO,image.get_size())))

func write_rock(side: int,position_: Vector2,scale_: Vector2,variant: int,flip: bool,row: String) -> void:
	var region := regions[variant]
	var name_ := "SaltBank_Fill_%d_%s_%03d" % [side,row,added]
	var parent := "Environment/Boundary/"+("LeftBanks" if side==0 else "RightBanks")
	additions += '\n[node name="%s" type="Sprite2D" parent="%s"]\n' % [name_,parent]
	additions += 'z_index = %d\nposition = Vector2(%f, %f)\nscale = Vector2(%f, %f)\n' % [roundi(PROJECTION.unproject(position_).y),position_.x,position_.y,scale_.x,scale_.y]
	additions += 'texture = ExtResource("%s")\ncentered = false\noffset = Vector2(%f, %f)\n' % [TEXTURE_IDS[variant],-region.size.x*0.5,-region.size.y]
	additions += 'flip_h = %s\nregion_enabled = true\nregion_rect = Rect2(%f, %f, %f, %f)\nscript = ExtResource("4_0re1s")\n' % ["true" if flip else "false",region.position.x,region.position.y,region.size.x,region.size.y]
	occupied[side].append(position_)
	added += 1

func run() -> void:
	var original := FileAccess.get_file_as_string(SCENE)
	if original.contains('name="SaltBank_Fill_'):
		push_error("Fill already exists; edit the authored nodes rather than regenerating."); quit(1); return
	field = load(SCENE).instantiate()
	var bank: Node2D = field.get_node("Environment/Boundary")
	var textures: Array[Texture2D] = []
	for i in 3:
		var texture: Texture2D = load("res://assets/sideview/environment/chapter_2_salt/salt_outcrop_%d.png" % (i+1))
		textures.append(texture); regions.append(visible_region(texture))
	for side in 2:
		for rock in bank.get_node("LeftBanks" if side==0 else "RightBanks").get_children():
			occupied[side].append(rock.position)
	# Copy the actual user's right-hand overlap pattern to the left, not the old spacing rule.
	for rock: Sprite2D in bank.get_node("RightBanks").get_children():
		var mirrored := Vector2(3600-rock.position.x,rock.position.y)
		var near := false
		for point: Vector2 in occupied[0]:
			if point.distance_to(mirrored)<18: near = true
		if near: continue
		var variant := textures.find(rock.texture)
		if variant<0: continue
		write_rock(0,mirrored,rock.scale,variant,not rock.flip_h,"Example")
	# Overlapping outer terraces, with progressively taller silhouettes toward the sides.
	# Outer rows are authored first; the inner edge stays low and clear for the pawn.
	for row in range(3,-1,-1):
		for side in 2:
			for i in 29:
				var depth := 90.0+i*59.0+side*12.0+row*9.0
				var scale_factor := [1.0,1.65,2.35,3.1][row] as float
				var variant := (i+side+row)%3 if row==0 else 1+(i+side+row)%2
				var region := regions[variant]
				var jitter := float((i*13+side*19+row*7)%27)-13.0
				var distance := [region.size.x*0.5-10.0,350.0,640.0,980.0][row] as float
				var foot := Vector2(-distance-jitter if side==0 else 3600+distance+jitter,depth)
				var position_ := PROJECTION.project(foot)
				if row==0:
					var near := false
					for point: Vector2 in occupied[side]:
						if point.distance_to(position_)<32: near = true
					if near: continue
				var size := Vector2.ONE*scale_factor*PROJECTION.depth_scale(depth)
				write_rock(side,position_,size,variant,(i+row)%2==1,"Tier%d" % row)
	field.free()
	var marker := '[editable path="Environment"]'
	var output := original.replace(marker,additions+"\n"+marker)
	var file := FileAccess.open(SCENE,FileAccess.WRITE)
	if file==null: quit(1); return
	file.store_string(output); file.close()
	print("APPENDED REEF NODES: ",added,"; preserved original scene blocks")
	quit()
