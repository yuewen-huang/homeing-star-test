extends SceneTree
## Native six-state preview; a combat specimen exists only in this capture process.
class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config=ConfigFile.new(); _loaded=true
	func save_progress() -> bool: return true
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var old:=root.get_node("SaveProgress"); root.remove_child(old); old.free()
	var save:=MemorySave.new(); save.name="SaveProgress"; root.add_child(save)
	var field:=load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate() as Chapter2SaltField
	root.add_child(field); current_scene=field; field.set_physics_process(false)
	var position_: Vector2=field.puzzle_stele.position
	var output:=OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	for kind in ["puzzle","combat"]:
		if kind=="combat":
			field.puzzle_stele.free()
			var specimen: MinigameStele=load("res://scenes/levels/chapter_2_salt/salt_combat_stele.tscn").instantiate()
			specimen.name="PuzzleStele"; specimen.position=position_
			field.add_child(specimen); field.puzzle_stele=specimen; specimen.bind_field(field)
		var stele: MinigameStele=field.puzzle_stele
		field.feet=SaltFieldProjection.unproject(position_)+Vector2(0,62)
		field.exploration_camera_position=SaltFieldProjection.project(SaltFieldProjection.unproject(position_))+Vector2(5,4)
		field._sync_view(0)
		print("STELE ART ",kind," ",stele.art_override.get_size()," alpha bounds ",stele.art_override.get_image().get_used_rect())
		for state_ in 3:
			if not save.set_stele_state(stele.stele_id,state_): quit(1); return
			await process_frame; await RenderingServer.frame_post_draw
			if not output.is_empty():
				var error:=root.get_texture().get_image().save_png(output.path_join("salt_stele_%s_%d.png"%[kind,state_]))
				if error!=OK: quit(error); return
	field.free(); current_scene=null; await process_frame; quit()
