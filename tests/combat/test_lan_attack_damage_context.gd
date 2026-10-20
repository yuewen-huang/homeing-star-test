extends SceneTree
const ATTACK_CATALOG := preload("res://scripts/player/lan/lan_attack_effect_catalog.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var contexts: Array[RefCounted] = [
		ATTACK_CATALOG.attack_1x().attack_hit_context,
		ATTACK_CATALOG.attack_2x().attack_hit_context,
		ATTACK_CATALOG.attack_2x_1().attack_hit_context,
		ATTACK_CATALOG.attack_2x_2().attack_hit_context,
		ATTACK_CATALOG.attack_3x(25.0).attack_hit_context,
		ATTACK_CATALOG.jump_attack_1x(25.0).attack_hit_context,
		ATTACK_CATALOG.jump_attack_2x(25.0).attack_hit_context,
		ATTACK_CATALOG.dodge_attack_1x(25.0).attack_hit_context,
		ATTACK_CATALOG.dodge_attack_2x(25.0).attack_hit_context,
		ATTACK_CATALOG.dodge_attack_3x(0.0).attack_hit_context,
		ATTACK_CATALOG.instant_dash().attack_hit_context,
	]
	var expected := [10, 10, 10, 10, 22, 12, 12, 14, 14, 18, 14]
	var expected_poise := [3, 3, 3, 3, 7, 4, 4, 4, 4, 4, 4]
	var failed := false
	for index in contexts.size():
		var hit := contexts[index]
		if hit == null or int(hit.get("health_damage")) != expected[index] \
			or int(hit.get("poise_damage")) != expected_poise[index] \
			or int(hit.get("legacy_damage")) != 1:
			push_error("Lan attack damage context mismatch at index %d" % index)
			failed = true
	if CombatTuning.LAN_SWORD_WAVE_DAMAGE != 35 \
		or CombatTuning.LAN_HEAVY_SWORD_WAVE_DAMAGE != 65 \
		or CombatTuning.LAN_SPECIAL_DAMAGE != 45 \
		or CombatTuning.LAN_SPECIAL_CHARGED_DAMAGE != 110 \
		or CombatTuning.LAN_SPECIAL_MAX_DAMAGE != 200 \
		or CombatTuning.DEER_VINE_ULTIMATE_DAMAGE != 200 \
		or CombatTuning.LAN_ULTIMATE_HIT_DAMAGE * 16 \
			+ CombatTuning.LAN_ULTIMATE_FINISHER_HIT_DAMAGE * 8 != 280:
		push_error("Combat skill damage tuning does not match the design table")
		failed = true
	if CombatTuning.damage_during_poise_break(45, true) != 68 \
		or CombatTuning.damage_during_poise_break(6, true, true) != 6:
		push_error("Poise break damage multiplier or ultimate exemption mismatch")
		failed = true
	if CombatTuning.boss_player_damage(CombatAttackData.DangerType.NORMAL) != 10 \
		or CombatTuning.boss_player_damage(CombatAttackData.DangerType.COUNTERABLE_DANGER) != 18 \
		or CombatTuning.boss_player_damage(CombatAttackData.DangerType.UNPARRYABLE_DANGER) != 24 \
		or CombatTuning.BOSS_PLAYER_FINISHER_DAMAGE != 45 \
		or CombatTuning.LAN_PARRY_FAILURE_DAMAGE_MULTIPLIER != 0.5:
		push_error("Boss-to-player damage mapping or failed-parry reduction mismatch")
		failed = true
	quit(1 if failed else 0)
