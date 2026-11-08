extends SceneTree
## Bake the accepted Studio rig by production phase, with explicit contact metadata.
const OUT="D:/HomingStar/homeing-star-test/artifacts/sandstorm-signature/tail_finisher_bake/"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.unfocusable=true
	root.position=Vector2i(-1500,-1500)
	DirAccess.make_dir_recursive_absolute(OUT)
	var view:=SubViewport.new()
	view.size=Vector2i(440,460)
	view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var rig=load("res://vfx/sand_scorpion_tail_study.gd").new()
	rig.autoplay=false
	rig.show_ground=false
	rig.show_contact_grit=false
	view.add_child(rig)
	var clips:={}
	var tips:=[]
	var clocks:=[]
	var frame:=0
	for key: String in ["wind","strike","hold","release"]:
		var count:=13 if key=="wind" else (11 if key=="strike" else (9 if key=="hold" else 21))
		clips[key]={"start":frame,"count":count}
		for sample in range(count):
			var u:=sample/float(count-1)
			var source:=0.0
			match key:
				"wind":
					var t:=u*.40
					source=lerpf(0.0,1.15,t/.12) if t<.12 else (lerpf(1.15,1.70,(t-.12)/.16) if t<.28 else lerpf(1.70,1.95,(t-.28)/.12))
				"strike": source=lerpf(1.95,2.16,u)
				"hold": source=lerpf(2.16,2.42,u)
				"release": source=lerpf(2.42,4.40,u)
			rig.elapsed=source
			await process_frame
			await RenderingServer.frame_post_draw
			var error:=view.get_texture().get_image().save_png(OUT+"frame_%03d.png"%frame)
			if error!=OK:
				push_error("Tail bake failed: "+str(error))
				quit(1)
				return
			tips.append([rig.tip.x,rig.tip.y])
			clocks.append(source)
			frame+=1
	var data:={"kind":"phase_locked_tail","cell":[440,460],"origin":[rig.contact_point.x,rig.contact_point.y],
		"frames":frame,"fps":60,"clips":clips,"frame_tips":tips,"source_clocks":clocks,
		"world_scale":1.15,"source":"combat-vfx-studio/studies/sandstorm_scorpion/tail_stab.tscn"}
	var file:=FileAccess.open(OUT+"bake.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"  "))
	file.close()
	print("BAKED phase-locked scorpion: ",frame," frames; contact ",rig.contact_point)
	view.queue_free()
	await process_frame
	quit()
