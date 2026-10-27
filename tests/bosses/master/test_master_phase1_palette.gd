extends "../../support/harness.gd"
## Verify the editor snapshot reaches composed production effects and stays owner-local.

func ground_palette(node: Node) -> int:
	var count := 0
	if node is CanvasItem:
		var material := (node as CanvasItem).material as ShaderMaterial
		if material!=null and material.shader!=null:
			for parameter: Dictionary in material.shader.get_shader_uniform_list():
				if parameter.name=="ramp":
					check(material.get_shader_parameter("ramp")==MasterPhase1Palette.ramp(),"Ground layer uses the production steel-blue ramp: "+String(node.name))
					count+=1
	for child in node.get_children(): count+=ground_palette(child)
	return count

func run() -> void:
	use_memory_progress()
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MasterPhase1Palette.DATA))
	check(data.blade_style=="brush" and data.editor_palette_label=="钢蓝","Snapshot records the selected editor look")
	check(FileAccess.get_sha256(MasterPhase1Palette.BRUSH.resource_path)==data.sources["brush_trail.gdshader"],"Production brush shader matches the imported Studio shader byte for byte")
	var room := load("res://scenes/levels/tutorial/tutorial_battle_room.tscn").instantiate() as Node2D
	root.add_child(room)
	current_scene=room
	var master := room.get_node("MasterBoss") as MasterBoss
	var player := room.get_node("Lan") as LanPlayer
	master.set_process(false)
	master.manual_control=true
	player.set_physics_process(false)
	player.position.x=2500
	# Let Lan's deferred, world-owned dodge visual join the specimen before teardown.
	await process_frame
	for id: StringName in MasterActionLibrary.MOVE_IDS:
		master._cancel_phase_1_action()
		check(master.start_phase_1_action(id),"Production move starts: "+id)
		var action := master.phase_1_action
		action.advance(float(action.timeline.cuts[0].release)+.01)
		var ribbon: MasterBladeTrail=action._ribbons[0]
		check(ribbon.palette==MasterPhase1Palette.inks() and ribbon.shader_material.shader==MasterPhase1Palette.BRUSH,"Authored blade uses brush + steel blue: "+id)
		action._leave_ghost([])
		check(action._ghosts[-1].node.modulate==MasterPhase1Palette.ghost(),"Recovery ghost uses steel-blue tint: "+id)
		if id in [&"combo_four",&"combo_five",&"mountain"]:
			action.advance(float(action.timeline.cuts[-1].contact_at)-action.elapsed+.001)
			var qi: MasterSwordQi=action.sword_qi
			check(ground_palette(qi.effect)>=6,"All composed qi layers have a palette: "+id)
			if qi is MasterGreatbladeSwordQi:
				check(qi.effect.layers.body.material.get_shader_parameter("palette_steel")==true,"Continuous translucent steel uses the new palette")
	master._cancel_phase_1_action()
	var sword := MasterFlyingSword.new()
	root.add_child(sword)
	for i in 4:
		check(sword.energy.get_shader_parameter("ink_%d" % i)==MasterPhase1Palette.inks()[i],"Flying weapon receives ink %d" % i)
	check(sword.trail.gradient.get_color(1)==Color(MasterPhase1Palette.inks()[1],.58),"Flying weapon tail uses steel blue")
	var ribbon := MasterFlyingSwordRibbon.new()
	root.add_child(ribbon)
	check(ribbon.palette==MasterPhase1Palette.inks() and ribbon.shader_material.shader==MasterPhase1Palette.BRUSH,"Patrol ribbon uses the same imported brush shader")
	check(ribbon.shader_material.get_shader_parameter("age_from_birth")==true,"Flying and held ribbons retain their different UV age contracts")
	master.charged_power=2
	master.spirit_aura.update_visual(0)
	check(master.spirit_aura.spirit_material.get_shader_parameter("phase1_palette")==true,"Phase-one spirit uses steel-blue smoke")
	master.phase=2
	master.spirit_aura.update_visual(0)
	check(master.spirit_aura.spirit_material.get_shader_parameter("phase1_palette")==false and master.spirit_aura.spirit_material.get_shader_parameter("aura_colour")==Color("ff352f"),"Phase-two aura retains red")
	var shared := DodgeBulletTimeVisual.new()
	root.add_child(shared)
	check(shared.palette_override.is_empty() and shared.overlay_material.get_shader_parameter("tint")==null,"Shared dodge defaults remain unchanged")
	master.phase=1
	var response := MasterDodgeResponse.new()
	master.add_child(response)
	response.setup(master,player)
	check(response.visual.palette_override==MasterPhase1Palette.inks(),"Only the Master's own dodge response gets steel blue")
	response.cancel()
	shared.free()
	ribbon.free()
	sword.free()
	room.free()
	current_scene=null
	await process_frame
	expect_save_untouched()
	finish("MASTER PHASE ONE PALETTE")
