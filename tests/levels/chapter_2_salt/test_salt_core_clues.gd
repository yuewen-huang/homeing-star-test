extends SceneTree
const CLUE := preload("res://scripts/levels/chapter_2_salt/salt_core_clue.gd")
const PROJECTION := preload("res://scripts/levels/chapter_2_salt/salt_field_projection.gd")
class MemorySave extends SaveProgressService:
	var fail_write := false
	func load_progress() -> void:
		_config = ConfigFile.new()
		_loaded = true
	func save_progress() -> bool: return not fail_write
	func is_ability_unlocked(_ability: StringName) -> bool: return true
var checks := 0
var failures := 0
var field: Chapter2SaltField
var save: MemorySave

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func enter() -> void:
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate() as Chapter2SaltField
	root.add_child(field)
	current_scene = field
	field.set_physics_process(false)
	field.worms.ambush_chance = 0
func tick(seconds: float, digging := false) -> void:
	for i in ceili(seconds*60): field.step_exploration(1.0/60,Vector2.ZERO,digging,false)
func excavate(id: int) -> void:
	field.feet = field.piles[id].ground_position+Vector2(0,42)
	tick(1.05,true)
func capture(label_: String) -> void:
	var output := OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	if output.is_empty() or DisplayServer.get_name()=="headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label_+".png"))==OK,"Capture "+label_)
func run() -> void:
	var origin := Vector2(3600,900)
	for sector in 8:
		var offset := Vector2.RIGHT.rotated(sector*PI/4)*160
		var core := PROJECTION.unproject(PROJECTION.project(origin)+offset)
		check(CLUE.describe(origin,core).direction==CLUE.DIRECTIONS[sector],"Visible compass sector "+CLUE.DIRECTIONS[sector])
	for x in [480,3600,6720]:
		var from := Vector2(x,900)
		var core := PROJECTION.unproject(PROJECTION.project(from)+Vector2(0,-120))
		check(CLUE.describe(from,core).direction=="北","Screen-north clue stays north under perspective at x=%d" % x)
	for band in 5:
		var distance: float = [100,450,1000,2200,4000][band]
		var from := Vector2(1000,900)
		check(CLUE.describe(from,from+Vector2(distance,0)).band==band,"Distance band %d" % band)
	for limit in CLUE.DISTANCE_LIMITS:
		var from := Vector2(1000,900)
		var lower: int = CLUE.describe(from,from+Vector2(limit-0.1,0)).band
		var upper: int = CLUE.describe(from,from+Vector2(limit+0.1,0)).band
		check(upper==lower+1,"Distance changes only across threshold %.0f" % limit)
	var variants := {}
	for variant in 18:
		var text := CLUE.empty_hint(Vector2(1000,900),Vector2(1500,900),variant)
		variants[text] = true
		check(text.count("\n")==1 and text.contains("东") and not text.contains("西"),"Wording variation keeps correct direction")
	check(variants.size()==18,"Eighteen distinct wordings per direction and distance pair")
	var old := root.get_node("SaveProgress")
	root.remove_child(old)
	old.free()
	save = MemorySave.new()
	save.name = "SaveProgress"
	root.add_child(save)
	save._config.set_value("map_states","chapter_2_salt_field",{"boss_pile":1,"dug":[]})
	enter()
	field.feet = field.piles[4].ground_position+Vector2(0,42)
	tick(0.4,true)
	check(field.dig_hint.is_empty(),"Partial excavation reveals no clue")
	tick(1.0/60)
	tick(0.4,true)
	check(field.dig_hint.is_empty(),"Interrupted digging does not reveal a clue")
	tick(0.7,true)
	var expected := CLUE.empty_hint(field.piles[4].ground_position,field.piles[1].ground_position,0)
	check(field.dig_hint==expected and field.status.text==expected,"Successful empty excavation displays clue from the actual saved core position")
	await capture("salt_core_empty_far")
	var first_hint := field.dig_hint
	save.fail_write = true
	excavate(5)
	check(field._dig_failed and not field.piles[5].excavated and field.dig_hint==first_hint,"Failed excavation save creates neither empty pit nor new clue")
	save.fail_write = false
	tick(1.0/60)
	excavate(5)
	check(field.piles[5].excavated and field.dig_hint!=first_hint and not field.boss_found,"Another empty heap yields a fresh clue without revealing the core")
	field.feet += Vector2(40,0)
	tick(2)
	check(field.status.text==field.dig_hint and field.dig_hint_remaining>0,"Clue remains readable while exploring")
	tick(5)
	check(field.dig_hint_remaining==0 and field.status.text!=field.dig_hint,"Clue expires and ordinary exploration prompt returns")
	excavate(1)
	check(field.boss_found and field.dig_hint.contains("找到核心") and not field.dig_hint.contains("空空如也"),"Digging the correct heap announces the core discovery")
	await capture("salt_core_discovered")
	check(field.crab_encounter.active,"Core discovery starts the production encounter")
	field.crab_encounter.crab.combat_stats.apply_health_damage(999)
	await process_frame
	excavate(6)
	check(field.dig_hint.contains("已经确认") and not field.dig_hint.contains("方向"),"Further empty digs do not send the player toward an already found core")
	field.free()
	current_scene = null
	enter()
	check(field.boss_found and int(field.state.boss_pile)==1 and field.piles[1].excavated,"Reentry preserves core identity and discovery")
	field.free()
	current_scene = null
	await process_frame
	print("SALT CORE CLUES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
