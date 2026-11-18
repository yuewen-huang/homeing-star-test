extends "test_twin_fish_lightning.gd"
## The fixture fills only previous charges. The final credit, scheduling, movement,
## defenses and damage all pass through the formal A27 encounter.
const MiddleHazard := preload("res://scripts/bosses/twin_fish/twin_fish_middle_hazard.gd")
const SkyColumn := preload("res://scripts/bosses/twin_fish/twin_fish_weak_column.gd")
const MID_REACTION := 0.20

class SeaRecorder extends OpeningRecorder:
	var rolling := false
	var draw_frame := 0
	func _process(_delta: float) -> void:
		if not rolling: return
		draw_frame += 1
		if draw_frame % 2 == 0: return
		await RenderingServer.frame_post_draw
		if not is_inside_tree(): return
		var file := "%04d.jpg" % frames.size()
		var image := get_viewport().get_texture().get_image()
		image.resize(960,540,Image.INTERPOLATE_BILINEAR)
		image.save_jpg(folder.path_join(file),0.92)
		frames.append({"file":file,"time":frames.size()/30.0})

func make_recorder() -> OpeningRecorder: return SeaRecorder.new()

func verify_opening() -> void:
	var args := OS.get_cmdline_user_args()
	var yang := "--yang" in args
	var grade := int(args[args.find("--tier")+1]) if "--tier" in args else 1
	var ignore_middle := "--ignore-middle" in args
	var hold_middle_lane := "--hold-middle-lane" in args
	var jump_middle_yin := "--jump-middle-yin" in args
	var middle_wall := "--middle-yang-wall" in args
	var middle_jump_in_place := "--middle-yang-jump-in-place" in args
	var middle_skip_jump := "--middle-yang-skip-jump" in args
	var middle_straight := "--middle-yang-straight" in args
	var ignore_strong := "--ignore-strong" in args
	var strong_route_option := args.find("--strong-yang-route")
	var strong_route := args[strong_route_option + 1] if strong_route_option >= 0 else ""
	var strong_wall := strong_route == "wall"
	var strong_wrong_route := not strong_route.is_empty() and not strong_wall
	var strong_double_jump := "--strong-yin-double-jump" in args
	var e := level.twin_fish_encounter
	walk(100)
	for i in 150:
		await physics_frame
		if e.engaged: break
	walk(0)
	var seeded := false
	for i in 800:
		await physics_frame
		if not seeded and is_instance_valid(e.fish):
			e.fish._swim_random.seed = 41019
			seeded = true
		if e.battle_ready: break
	if not e.battle_ready:
		quit(1)
		return
	var d := e.fish.lightning
	var sea := d.sea
	var side := int(yang)
	for i in (7 if yang else 3): sea.award(side)
	var other: int = [6,4,0][grade-1]
	for i in (other/2 if yang else other): sea.award(1-side)
	var rec: SeaRecorder
	for child in level.get_children():
		if child is SeaRecorder: rec = child
	var pressed := -10
	var opened := false
	var started := false
	var waves := {}
	var done_at := -1
	var sea_hp := 0
	var armed_at := -1.0
	var middle_first := 0.0
	var middle_return := 0.0
	var positioned_near_wall := false
	var hopped := false
	var double_jumped := false
	var hit_before_forks := false
	var strong_direction := 0.0
	var strong_pair := -1
	var strong_dash := false
	var strong_airborne_dash := false
	var strong_landed := false
	var previous_strong_t := 0.0
	var strong_layout_checked := false
	var spawn_x := 0.0
	for i in 2100:
		await physics_frame
		var x := d._target().x
		if i == pressed+3: Input.action_release(&"parry")
		if done_at >= 0:
			walk(0)
			if i >= done_at+15: break
			continue
		if sea.armed >= 0 and armed_at < 0:
			armed_at = d.clock
			print("ARM ",sea.charge," tier=",sea.tier," beat=",d.LABELS[d.beat])
			check(sea.tier == grade and sea.armed == side, "Real final event selects requested grade")
		if d.beat == Duel.Beat.OPEN: opened = true
		var needs_wall_start := yang and (grade == 2 and middle_wall or grade == 3 and strong_wall)
		if needs_wall_start and not positioned_near_wall and sea.armed >= 0 and d.beat == Duel.Beat.RECOVER:
			positioned_near_wall = true
			var wall_x := d.arena.end.x - sea.PLAYER_EDGE - 12.0
			level.player.reset_after_map_fall(d.fish.to_global(Vector2(wall_x, d.arena.end.y)))
		if sea.running:
			if not started:
				started = true
				spawn_x = x
				sea_hp = level.player.combat_stats.health
				print("SEA_BEGIN ",rec.frames.size() if rec else i," charge=",sea.charge)
				check(yang or opened and d.clock-armed_at >= Duel.OPEN_TIME, "Sea respects the clash punish window")
				if needs_wall_start: check(positioned_near_wall and d.arena.end.x - x < 72.0, "Lan starts near the right seal")
				if grade == 1:
					check(sea.cells.size() == (3 if yang else 4) and sea.cells.all(func(c): return c.strike_at == sea.cells[0].strike_at and not c.can_cut and c._attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER), "Weak columns strike together and cannot be parried")
					print("WEAK_MOVIE ", Engine.get_frames_drawn(), " impact_delay=",sea.cells[0].strike_at)
				elif grade == 2:
					check(sea.cells.all(func(c): return not c.can_cut and c._attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER), "Middle attacks cannot be parried")
					if yang:
						middle_return = x
						middle_first = x + (120.0 if x <= d.arena.get_center().x else -120.0)
						_check_middle_yang_layout(d, x)
					else:
						_check_yin_layout(d)
						middle_first = _middle_yin_landing(d, x)
				else:
					if yang:
						strong_direction = 1.0 if x <= d.arena.get_center().x else -1.0
					else:
						strong_pair = _strong_yin_pair(d, x)
						check(sea.cells.size() == 6 and strong_pair >= 0, "Five moving pearls and a ceiling begin the strong Yin pattern")
			if grade == 2:
				for cell in sea.cells:
					if sea.elapsed >= cell.strike_at: waves[cell.wave] = true
				if jump_middle_yin and sea.elapsed < sea.MIDDLE_YIN_STRIKE and level.player.combat_stats.health < sea_hp:
					hit_before_forks = true
				if ignore_middle:
					walk(0)
				elif yang:
					var move_at := sea.MIDDLE_SKY_SECOND_WARN + MID_REACTION
					var mark := middle_return if not hold_middle_lane and sea.elapsed >= move_at else middle_first
					var offset := middle_first - middle_return if middle_straight else mark - x
					walk(offset if sea.elapsed >= MID_REACTION and not middle_jump_in_place else 0.0)
					if not hopped and not middle_skip_jump and sea.elapsed >= sea.MIDDLE_SKY_STRIKE - 0.18:
						hopped = true
						Input.action_press(&"jump")
					if hopped and sea.elapsed >= sea.MIDDLE_SKY_STRIKE - 0.02:
						Input.action_release(&"jump")
				else:
					walk(middle_first - x if sea.elapsed >= MID_REACTION else 0.0)
					if jump_middle_yin:
						if not hopped and sea.elapsed >= 0.78:
							hopped = true
							Input.action_press(&"jump")
						elif not double_jumped and sea.elapsed >= 1.02:
							double_jumped = true
							Input.action_press(&"jump")
						elif hopped and sea.elapsed >= 0.88 and (not double_jumped or sea.elapsed >= 1.13):
							Input.action_release(&"jump")
				continue
			for c in sea.cells:
				if sea.elapsed >= c.strike_at: waves[c.wave] = true
			if grade == 1:
				if sea.elapsed > 0.15: _walk_weak_gap(d, x)
				else: walk(0)
				continue
			if not strong_layout_checked and sea.elapsed >= (sea.STRONG_YANG_SHIFT_WARN if yang else sea.STRONG_YIN_LOCK):
				strong_layout_checked = true
				_check_strong_layout(d, yang)
			if ignore_strong:
				walk(0)
			elif yang:
				_drive_strong_yang(d, strong_route, spawn_x, strong_direction, previous_strong_t)
				previous_strong_t = sea.elapsed
				strong_dash = strong_dash or level.player.attack_state == LanPlayer.AttackState.INSTANT_DASH
				double_jumped = double_jumped or level.player.double_jump_used
				strong_airborne_dash = strong_airborne_dash or level.player.attack_state == LanPlayer.AttackState.AERIAL_DASH
				strong_landed = strong_landed or (strong_airborne_dash and level.player.is_on_floor())
			else:
				if sea.elapsed >= MID_REACTION and strong_pair >= 0:
					var pair := _strong_yin_roots(d)
					walk((pair[strong_pair] + pair[strong_pair + 1]) * 0.5 - x)
				var jump_at := sea.STRONG_YIN_STRIKE - (0.48 if strong_double_jump else 0.19)
				if not hopped and sea.elapsed >= jump_at:
					hopped = true
					Input.action_press(&"jump")
				elif strong_double_jump and hopped and not double_jumped and sea.elapsed >= sea.STRONG_YIN_STRIKE - 0.09:
					double_jumped = true
					Input.action_press(&"jump")
				elif hopped and sea.elapsed >= jump_at + 0.15:
					Input.action_release(&"jump")
			continue
		if started:
			done_at = i
			print("SEA_END ",rec.frames.size() if rec else i," charges=",sea.charge," hp=",sea_hp,"->",level.player.combat_stats.health)
			if grade == 1: check(sea_hp == level.player.combat_stats.health, "Ordinary walking reaches the weak opening unharmed")
			elif grade == 2:
				var unhurt := sea_hp == level.player.combat_stats.health
				if jump_middle_yin:
					check(double_jumped and hit_before_forks, "A double jump reaches the wider ceiling before the forks discharge")
				elif ignore_middle or hold_middle_lane or middle_jump_in_place or middle_skip_jump or middle_straight:
					check(not unhurt, "Ignoring the middle pattern's movement takes damage")
					if hold_middle_lane: check(not sea._landed_waves.has(0) and sea._landed_waves.has(1), "The hop clears the surge but the side gap closes on the second beat")
					if middle_jump_in_place or middle_skip_jump:
						check(sea._landed_waves.has(0), "The first beat requires both leaving the column and clearing its surge")
				else:
					check(unhurt and (not yang or hopped), "The intended route clears the complete middle pattern unharmed")
			else:
				var unhurt := sea_hp == level.player.combat_stats.health
				print("STRONG_ROUTE x=", spawn_x, "->", x, " hit_waves=", sea._landed_waves.keys())
				if ignore_strong or strong_wrong_route or strong_double_jump:
					check(not unhurt, "Ignoring the intended strong pattern takes damage")
					if strong_route == "no-dash":
						var hits := sea._landed_waves.keys()
						check(double_jumped and not hits.is_empty() and hits[0] == 1,
							"Double jump clears the first beat but regular movement misses the next opening")
					elif strong_route == "single-jump":
						check(sea._landed_waves.has(0), "The raised floor catches a single jump")
					elif strong_route == "ground-dash":
						check(strong_dash and sea._landed_waves.has(0), "A ground dash does not clear the first gate")
					elif strong_route == "late-drop":
						check(not sea._landed_waves.has(0) and not sea._landed_waves.has(1) and sea._landed_waves.has(2),
							"An airborne dash reaches the second opening but staying high catches the final canopy")
				else:
					check(unhurt and (double_jumped and strong_airborne_dash and strong_landed if yang else hopped),
						"The intended route clears the strong pattern unharmed")
			check(sea.armed < 0 and sea.charge == Vector2i.ZERO, "Consumed charge clears after the spell")
			continue
		if rec and (d.beat == Duel.Beat.LOCK and d.age > 1.0 or d.beat == Duel.Beat.DASH):
			rec.rolling = true
		if yang:
			walk(220 if d.beat == Duel.Beat.LOCK or d.beat == Duel.Beat.AIM and d.age > 0.22 else 0)
			if d.beat == Duel.Beat.DASH and pressed < 0:
				var nose := d.lane_end - d.locked_direction*d.dash_left
				if nose.distance_to(d._target()) < 123:
					pressed = i
					walk(0)
					Input.action_press(&"parry")
		else:
			match d.beat:
				Duel.Beat.SWIM,Duel.Beat.CAST,Duel.Beat.LURE,Duel.Beat.AIM: walk(-320.0-x)
				Duel.Beat.LOCK: walk(d.orb.position.x-76.0-x if d.age>0.7 else -320.0-x)
				Duel.Beat.DASH: walk(-200)
				Duel.Beat.OPEN, Duel.Beat.RECOVER: walk(-320.0-x if grade == 2 else 0.0)
				_: walk(0)
		if d.cast_number > 1: break
	walk(0)
	Input.action_release(&"parry")
	Input.action_release(&"jump")
	Input.action_release(&"instant_dash")
	if rec: rec.rolling = false
	var expected_waves := grade if yang else 1
	check(started and done_at >= 0 and waves.size() == expected_waves, "The complete A27 sea emits the selected pattern")
	expect_save_untouched()
	finish("A27 SEA")

func _drive_strong_yang(d: Duel, route: String, start_x: float, direction: float, previous: float) -> void:
	var t := d.sea.elapsed
	var x := d._target().x
	Input.action_release(&"jump")
	Input.action_release(&"instant_dash")
	walk(0.0)
	var dash_at := d.sea.STRONG_YANG_SHIFT_WARN + MID_REACTION
	if route == "ground-dash":
		if previous < 0.96 and t >= 0.96:
			walk(direction * 200.0)
			Input.action_press(&"instant_dash")
		return
	var first_jump_at := 0.64
	var second_jump_at := 1.11 if route == "late-drop" else 1.02
	if previous < first_jump_at and t >= first_jump_at:
		Input.action_press(&"jump")
	elif route != "single-jump" and previous < second_jump_at and t >= second_jump_at:
		Input.action_press(&"jump")
	if route in ["late-drop", "no-dash"] and t >= MID_REACTION and t < d.sea.STRONG_YANG_LIFT_CLEAR:
		walk(start_x + direction * 47.0 - x)
	if route == "no-dash":
		if t >= d.sea.STRONG_YANG_LIFT_CLEAR: walk(direction * 240.0)
		return
	if route == "late-drop": dash_at = 1.69
	if previous < dash_at and t >= dash_at:
		walk(direction * 200.0)
		Input.action_press(&"instant_dash")

func _strong_yin_roots(d: Duel) -> PackedFloat32Array:
	var roots := PackedFloat32Array()
	for cell in d.sea.cells:
		if cell is MiddleHazard and cell.form == MiddleHazard.Form.FORK:
			roots.append(cell.position.x)
	return roots

func _strong_yin_pair(d: Duel, x: float) -> int:
	var roots := _strong_yin_roots(d)
	var pair := -1
	var distance := INF
	for i in roots.size() - 1:
		var delta := absf(x - (roots[i] + roots[i + 1]) * 0.5)
		if delta < distance:
			distance = delta
			pair = i
	return pair

func _check_strong_layout(d: Duel, yang: bool) -> void:
	check(d.sea.cells.all(func(c): return not c.can_cut and c._attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER), "Strong hazards cannot be parried")
	if yang:
		var layers := d.sea.cells.filter(func(c): return c is MiddleHazard and c.form == MiddleHazard.Form.CEILING)
		check(layers.size() == 2 and layers[0].position.y == d.arena.end.y and layers[0].span == d.arena.size.x
			and layers[1].position.y < layers[0].position.y, "The full-width floor and elevated canopy flip the vertical safe area")
		var lift := _column_openings(d, 0)
		var shift := _column_openings(d, 1)
		if lift.size() != 1 or shift.size() != 1:
			check(false, "Each gate has a single opening")
			return
		var gap := maxf(lift[0].x - shift[0].y, shift[0].x - lift[0].y)
		var body_width := (d._target_shape.shape as RectangleShape2D).size.x
		var run_reach := (d.sea.STRONG_YANG_SHIFT_STRIKE - d.sea.STRONG_YANG_LIFT_CLEAR) * LanPlayer.RUN_SPEED
		check(gap + body_width > run_reach, "The shifted opening is beyond ordinary sprint reach after the first gate clears")
		return
	var roots := _strong_yin_roots(d)
	check(d.sea.cells.all(func(c): return c.form != MiddleHazard.Form.FORK or c._tips.size() == 3), "Each locked pearl warns a three-pronged strike")
	var widest := 0.0
	for i in roots.size() - 1:
		widest = maxf(widest, roots[i + 1] - roots[i])
	var radius: float = d.sea.cells[1]._guard.radius
	var hurt_half := (d._target_shape.shape as RectangleShape2D).size.x * 0.5
	check(widest <= 2.0 * (radius + hurt_half) and roots[0] - radius - hurt_half <= d.arena.position.x + d.sea.PLAYER_EDGE \
		and roots[-1] + radius + hurt_half >= d.arena.end.x - d.sea.PLAYER_EDGE, "Locked domes close every standing gap across the reachable floor")

func _check_middle_yang_layout(d: Duel, start_x: float) -> void:
	var surges := d.sea.cells.filter(func(c): return c is MiddleHazard and c.form == MiddleHazard.Form.GROUND_SURGE)
	check(surges.size() == 1 and absf(surges[0].position.x - start_x) < 6.0, "The first impact anchors a surge at Lan's starting position")
	var openings := _column_openings(d, 1)
	check(openings.size() == 1 and openings[0].x < start_x and start_x < openings[0].y,
		"The second beat leaves one opening at the first impact")

func _column_openings(d: Duel, wave: int) -> Array[Vector2]:
	var edge := d.arena.position.x
	var openings: Array[Vector2] = []
	for cell in d.sea.cells:
		if cell.wave == wave and (cell is SkyColumn or (cell is MiddleHazard and cell.form == MiddleHazard.Form.SKY_STRIKE)):
			var left := cell.position.x - cell.span * 0.5
			if left > edge + 0.1: openings.append(Vector2(edge, left))
			edge = cell.position.x + cell.span * 0.5
	if edge < d.arena.end.x - 0.1: openings.append(Vector2(edge, d.arena.end.x))
	return openings

func _middle_yin_landing(d: Duel, x: float) -> float:
	var roots := PackedFloat32Array()
	for cell in d.sea.cells:
		if cell is MiddleHazard and cell.form == MiddleHazard.Form.FORK:
			roots.append(cell.position.x)
	var gap := x
	var distance := INF
	for i in roots.size() - 1:
		var center := (roots[i] + roots[i + 1]) * 0.5
		if absf(center - x) < distance:
			gap = center
			distance = absf(center - x)
	return gap

func _check_yin_layout(d: Duel) -> void:
	var forks: Array[MiddleHazard] = []
	var ceiling: MiddleHazard
	for cell in d.sea.cells:
		if cell is MiddleHazard and cell.form == MiddleHazard.Form.FORK: forks.append(cell)
		if cell is MiddleHazard and cell.form == MiddleHazard.Form.CEILING: ceiling = cell
	if forks.size() != 6 or not is_instance_valid(ceiling):
		check(false, "Yin has six fixed roots and a ceiling")
		return
	var width := minf(d.arena.size.x, 1280.0)
	var spacing := width / 6.0
	var left := d.arena.get_center().x - width * 0.5
	for i in forks.size():
		check(is_equal_approx(forks[i].position.x, left + (i + 0.5) * spacing), "Yin root %d is evenly spaced" % (i + 1))
	var rise := -forks[0]._tips[0].y
	var crossing := spacing / (2.0 * tan(MiddleHazard.FORK_ANGLE))
	var ceiling_bottom := d.arena.end.y - ceiling.position.y
	check(is_equal_approx(rise, ceiling_bottom + ceiling._height) and crossing < ceiling_bottom \
		and is_equal_approx(ceiling.span, d.arena.size.x), "Crossings sit below the full-width ceiling and the beams reach its top")
	var projection := ceiling.get_global_transform_with_canvas()
	var screen_height := absf((projection * Vector2(0.0, -ceiling._height)).y - projection.origin.y)
	check(is_equal_approx(screen_height, get_root().get_visible_rect().size.y * 0.5), "The ceiling spans half the visible screen height")

func _walk_weak_gap(d: Duel, x: float) -> void:
	var left := d.arena.position.x + 24.0
	var right := d.arena.end.x - 24.0
	var safe := clampf(x,left,right)
	var distance := INF
	for i in d.sea.cells.size() + 1:
		var edge := right
		if i < d.sea.cells.size():
			var cell := d.sea.cells[i]
			edge = cell.position.x - cell.span * 0.5 - 34.0
		if edge >= left:
			var candidate := clampf(x,left,edge)
			if absf(candidate-x) < distance:
				distance = absf(candidate-x)
				safe = candidate
		if i < d.sea.cells.size():
			var cell := d.sea.cells[i]
			left = cell.position.x + cell.span * 0.5 + 34.0
	walk(safe-x)

