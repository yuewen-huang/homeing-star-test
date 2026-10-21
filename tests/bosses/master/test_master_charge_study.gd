extends "test_master_pose_flow_study.gd"

func _init() -> void:
	study_action = 3
	study_id = &"lunge_combo"
	contact_count = 2

func check_source_registration(rhythm: MasterClashRhythm) -> void:
	# Measured last boot pixels in the source PNGs, independent of the node origin.
	var grounded := true
	var old_time := rhythm.elapsed
	for sample in [[1.00,Vector2(265,229)],[1.07,Vector2(265,229)],[1.11,Vector2(265,309)]]:
		rhythm.elapsed = float(sample[0])
		rhythm._show(rhythm.frame_at(rhythm.elapsed))
		var sprite := master.animated_sprite
		var size := sprite.sprite_frames.get_frame_texture(sprite.animation,sprite.frame).get_size()
		var mirror := Vector2(-1.0 if sprite.flip_h else 1.0,1.0)
		var boot := sprite.to_global(((sample[1] as Vector2)-size*0.5)*mirror)
		grounded = grounded and absf(boot.y-master.global_position.y) <= 2.0
	check(grounded,"Measured boot pixels remain on the floor before and after the dash-to-heavy transition")
	rhythm.elapsed = old_time
	rhythm._show(rhythm.frame_at(old_time))
