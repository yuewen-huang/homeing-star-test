extends SceneTree

class MemorySave extends SaveProgressService:
	# Geometry/excavation tests run after the first chapter's ability unlocks.
	# Ability locking is exercised separately by test_salt_field_skills.
	func is_ability_unlocked(_ability: StringName) -> bool: return true
	var fail_write := false
	var writes := 0
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool:
		writes += 1
		return not fail_write

var field: Chapter2SaltField
var save: MemorySave
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func enter() -> void:
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate() as Chapter2SaltField
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	await process_frame; await process_frame
func clear_scene() -> void:
	current_scene.free()
	current_scene = null
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK,"Capture "+label)
func tick(seconds: float, movement := Vector2.ZERO, dig := false) -> void:
	for i in ceili(seconds*60): field.step_exploration(1.0/60,movement,dig,false)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save); real_save.free()
	save = MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	var authored: Node2D = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_environment.tscn").instantiate()
	var placed_rock: Sprite2D = authored.get_node("Boundary/LeftBanks").get_child(0)
	check(placed_rock.texture!=null and authored.get_node("Ground").mesh!=null,
		"Authored rocks and ground exist before entering the tree, for editor visibility")
	placed_rock.position += Vector2(12,10)
	placed_rock.scale *= 1.08
	var edited_transform := placed_rock.transform
	root.add_child(authored)
	await process_frame
	check(placed_rock.transform.is_equal_approx(edited_transform),"Manual prop position and scale survive runtime initialization")
	check(authored.get_node("Boundary").outcrops.size()==40,"Authored boundary adopts forty saved rocks without generating duplicates")
	check(placed_rock.z_index==roundi(SaltFieldProjection.unproject(placed_rock.global_position).y),
		"Dragged prop keeps its depth order without overwriting its authored transform")
	authored.free()
	await enter()
	check(field.MAP_SIZE == Vector2(7200,1800) and field.piles.size() == 56,"Salt field doubles its width to 7200 and grows to 56 heaps while depth stays unchanged")
	check(field.ground_layer.texture.get_size()==Vector2(300,300),"Ground uses one 300 by 300 source tile")
	check(field.ground_layer.mesh.get_surface_count()==1 and field.ground_layer.z_index<0,"Projected ground mesh remains below Lan and salt heaps")
	for row in 2:
		for column in 3:
			check(SaltFieldGround.tile_uv(column,row,Vector2(1,0.4))==SaltFieldGround.tile_uv(column+1,row,Vector2(0,0.4)),"Mirror tiling shares the same horizontal seam samples")
	for column in 4:
		check(SaltFieldGround.tile_uv(column,0,Vector2(0.3,1))==SaltFieldGround.tile_uv(column,1,Vector2(0.3,0)),"Mirror tiling shares the same vertical seam samples")
	for i in 5:
		var art_pile := field.piles[i]
		check(art_pile.art_variant == i and art_pile.sprite.texture == SaltFieldPile.TEXTURES[i],"Painted salt variant %d appears in actual map" % (i+1))
		check(art_pile.sprite.scale == Vector2.ONE * SaltFieldPile.ART_SCALE,"Painted art keeps uniform source-pixel scale for variant %d" % (i+1))
	var projection := field.PROJECTION
	var corners := projection.rect_polygon(Rect2(Vector2.ZERO,field.MAP_SIZE))
	check(is_equal_approx(corners[0].distance_to(corners[1])/corners[2].distance_to(corners[3]),0.6),"Far boundary is sixty percent of near boundary width")
	check(is_equal_approx(corners[2].y-corners[0].y,1080),"Camera correction preserves the original 1080 projected ground depth")
	for point in [Vector2(40,120),Vector2(3600,900),Vector2(7160,1760),field.SPAWN]:
		check(projection.unproject(projection.project(point)).distance_to(point)<0.001,"Ground projection preserves logical coordinates %s" % point)
	check(is_equal_approx(projection.depth_scale(0),0.6) and is_equal_approx(projection.depth_scale(1800),1.0),"Billboards scale from sixty percent in distance to full size nearby")
	check(field.pawn.position.distance_to(projection.project(field.feet))<0.001 \
		and is_equal_approx(field.pawn.scale.x,projection.depth_scale(field.feet.y)),"Pawn feet and upright body share perspective scale")
	check(field.piles[4].position.distance_to(projection.project(field.piles[4].ground_position))<0.001,"Heap art is projected from its actual collision footprint")
	field.feet = Vector2(900,120); field._sync_view(0)
	var head_on_screen := field.pawn.position.y - 82 * field.pawn.scale.y - field.camera.position.y + 360
	check(head_on_screen>104,"Camera headroom keeps the distant pawn below the HUD")
	field.exploration_camera_position = Vector2(1800,500)
	for screen_y in [360,400,480,580,600]:
		field.feet = projection.unproject(Vector2(1800,500+screen_y-360)); field._sync_view(0)
		check(is_equal_approx(field.camera.position.y,500),"Camera remains still inside the marked vertical dead zone at screen y=%d" % screen_y)
	field.feet = projection.unproject(Vector2(1800,470)); field._sync_view(0)
	check(is_equal_approx(field.camera.position.y,470) and is_equal_approx(field.pawn.position.y-field.camera.position.y+360,360),
		"Crossing the upper edge advances the camera by exactly the overflow")
	field.feet = projection.unproject(Vector2(1800,430)); field._sync_view(0)
	check(is_equal_approx(field.camera.position.y,430),"Continuing toward the far edge keeps advancing the camera")
	field.feet = projection.unproject(Vector2(1800,470)); field._sync_view(0)
	check(is_equal_approx(field.camera.position.y,430),"Reversing into the dead zone stops camera movement without recentering")
	field.feet = projection.unproject(Vector2(1800,700)); field._sync_view(0)
	check(is_equal_approx(field.camera.position.y,460) and is_equal_approx(field.pawn.position.y-field.camera.position.y+360,600),
		"Crossing the lower edge pulls the camera back by exactly the overflow")
	var normal_camera := field.camera.position
	field.overview = true; field._sync_view(0)
	field.overview = false; field._sync_view(0)
	check(field.camera.position.is_equal_approx(normal_camera),"Closing overview restores the exploration camera without recentering")
	field.feet = Vector2(1800,1760); field._sync_view(0)
	check(field.boundary_layer.sections.size()==10 and field.boundary_layer.has_node("SouthCoast"),
		"Ten north wall sections cover the wider map; south coast and irregular side reefs remain")
	await capture("salt_field_near_edge")
	for side in [40,7160]:
		for depth in [495,1075,1655]:
			var limits := SaltFieldPerimeter.x_limits(depth)
			field.feet = Vector2(limits.x if side==40 else limits.y,depth); field._sync_view(0)
			await capture("salt_wall_%d_%d" % [side,depth])
	field.feet = Vector2(1800,120); field._sync_view(0)
	await capture("salt_field_far_edge")
	field.feet = field.SPAWN; field._sync_view(0)
	check(field.state.boss_pile in field.CANDIDATES,"Hidden core selects only a battle-space candidate")
	var hidden := int(field.state.boss_pile)
	var writes := save.writes
	check(save.ensure_salt_field_state(field.CANDIDATES).boss_pile == hidden and save.writes == writes,"Repeated activation retains the saved random position")
	field.overview = true; field._sync_view(0)
	await capture("salt_field_overview")
	field.overview = false; field._sync_view(0)
	await capture("salt_field_entrance")
	var before := field.feet
	tick(0.4,Vector2.UP)
	check(field.feet.y < before.y-field.SPEED*0.35 and absf(projection.project(field.feet).x-projection.project(before).x)<0.01,"Up input changes depth along screen vertical rather than jumping")
	before = field.feet
	tick(0.4,Vector2.DOWN)
	check(field.feet.distance_to(field.SPAWN)<1,"Down input walks back without crouching or gravity")
	field.feet = Vector2(900,1500)
	before = field.feet
	tick(0.1,Vector2(1,1))
	var projected_distance := projection.project(field.feet).distance_to(projection.project(before))
	check(absf(projected_distance-field.SPEED*0.1*projection.depth_scale(before.y))<0.1,"Diagonal screen movement is normalized with perspective scale")
	field.feet = Vector2(900,850)
	field.step_exploration(0,Vector2.RIGHT,false,true)
	before = field.feet
	tick(0.3,Vector2.UP)
	check(field.feet.x > before.x+field.DODGE_SPEED*0.29 and is_equal_approx(field.feet.y,before.y),"Dodge travels horizontally while vertical movement waits for its end")
	field.dodge_remaining = 0; field.dodge_cooldown = 0
	var pile := field.piles[4]
	field.feet = Vector2(pile.ground_position.x,pile.ground_position.y+55)
	field._sync_view(0)
	# Screen-up also changes logical X under perspective. Check the initial contact
	# before sustained input can slide around the heap's side.
	tick(0.2,Vector2.UP)
	check(field.feet.y >= pile.ground_position.y+field.BODY_HALF.y-1,"Salt heap footprint blocks walking from the front")
	field.feet = Vector2(pile.footprint().position.x-30,pile.ground_position.y-pile.span.y*0.5)
	before = field.feet
	field.step_exploration(0,Vector2.RIGHT,false,true)
	tick(0.25)
	check(field.feet.x < pile.footprint().position.x-field.BODY_HALF.x,"Swept horizontal dodge cannot tunnel through a heap")
	field.dodge_remaining = 0; field.dodge_cooldown = 0
	field.feet = pile.ground_position-Vector2(0,100)
	field._sync_view(0)
	check(pile.occluded and pile.modulate.a < 0.3 and field.pawn.z_index < pile.z_index,"Heap fades while it occludes a pawn standing behind it")
	await capture("salt_field_occlusion")
	field.feet = pile.ground_position+Vector2(0,42)
	field._sync_view(0)
	check(not pile.occluded and field.pawn.z_index > pile.z_index,"Pawn in front sorts above the heap and restores its opacity")
	tick(0.45,Vector2.ZERO,true)
	check(field.dig_elapsed>0.4 and not pile.excavated,"Holding E progresses excavation without immediately removing heap")
	await capture("salt_field_digging")
	tick(1.0/60)
	check(field.dig_elapsed == 0,"Releasing E discards excavation progress")
	tick(0.4,Vector2.ZERO,true)
	tick(1.0/60,Vector2.RIGHT,true)
	check(field.dig_elapsed == 0,"Movement interrupts excavation and discards progress")
	tick(0.3,Vector2.ZERO,true)
	field.step_exploration(1.0/60,Vector2.ZERO,true,true)
	check(field.dig_elapsed == 0,"Horizontal dodge interrupts excavation")
	tick(field.pawn.dodge_duration+0.05)
	field.feet = pile.ground_position+Vector2(0,42)
	tick(1.05,Vector2.ZERO,true)
	check(pile.excavated and field.state.dug.has(pile.pile_id),"Full hold removes the heap and persists its salt trace")
	check(pile.sprite.texture == SaltFieldPile.EXCAVATED_TEXTURE,"Excavation swaps to the user's painted investigated heap")
	await capture("salt_field_painted_excavated")
	field.feet = pile.ground_position+Vector2(0,42)
	tick(0.6,Vector2.UP)
	check(field.feet.y < pile.ground_position.y-40,"Excavated footprint becomes passable")
	var other := field.piles[5]
	field.feet = other.ground_position+Vector2(0,42)
	save.fail_write = true
	tick(1.1,Vector2.ZERO,true)
	check(not other.excavated and not save.ensure_salt_field_state(field.CANDIDATES).dug.has(other.pile_id),"Failed excavation save leaves heap and saved state intact")
	check(field.status.text.contains("保存失败"),"Failed excavation offers retry without losing player control")
	save.fail_write = false
	tick(1.0/60)
	tick(1.05,Vector2.ZERO,true)
	check(other.excavated,"Release and hold retries failed excavation")
	var boss_pile := field.piles[hidden]
	field.feet = boss_pile.ground_position+Vector2(0,42)
	tick(1.05,Vector2.ZERO,true)
	check(field.boss_found and boss_pile.excavated,"Excavating saved hiding place reveals the core placeholder")
	await capture("salt_field_core_found")
	var disk := save._config.encode_to_text()
	clear_scene()
	save._config = ConfigFile.new(); save._config.parse(disk)
	await enter()
	check(field.state.boss_pile == hidden and field.boss_found and field.piles[4].excavated,"Reload restores hidden core and excavated heaps without reroll")
	field.feet = Vector2(50,130)
	tick(2,Vector2(-1,-1))
	check(field.feet.x>=40 and field.feet.y>=120,"Northwest map boundary contains the pawn")
	field.feet = Vector2(7150,1750)
	tick(2,Vector2.ONE)
	check(field.feet.x<=7160 and field.feet.y<=1760,"Southeast map boundary contains the pawn")
	var screen_feet := field.pawn.position-field.camera.position+Vector2(640,360)
	check(field.camera.position.x<=6560 and screen_feet.y<=600.01 and screen_feet.y>=359.99,
		"Map limits do not prevent the camera from keeping the pawn inside the vertical dead zone")
	await capture("salt_field_southeast_edge")
	# A discovered core now starts the production crab encounter on reload.
	# Exercise exploration inputs in a fresh exploration fixture, not that fight.
	clear_scene()
	save._config = ConfigFile.new()
	await enter()
	field.feet = field.SPAWN
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W; event.keycode = KEY_W; event.pressed = true
	Input.parse_input_event(event); Input.flush_buffered_events()
	field._physics_process(0.1)
	event = event.duplicate(); event.pressed = false
	Input.parse_input_event(event); Input.flush_buffered_events()
	check(field.feet.y < field.SPAWN.y-field.SPEED*0.08,"W input reaches planar upward movement through the actual input bridge")
	event = InputEventKey.new()
	event.physical_keycode = KEY_L; event.keycode = KEY_L; event.pressed = true
	root.push_input(event)
	await process_frame
	field._physics_process(1.0/60)
	check(field.dodge_remaining>0,"L input starts the horizontal dodge through viewport input")
	clear_scene()
	# A fresh playthrough has no stored map section and therefore generates a new record.
	save._config = ConfigFile.new()
	check(not save.ensure_salt_field_state(Chapter2SaltField.CANDIDATES).is_empty(),"Fresh playthrough generates and saves a new hiding record")
	await process_frame; await process_frame
	print("SALT FIELD PROTOTYPE: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
