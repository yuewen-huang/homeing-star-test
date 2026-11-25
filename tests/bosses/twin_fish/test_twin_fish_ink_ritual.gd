extends "../../../tools/level_design/preview_twin_fish_arena.gd"
## A27 at game speed. Arrange two dash interceptions near the thresholds;
## the duel owns the clash, and only its normal cues can advance the painting.
const Duel := preload("res://scripts/bosses/twin_fish/twin_fish_lightning_duel.gd")

func initial_movement() -> int: return Duel.Movement.LIANGYI

func verifying() -> bool: return true

func verify_opening() -> void:
	var encounter := level.twin_fish_encounter
	Input.action_press(&"ui_right")
	for i in 110:
		await physics_frame
		if encounter.engaged: break
	Input.action_release(&"ui_right")
	var marked := 0
	var placed := 0
	var settled := 0
	var held := 0
	var first_rim := Rect2()
	var stable_rim := true
	for i in 4000:
		await physics_frame
		var fish := encounter.fish
		if not is_instance_valid(fish): continue
		var field := fish._taichi_array
		if not field.playing_first_array: continue
		if first_rim.has_area():
			stable_rim = stable_rim and first_rim.is_equal_approx(field.painted_bounds())
		var d := fish.lightning
		if is_instance_valid(d) and d.beat == Duel.Beat.DASH and placed < 2 and d.cast_number > placed:
			d.clashes = placed * 2 + 1
			var ahead := d.lane_end - d.locked_direction * (d.dash_left - 12.0)
			d.orb.release(ahead,Vector2.ZERO,d.cast_number)
			placed += 1
		if field.stage > marked + 0.001 and marked < 4:
			marked += 1
			print("INK_START ",marked," ",Engine.get_frames_drawn())
		if settled < 4 and field.stage >= settled + 0.9999:
			settled += 1
			print("INK_DRY ",settled," ",Engine.get_frames_drawn())
			var count: int = [2,2,4,8][settled-1]
			check(field.active_core_positions().size()==count, "Written stage %d has %d cores" % [settled,count])
			if settled == 1:
				first_rim = field.painted_bounds()
				var diameter := minf(encounter.arena.size.x, encounter.arena.size.y) * encounter.FIELD_FRACTION
				check(is_equal_approx(first_rim.size.x, diameter), "The open rim has the A27 first-array diameter")
			if settled == 3 or settled == 4:
				check(d.clashes == (2 if settled == 3 else 4), "The duel's orb interception advanced the array")
			if settled == 4:
				var gates := field.active_core_positions()
				check(gates[0].y < 0 and absf(gates[0].x) < 0.1 and gates[2].x > 0 and absf(gates[2].y) < 0.1,"Kan is north and Zhen is east")
		if settled == 4:
			held += 1
			if held >= 70: break
	check(settled == 4, "A27 writes Taiji, Liangyi, Sixiang and Bagua in order")
	check(stable_rim, "The rim keeps its opening position and diameter through every transition")
	finish("TWIN FISH INK RITUAL")
