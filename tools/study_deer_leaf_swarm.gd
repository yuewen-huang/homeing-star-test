extends SceneTree
## Run against combat-vfx-studio, not the game. Uses the original editor renderer.
const Swarm = preload("res://vfx/swarm_effect.gd")
const Catalog = preload("res://vfx/editor_catalog.gd")
const OUTPUT := "E:/HomingStar/homeing-star-test/artifacts/deer-leaf-study-20261104"

class StudyStage extends Node2D:
	const GROUND_Y := 555.0
	const TARGET_SIZE := Vector2(24,58)
	var attacker := Node2D.new()
	var target := Node2D.new()
	var TIMELINE: Array = []
	var actors := {}
	func _init() -> void:
		attacker.position = Vector2(360,555)
		target.position = Vector2(800,555)
		add_child(attacker)
		add_child(target)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280,720)
	DisplayServer.window_set_size(root.size)
	ComboStyle.data = {"quake_style":"real","quake_detail":"explosive"}
	var original: Dictionary = {}
	for item: Array in Catalog.PRESETS.swarm:
		if String(item[0]).begins_with("落叶"):
			original = item[3].duplicate(true)
	assert(not original.is_empty())
	original.merge({"t":0.0,"do":"swarm","id":"autumn_reference"},true)
	var olive := ["202719","414e29","87984f","d1d8a3","f2efd2"]
	var studies := [
		{"name":"reference","title":"编辑器原预设 · 落叶 / 秋风回旋","events":[original]},
		{"name":"surface","title":"同一落叶材质 · 卷边 / 叶脉 / 翻面光照","events":[
			{"t":0.0,"do":"swarm","id":"leaf_surface","material":"leaf","form":"cloud","at":[640,370],"radius":480.0,"height":370.0,"count":50,"size":3.4,"ramp":olive,"turbulence":3.0,"leaf_curl":.7,"leaf_sway":.45,"linger":6.0}]},
		{"name":"motion","title":"编排研究 · 聚叶 → 定向流动 → 散开 → 飘落","events":[
			{"t":0.0,"do":"swarm","id":"leaf_motion","material":"leaf","form":"cloud","at":[300,400],"radius":65.0,"height":110.0,"count":80,"size":.65,"ramp":olive,"turbulence":5.0,"leaf_sway":.25,"leaf_curl":.6,"linger":5.0},
			{"t":.65,"do":"swarm","id":"leaf_motion","material":"leaf","form":"stream","at":[970,420],"time":.24,"path":[[300,400],[490,345],[720,395],[970,420]],"travel":.8,"length":.6,"width":35.0},
			{"t":1.5,"do":"swarm","id":"leaf_motion","material":"leaf","form":"burst","at":[970,420],"time":.16,"radius":175.0,"height":130.0},
			{"t":2.12,"do":"swarm","id":"leaf_motion","material":"leaf","form":"fall","at":[970,450],"time":.4,"radius":200.0,"height":85.0},
			{"t":3.2,"do":"swarm","id":"leaf_motion","form":"gone","time":.5}]}]
	# Explicit full events are reproducible in the editor and avoid its 6000-capacity
	# default when later events omit count. Do not modify the source editor defaults.
	for study: Dictionary in studies:
		var inherited := {}
		for i in study.events.size():
			inherited.merge(study.events[i],true)
			study.events[i] = inherited.duplicate(true)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var record := FileAccess.open(OUTPUT.path_join("studies.json"),FileAccess.WRITE)
	record.store_string(JSON.stringify(studies,"\t"))
	record.close()
	for study: Dictionary in studies:
		var stage := StudyStage.new()
		stage.TIMELINE = study.events
		root.add_child(stage)
		var back := ColorRect.new()
		back.color = Color("222a27")
		back.size = Vector2(1280,720)
		back.z_index = -5
		stage.add_child(back)
		var title := Label.new()
		title.text = study.title
		title.position = Vector2(28,22)
		title.add_theme_font_size_override("font_size",24)
		title.z_index = 10
		stage.add_child(title)
		var swarm: Node2D = Swarm.new().configure(study.events[0],stage)
		stage.add_child(swarm)
		var folder := OUTPUT.path_join(study.name)
		DirAccess.make_dir_recursive_absolute(folder)
		var event_index := 1
		for frame in 49:
			var t := frame/12.0
			if frame > 0: swarm.advance(1.0/12)
			while event_index < study.events.size() and float(study.events[event_index].t) <= t:
				var event: Dictionary = study.events[event_index].duplicate(true)
				# In the editor these inherit the named swarm's existing appearance.
				var merged: Dictionary = swarm.spec.duplicate(true)
				merged.merge(event,true)
				swarm.morph(merged)
				event_index += 1
			await process_frame
			RenderingServer.force_draw(false)
			await process_frame
			RenderingServer.force_draw(false)
			var error := root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frame))
			assert(error == OK)
		print("CAPTURED ",study.name," capacity=",swarm.capacity)
		stage.free()
		await process_frame
	print("LEAF STUDY READY ",OUTPUT)
	quit()
