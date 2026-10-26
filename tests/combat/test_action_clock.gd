extends "../support/harness.gd"
## ActionClock (restructure P4, 2026-10-19): the shared action time every attacker uses for
## dodge bullet time and parry pauses. Checks the clock's rules, that BossBase combines it with
## the red-parry hold and still answers to the old _dodge_remaining/_parry_pause names, and
## that the master keeps its own slower bullet time.

func run() -> void:
	var clock := ActionClock.new()
	check(is_equal_approx(clock.scale(), 1.0), "A fresh clock runs at full speed")
	clock.start_dodge_slow(0.5)
	check(is_equal_approx(clock.scale(), ActionClock.DODGE_SLOW) and is_equal_approx(ActionClock.DODGE_SLOW, 0.25), "A perfect dodge slows the attacker to 0.25")
	clock.advance(0.3)
	check(is_equal_approx(clock.dodge_remaining, 0.2) and clock.is_slowed(), "Bullet time counts down in real seconds")
	clock.start_dodge_slow(0.1)
	check(is_equal_approx(clock.dodge_remaining, 0.1), "start_dodge_slow replaces a running bullet time")
	clock.extend_dodge_slow(0.05)
	check(is_equal_approx(clock.dodge_remaining, 0.1), "extend_dodge_slow keeps the longer one")
	clock.extend_dodge_slow(0.4)
	check(is_equal_approx(clock.dodge_remaining, 0.4), "extend_dodge_slow lengthens a shorter one")
	clock.pause(0.2)
	check(is_zero_approx(clock.scale()), "A parry pause stops the attacker, even during bullet time")
	clock.advance(0.25)
	check(is_equal_approx(clock.scale(), ActionClock.DODGE_SLOW), "After the pause bullet time resumes")
	clock.advance(1.0)
	check(is_equal_approx(clock.scale(), 1.0) and clock.dodge_remaining == 0.0 and clock.pause_remaining == 0.0, "Timers stop at zero and speed returns to 1")
	clock.start_dodge_slow(1.0)
	clock.pause(1.0)
	clock.clear()
	check(is_equal_approx(clock.scale(), 1.0), "clear() ends bullet time and pauses")

	var boss := BossBase.new()
	boss._dodge_remaining = 0.7
	check(is_equal_approx(boss.action_clock.dodge_remaining, 0.7) and is_equal_approx(boss.get_action_time_scale(), 0.25), "BossBase._dodge_remaining still sets the boss's bullet time")
	boss._parry_pause = 0.2
	check(is_equal_approx(boss.action_clock.pause_remaining, 0.2) and is_zero_approx(boss.get_action_time_scale()), "BossBase._parry_pause still pauses the boss")
	boss.action_clock.clear()
	boss.red_parry_hold = true
	check(is_zero_approx(boss.get_action_time_scale()), "A red-parry hold stops the boss")
	boss.red_parry_hold = false
	boss._on_dodge_evaded(boss, 0.3)
	check(is_equal_approx(boss._dodge_remaining, 0.3), "Lan's dodge of the boss's own attack starts its bullet time")
	var other := Node2D.new()
	boss._on_dodge_evaded(other, 0.9)
	check(is_equal_approx(boss._dodge_remaining, 0.3), "A dodge of someone else's attack does not")
	other.free()
	boss.free()

	var master := MasterBoss.new()
	check(is_equal_approx(master.action_clock.dodge_slow, 0.25), "Master and other bosses share the perfect-dodge slowdown")
	master.free()
	finish("ACTION CLOCK")
