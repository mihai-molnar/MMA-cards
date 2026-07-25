extends RefCounted

const TestRunner := preload("res://tests/run_tests.gd")

func run(t: TestRunner) -> void:
	_test_burst_configuration(t)
	_test_burst_frees_itself(t)

func _test_burst_configuration(t: TestRunner) -> void:
	var burst: ParticleBurst = ParticleBurst.create(Color(1, 0.4, 0.4), Juice.PARTICLES_HIT)
	t.check(burst.one_shot, "a burst is one shot, so it cannot loop forever")
	t.check(burst.emitting, "a burst starts emitting immediately")
	t.check_eq(burst.amount, Juice.PARTICLES_HIT, "a burst emits the configured particle count")
	t.check_eq(burst.lifetime, Juice.PARTICLE_LIFETIME, "a burst uses the configured lifetime")
	t.check(burst.color == Color(1, 0.4, 0.4), "a burst takes the requested colour")
	burst.free()

func _test_burst_frees_itself(t: TestRunner) -> void:
	# Bursts spawn per hit. If they did not free themselves they would
	# accumulate for the whole session.
	var burst: ParticleBurst = ParticleBurst.create(Color.WHITE, 8)
	t.check(burst.finished.is_connected(burst.queue_free),
		"a burst queues itself free when it finishes emitting")
	burst.free()
