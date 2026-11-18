extends "test_twin_fish_lightning.gd"
## The fixture fills only previous charges. The final credit, scheduling, movement,
## defenses and damage all pass through the formal A27 encounter.
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
	var cut_input := false
	var opened := false
	var started := false
	var gap := false
	var waves := {}
	var done_at := -1
	var sea_hp := 0
	var armed_at := -1.0
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
		if sea.running:
			if not started:
				started = true
				sea_hp = level.player.combat_stats.health
				print("SEA_BEGIN ",rec.frames.size() if rec else i," charge=",sea.charge)
				check(yang or opened and d.clock-armed_at >= Duel.OPEN_TIME, "Sea respects the clash punish window")
				if grade == 1:
					check(sea.cells.size() == (3 if yang else 4) and sea.cells.all(func(c): return c.strike_at == sea.cells[0].strike_at and not c.can_cut and c._attack.danger_type == CombatAttackData.DangerType.UNPARRYABLE_DANGER), "Weak columns strike together and cannot be parried")
					print("WEAK_MOVIE ", Engine.get_frames_drawn(), " impact_delay=",sea.cells[0].strike_at)
			var soonest := INF
			var nearest_cell: Node2D
			var best := INF
			for c in sea.cells:
				if c.broken: gap = true
				if sea.elapsed >= c.strike_at: waves[c.wave] = true
				if c.strike_at+0.22 < sea.elapsed or c.broken: continue
				soonest = minf(soonest,c.strike_at)
				if c.wave == 0 and absf(x-c.position.x)<best:
					nearest_cell = c
					best = absf(x-c.position.x)
			if not yang and grade == 3 and nearest_cell and not cut_input:
				walk(nearest_cell.position.x-x)
				if sea.elapsed >= nearest_cell.strike_at-0.45:
					pressed = i
					cut_input = true
					Input.action_press(&"parry")
			elif grade == 1 and sea.elapsed > 0.15:
				_walk_weak_gap(d, x)
			elif soonest < INF and soonest-sea.elapsed < 0.94:
				_evade(d,x,soonest)
			else: walk(0)
			continue
		if started:
			done_at = i
			print("SEA_END ",rec.frames.size() if rec else i," charges=",sea.charge," core_open=",gap," hp=",sea_hp,"->",level.player.combat_stats.health)
			if grade == 1: check(sea_hp == level.player.combat_stats.health, "Ordinary walking reaches the weak opening unharmed")
			check(sea.armed < 0 and sea.charge.x == 0 and sea.charge.y == (1 if gap else 0), "Consumed charge clears and real core parry carries once")
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
				_: walk(0)
		if d.cast_number > 1: break
	walk(0)
	Input.action_release(&"parry")
	if rec: rec.rolling = false
	check(started and done_at >= 0 and waves.size() == grade, "The complete A27 sea emits the selected number of waves")
	if not yang and grade == 3: check(gap,"Lan opens a strong yin core with parry input")
	finish("A27 SEA")

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

func _evade(d: Duel,x: float,soonest: float) -> void:
	var width := (d.arena.size.x-52.0)/d.sea.LANES
	var blocked := PackedInt32Array()
	var threatened := false
	for cell in d.sea.cells:
		if cell.broken or cell.strike_at+0.22 < d.sea.elapsed or absf(cell.strike_at-soonest)>0.55: continue
		var lane := floori((cell.position.x-d.arena.position.x-26.0)/width)
		blocked.append(lane)
		if absf(cell.position.x-x)<width*0.5+24.0: threatened = true
	if not threatened:
		walk(0)
		return
	var best := INF
	var offset := 0.0
	for lane in d.sea.LANES:
		if lane in blocked: continue
		var dx := d.arena.position.x+26+(lane+0.5)*width-x
		if absf(dx)<best:
			best = absf(dx)
			offset = dx
	walk(offset)

