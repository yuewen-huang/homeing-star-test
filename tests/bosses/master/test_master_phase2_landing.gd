extends "../../support/harness.gd"

# The same visible rear-toe pixel in each action's standing pose. Uppercut's
# uniform bake rounds the matching pixel by half a texel.
const TOES := {
	"phase_2_attack_1": Vector2(74,200),
	"phase_2_attack_2": Vector2(74,294),
	"phase_2_dash": Vector2(138,264),
	"phase_2_special_attack": Vector2(74,244),
	"phase_2_uppercut": Vector2(47,345),
}

func _toe_world(master: MasterBoss, point: Vector2, cell: Vector2) -> Vector2:
	var mirror := -1.0 if master.animated_sprite.flip_h else 1.0
	return master.animated_sprite.to_global((point-cell*.5)*Vector2(mirror,1))

func run() -> void:
	use_memory_progress()
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene = room
	var master: MasterBoss = room.get_node("MasterBoss")
	master.manual_control = true
	master.set_process(false)
	master._enter_phase_2()
	master._enter_phase_2_idle(0)
	var target: Node2D = master.combat_target
	for direction in [-1.0,1.0]:
		for id: StringName in MasterPhase2BodyAction.IDS:
			master.movement_direction = direction
			master.position.x = 700
			target.position.x = 800
			master.phase_2_buff_remaining = 0
			master._enter_phase_2_idle(0)
			var idle_toe: Vector2 = master.to_local(_toe_world(master,Vector2(74,200),Vector2(256,256)))
			master.start_phase_2_body_action(id)
			var action := master.phase_2_body_action
			var seen: Dictionary = {}
			var stable_root := true
			var aligned_shapes := true
			var aligned_effects := true
			var final_x := master.position.x
			var dash_moves := 0
			var ticks := 0
			while master.phase_2_body_action != null and ticks < 900:
				var before := master.position
				master._process(1.0/120.0)
				if master.position.x != before.x: dash_moves += 1
				stable_root = stable_root and is_equal_approx(master.position.y,before.y)
				if master.phase_2_body_action == null:
					check(is_equal_approx(master.position.x,final_x),"Finishing never resets the committed landing x")
					break
				final_x = master.position.x
				var clip: Dictionary = action.data.clips[action.clip_index]
				if not seen.has(action.clip_index):
					seen[action.clip_index] = true
					var cell := Vector2(clip.cell[0],clip.cell[1])
					var toe: Vector2 = TOES[clip.animation]
					var image: Image = master.animated_sprite.sprite_frames.get_frame_texture(StringName(clip.animation),0).get_image()
					check(image.get_pixelv(Vector2i(toe)).a > .5,"Standing registration comes from a visible foot pixel")
					var local_toe := master.to_local(_toe_world(master,toe,cell))
					check(local_toe.distance_to(idle_toe)<1.0,"Every clip shares idle's standing foot in both facings")
				for group: Dictionary in clip.groups:
					var box: CombatHitbox2D = action.hitboxes[group.id]
					for member_index in group.members.size():
						var shape := box.get_child(member_index) as CollisionShape2D
						if shape.disabled: continue
						var member: Dictionary = group.members[member_index]
						var source_time: float = float(clip.start_time)+action.elapsed-action.clip_start
						var sample_index := clampi(int((source_time-float(member.release))*120),0,member.samples.size()-1)
						var sample: Array = member.samples[sample_index]
						var offset: Array = clip.geometry_offset
						var registered := Vector2(sample[1],sample[2])*float(clip.pixel_scale)+Vector2(offset[0],offset[1])+MasterPhase2BodyAction.registration_offset(clip)
						var expected := master.to_global(registered*Vector2(direction,1)*float(action.data.scale))
						aligned_shapes = aligned_shapes and shape.global_position.distance_to(expected)<.01
				for event: Dictionary in action.vfx.definition.events:
					var body_index := int(String(event.node).trim_prefix("body_"))-1
					var source_clip: Dictionary = action.data.clips[body_index]
					aligned_effects = aligned_effects and MasterPhase2BodyAction.registration_offset(event)==MasterPhase2BodyAction.registration_offset(source_clip)
				ticks += 1
			check(ticks<900 and seen.size()==action.data.clips.size(),"All clips finish on the shared action clock")
			check(stable_root and dash_moves==(0 if id==MasterPhase2BodyAction.IDS[0] else 1),"Only the authored dash changes the landing point, once")
			check(aligned_shapes and aligned_effects,"Body, live claw collision and emitted effects share registration")
			var final_toe := master.to_local(_toe_world(master,Vector2(74,200),Vector2(256,256)))
			check(final_toe.distance_to(idle_toe)<.001,"Recovery returns to the same standing registration")
			await process_frame
	# Both arena edges clamp the intentional dash without a later return teleport.
	for edge in [master.world_min_x,master.world_max_x]:
		for direction in [-1.0,1.0]:
			target.position.x = edge
			master.movement_direction = direction
			master.start_phase_2_body_action(MasterPhase2BodyAction.IDS[1])
			master.phase_2_body_action.advance(.51)
			var landing := clampf(edge-direction*105,master.world_min_x,master.world_max_x)
			check(is_equal_approx(master.position.x,landing),"Dash landing stays inside arena in either facing")
			master._interrupt_phase_2_action(0)
			check(is_equal_approx(master.position.x,landing),"Interrupted recovery keeps the committed landing")
			await process_frame
	expect_save_untouched()
	finish("MASTER PHASE TWO LANDING")
