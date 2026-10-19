extends SceneTree
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config=ConfigFile.new(); _loaded=true
	func save_progress() -> bool: return not fail_write
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("OK " if ok else "FAIL ",message)
func key() -> void:
	var event:=InputEventKey.new(); event.physical_keycode=KEY_E; event.keycode=KEY_E; event.pressed=true
	root.push_input(event)
	event=event.duplicate(); event.pressed=false; root.push_input(event)
func capture(label_: String) -> void:
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_+".png"))==OK,"Capture "+label_)
func run() -> void:
	var old:=root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save:=MemorySave.new(); save.name="SaveProgress"; root.add_child(save)
	# Mirror the user's screenshot landmarks without touching the actual save.
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":1,"dug":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,24,25,26,27]})
	var packed: PackedScene=load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn")
	var field:=packed.instantiate() as Chapter2SaltField
	root.add_child(field); current_scene=field; field.set_physics_process(false)
	var stele: MinigameStele=field.puzzle_stele
	var foot:=SaltFieldProjection.unproject(stele.position)
	check(foot.distance_to(Vector2(1400,1170))<0.01,"Shared puzzle stele sits at the screenshot's standing point")
	check(stele.state==MinigameStele.SteleState.LOCKED and not stele.challenge_available,"New stele starts locked and does not claim a completed puzzle")
	field.feet=foot+Vector2(0,62); field._sync_view(0)
	field.exploration_camera_position=SaltFieldProjection.project(foot)+Vector2(5,4)
	field._sync_view(0)
	check(stele.can_interact() and stele.z_index<field.pawn.z_index,"Standing in front allows interaction with correct depth order")
	await capture("salt_puzzle_stele_locked")
	save.fail_write=true; key()
	check(save.get_stele_state(&"salt_puzzle_01")==0 and save.get_checkpoint_for_scene(field.scene_file_path).is_empty(),"Failed activation rolls back unlock and planar checkpoint together")
	save.fail_write=false; key()
	check(save.get_stele_state(&"salt_puzzle_01")==1 and stele.state==MinigameStele.SteleState.UNLOCKED,"Actual E input unlocks and saves the salt stele")
	var checkpoint:=save.get_checkpoint_for_scene(field.scene_file_path)
	var expected:=foot+stele.checkpoint_offset
	check(checkpoint.position.distance_to(expected)<0.01,"Checkpoint is saved in logical ground coordinates, not screen projection")
	var safe:=true
	for pile in field.piles:
		if not pile.excavated and pile.footprint().grow(18).has_point(expected): safe=false
	check(safe,"Saved arrival point stays clear of intact salt heaps")
	field.step_exploration(0.5,Vector2.ZERO,true,false)
	check(field.dig_elapsed==0,"Holding E at the stele does not dig a nearby heap")
	await capture("salt_puzzle_stele_unlocked")
	var destinations:=save.get_unlocked_stele_destinations()
	check(destinations.size()==1 and destinations[0].stele_id==&"salt_puzzle_01","Activation adds the shared travel destination")
	check(TravelCatalog.region_of(&"salt_puzzle_01").id==&"salt" and TravelCatalog.music_for(&"salt_puzzle_01")==Chapter2Music.SALT_FIELD,"Travel entry belongs to second-chapter salt field with its BGM")
	field.feet=foot+Vector2(0,160); field._sync_view(0)
	check(not stele.can_interact(),"Logical depth distance prevents remote stele activation")
	field.free(); current_scene=null
	var transition:=root.get_node("SceneTransition") as SceneTransitionService
	transition.set_scene_entry_position(checkpoint.position)
	field=packed.instantiate() as Chapter2SaltField; root.add_child(field); current_scene=field; field.set_physics_process(false)
	check(field.feet.distance_to(expected)<0.01 and field.puzzle_stele.state==MinigameStele.SteleState.UNLOCKED,"Explicit travel arrival restores the safe feet position and unlocked stele")
	field.free(); current_scene=null; await process_frame
	print("SALT PUZZLE STELE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
