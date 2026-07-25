class_name ParticleBurst
extends CPUParticles2D

## A one-shot spray of coloured squares, used for impacts.
##
## CPUParticles2D rather than GPUParticles2D deliberately: it is configurable
## entirely in code with no ParticleProcessMaterial, needs no art asset, and at
## this scale the GPU version buys nothing.
##
## Frees itself when finished — bursts spawn per hit, and without this they
## would accumulate for the whole session.

static func create(colour: Color, count: int) -> ParticleBurst:
	var burst := ParticleBurst.new()
	burst.amount = count
	burst.one_shot = true
	burst.lifetime = Juice.PARTICLE_LIFETIME
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.initial_velocity_min = Juice.PARTICLE_SPEED * 0.4
	burst.initial_velocity_max = Juice.PARTICLE_SPEED
	burst.gravity = Vector2(0.0, 320.0)
	burst.scale_amount_min = Juice.PARTICLE_SIZE * 0.6
	burst.scale_amount_max = Juice.PARTICLE_SIZE
	burst.color = colour
	burst.emitting = true
	burst.finished.connect(burst.queue_free)
	return burst

## Spawns a burst at `at` in `parent`'s coordinate space.
static func spawn(parent: Node, at: Vector2, colour: Color, count: int) -> ParticleBurst:
	var burst: ParticleBurst = create(colour, count)
	burst.position = at
	parent.add_child(burst)
	return burst
