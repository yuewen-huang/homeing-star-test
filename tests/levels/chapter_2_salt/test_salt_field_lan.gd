extends SceneTree

class MemorySave extends SaveProgressService:
	func load_progress() -> void:
		_config = ConfigFile.new(); _loaded = true
	func save_progress() -> bool: return true
	func is_ability_unlocked(_ability: StringName) -> bool: return true

var field: Chapter2SaltField
var lan: LanPlayer
var checks := 0
var failures := 0
var output := ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("OK " if ok else "FAIL ",message)
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code; event.keycode = code; event.pressed = true
	root.push_input(event)
	event = event.duplicate(); event.pressed = false; root.push_input(event)
func tick(seconds: float, movement := Vector2.ZERO, dig := false, running := false) -> void:
	for i in ceili(seconds*60): field.step_exploration(1.0/60,movement,dig,false,running)
func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png")) == OK,"Capture "+label)

func run() -> void:
	output = OS.get_environment("HOMING_STAR_TEST_OUTPUT")
	var real_save := root.get_node("SaveProgress")
	root.remove_child(real_save); real_save.free()
	var save := MemorySave.new(); save.name = "SaveProgress"; root.add_child(save)
	field = load("res://scenes/levels/chapter_2_salt/chapter_2_salt_field.tscn").instantiate() as Chapter2SaltField
	root.add_child(field); current_scene = field
	field.set_physics_process(false)
	await process_frame; await process_frame
	lan = field.pawn.player
	check(lan is LanPlayer and lan.scene_file_path == "res://scenes/player/lan/lan_player.tscn","Actual Lan scene replaces geometric pawn")
	check(not lan.is_physics_processing() and lan.collision_mask == 0,"Side-view gravity and vertical body collision cannot override planar feet")
	check(lan.animated_sprite.animation == &"idle" and lan.air_state == LanPlayer.AirState.GROUNDED,"Lan begins in her real grounded idle")
	await capture("salt_lan_idle")
	field.feet = Vector2(1700,1500)
	tick(0.1,Vector2.RIGHT)
	check(lan.animated_sprite.animation in [&"start_walk",&"walk"] and lan.facing_direction == 1,"Rightward movement plays authored walking and faces right")
	await create_timer(0.15).timeout
	check(lan.animated_sprite.animation == &"walk","Walk startup transitions into the walking loop")
	await capture("salt_lan_walk_right")
	var facing := lan.facing_direction
	var before := field.feet
	tick(0.2,Vector2.UP)
	check(field.feet.y<before.y and lan.facing_direction==facing \
		and lan.air_state==LanPlayer.AirState.GROUNDED and lan.animated_sprite.animation==&"walk","Upward exploration preserves facing and walk instead of jumping")
	tick(0.1,Vector2.LEFT)
	check(lan.facing_direction==-1 and not lan.animated_sprite.flip_h,"Leftward movement mirrors Lan with the production facing rule")
	await capture("salt_lan_walk_left")
	before = field.feet
	tick(0.2,Vector2.RIGHT,false,true)
	check(field.feet.x>before.x+50 and lan.animated_sprite.animation in [&"run_start",&"run"],"Running uses production speed and clips")
	await create_timer(0.25).timeout
	check(lan.animated_sprite.animation==&"run","Run startup reaches the running loop")
	await capture("salt_lan_run")
	tick(0.1,Vector2.RIGHT)
	check(lan.animated_sprite.animation in [&"start_walk",&"walk"],"Releasing run returns to walking while still moving")
	tick(0.1)
	check(lan.animated_sprite.animation==&"idle","Stopping restores standing idle")
	field.feet = Vector2(1800,1500)
	var stamina := lan.combat_stats.stamina
	field.step_exploration(0.1,Vector2.RIGHT,false,true)
	check(lan.animated_sprite.animation==&"back_dodge" and lan.animated_sprite.frame>0 \
		and field.dodge_remaining>0,"Horizontal dodge plays and advances the original combat timeline")
	check(lan.combat_stats.stamina<stamina,"Dodge uses Lan's actual stamina cost")
	check(is_equal_approx(field.pawn.dodge_duration,lan.combat_timeline.get_animation(&"back_dodge").length/LanPlayer.BACK_DODGE_SPEED_SCALE),"Dodge movement duration matches the full authored clip")
	await capture("salt_lan_dodge")
	before = field.feet
	tick(0.15,Vector2.UP)
	check(is_equal_approx(field.feet.y,before.y),"Up input cannot turn horizontal dodge into a diagonal")
	tick(field.pawn.dodge_duration+0.05)
	check(lan.ground_action_state==LanPlayer.GroundActionState.NONE and lan.animated_sprite.animation==&"idle","Dodge ends without a frozen pose or sideways offset")
	var pile := field.piles[16]
	field.feet = pile.ground_position+Vector2(0,42)
	tick(0.4,Vector2.ZERO,true)
	check(field.pawn.digging_pose and lan.animated_sprite.animation==&"crouch" and field.dig_elapsed>0,"Holding E reuses crouch art for excavation")
	await capture("salt_lan_dig")
	tick(1.0/60)
	check(not field.pawn.digging_pose and lan.animated_sprite.animation==&"idle","Releasing excavation returns to idle rather than leaving Lan crouched")
	tick(0.2,Vector2.ZERO,true)
	tick(0.1,Vector2.DOWN)
	check(lan.animated_sprite.animation in [&"start_walk",&"walk"] \
		and lan.ground_action_state==LanPlayer.GroundActionState.NONE and field.dig_elapsed==0,"Down cancels digging into walking rather than triggering a crouch input")
	field.feet = Vector2(1800,1500)
	tick(0.1)
	key(KEY_J)
	tick(0.15)
	check(lan.attack_state==LanPlayer.AttackState.ATTACK_1X and lan.animated_sprite.animation==&"attack_1x", "J starts the production ground attack")
	await capture("salt_lan_attack")
	before = field.feet
	tick(0.05,Vector2.RIGHT)
	check(field.feet==before,"Ground attack holds the planar position")
	key(KEY_J)
	check(lan.attack_queued,"Next J queues the existing combo continuation")
	tick(0.7)
	check(lan.attack_state!=LanPlayer.AttackState.ATTACK_1X,"Combo follows the production continuation rather than restarting its first cut")
	tick(2)
	check(lan.attack_state==LanPlayer.AttackState.NONE and lan.animated_sprite.animation==&"idle","Attack timeline finishes and releases movement")
	key(KEY_K)
	tick(0.05)
	check(lan.defense_state!=LanPlayer.DefenseState.NONE and lan.animated_sprite.animation==&"parry","K plays the real parry action")
	await capture("salt_lan_parry")
	await create_timer(1.5).timeout
	tick(0.1)
	check(lan.defense_state==LanPlayer.DefenseState.NONE,"Parry recovery releases movement normally")
	field.feet = Vector2(1800,120)
	field._sync_view(0)
	check(field.pawn.scale.x<0.65 and lan.animated_sprite.scale==Vector2(1.5,1.5),"Perspective scales Lan's whole scene while preserving her authored sprite scale")
	await capture("salt_lan_far")
	field.free(); current_scene = null
	await process_frame; await process_frame
	print("SALT FIELD LAN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
