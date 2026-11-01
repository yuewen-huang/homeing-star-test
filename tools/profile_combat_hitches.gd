extends SceneTree
## CPU setup, frame latency and cleanup measurements, with the production renderer.
const Wave := preload("res://scripts/vfx/studio_parry/parry_wave.gd")
const Ground := preload("res://scripts/bosses/master/studio_vfx/quake_effect.gd")
const Style := preload("res://scripts/bosses/master/studio_vfx/combo_style.gd")
const Score := preload("res://scripts/bosses/crystal_crab/crystal_crab_quake_rhythm.gd")
const Textures := preload("res://scripts/bosses/master/studio_vfx/quake/textures.gd")
var report := {}
var stage: Node2D
func _initialize() -> void: run.call_deferred()

func stats(samples: Array[float]) -> Dictionary:
	if samples.is_empty(): return {}
	samples.sort()
	return {"median_ms":samples[samples.size()/2], "p95_ms":samples[mini(samples.size()-1,int(samples.size()*0.95))], "max_ms":samples.back()}

func run() -> void:
	stage = Node2D.new()
	root.add_child(stage)
	var backdrop := ColorRect.new()
	backdrop.color = Color("354a46")
	backdrop.size = Vector2(1280,720)
	stage.add_child(backdrop)
	for i in 30: await process_frame
	var t := Time.get_ticks_usec()
	Textures.puff_atlas()
	report["dust_texture_first_ms"] = (Time.get_ticks_usec()-t)/1000.0
	t = Time.get_ticks_usec()
	Textures.puff_atlas()
	report["dust_texture_repeat_ms"] = (Time.get_ticks_usec()-t)/1000.0
	print("DUST ",JSON.stringify(report))
	for mode in ["idle","impact","danger","parry","quake"]:
		await sample(mode)
	await sample("parry")
	var deer := DeerBoss.new()
	deer.animated_sprite = AnimatedSprite2D.new()
	deer.add_child(deer.animated_sprite)
	deer._build_frames()
	var cold: Array[float] = []
	var warm: Array[float] = []
	for clip: String in DeerActionLibrary.clips():
		deer.animated_sprite.animation = clip
		for frame in mini(3,deer.animated_sprite.sprite_frames.get_frame_count(clip)):
			deer.animated_sprite.frame = frame
			t = Time.get_ticks_usec()
			deer.body_center_offset()
			cold.append((Time.get_ticks_usec()-t)/1000.0)
			t = Time.get_ticks_usec()
			deer.body_center_offset()
			warm.append((Time.get_ticks_usec()-t)/1000.0)
		await process_frame
	report["deer_body_cold"] = stats(cold)
	report["deer_body_warm"] = stats(warm)
	deer.free()
	print("COMBAT HITCH PROFILE ",JSON.stringify(report))
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if not output.is_empty():
		var file := FileAccess.open(output.path_join("combat_hitches.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	stage.free()
	quit()

func sample(mode: String) -> void:
	var holder := Node2D.new()
	stage.add_child(holder)
	var active: Array[Node2D] = []
	var frame_ms: Array[float] = []
	var spawn_ms: Array[float] = []
	var start := Time.get_ticks_usec()
	for frame in 150:
		if frame % 30 == 0:
			var t := Time.get_ticks_usec()
			var effect: Node2D
			match mode:
				"impact":
					effect = CombatImpactEffect.new()
					effect.setup(frame/30,1,Vector2(640,400),frame/30)
					effect.set_process(false)
				"danger": effect = DangerFlash.new(&"red")
				"parry":
					effect = Wave.new().configure({"red":frame>=60,"sparks":0,"flash":0},Vector2(640,400),5,NAN,false)
				"quake":
					Style.load_data(Score.effect_style())
					effect = Ground.new().configure(Score.effect_spec(320,2))
					effect.position = Vector2(640,555)
			if effect != null:
				holder.add_child(effect)
				active.append(effect)
			spawn_ms.append((Time.get_ticks_usec()-t)/1000.0)
		for effect in active:
			if not is_instance_valid(effect) or effect.is_queued_for_deletion(): continue
			if effect is DangerFlash:
				effect.show_at(fmod(frame/60.0,0.5)-0.2,1,Vector2(640,400))
			else:
				effect.advance(1.0/60)
				if mode != "impact" and effect.is_done(): effect.queue_free()
		await process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append((now-start)/1000.0)
		start = now
	var result := {"frame":stats(frame_ms),"spawn":stats(spawn_ms),"remaining_nodes":holder.find_children("*","",true,false).size(),"time_scale":Engine.time_scale,"texture_mb":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)/1048576.0}
	report[mode] = result
	print(mode," ",JSON.stringify(result))
	holder.free()
	for i in 3: await process_frame
