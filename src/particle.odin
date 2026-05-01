package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Particle :: struct {
	pos:      rl.Vector2,
	vel:      rl.Vector2,
	lifetime: f32,
	max_life: f32,
	color:    rl.Color,
	size:     f32,
	active:   bool,
}

Particle_Pool :: struct {
	particles: [MAX_PARTICLES]Particle,
}

spawn_impact_particles :: proc(pool: ^Particle_Pool, pos: rl.Vector2, color: rl.Color, count: int) {
	spawned := 0
	for i in 0 ..< MAX_PARTICLES {
		if spawned >= count {
			return
		}
		p := &pool.particles[i]
		if p.active {
			continue
		}
		angle := rand.float32() * math.TAU
		speed_range: f32 = PARTICLE_SPEED_MAX - PARTICLE_SPEED_MIN
		speed := f32(PARTICLE_SPEED_MIN) + rand.float32() * speed_range
		life_range: f32 = PARTICLE_LIFE_MAX - PARTICLE_LIFE_MIN
		size_range: f32 = PARTICLE_SIZE_MAX - PARTICLE_SIZE_MIN
		tinted := color
		tinted.a = 200
		p^ = Particle {
			pos      = pos,
			vel      = {math.cos(angle) * speed, math.sin(angle) * speed - 50},
			lifetime = 0,
			max_life = f32(PARTICLE_LIFE_MIN) + rand.float32() * life_range,
			color    = tinted,
			size     = f32(PARTICLE_SIZE_MIN) + rand.float32() * size_range,
			active   = true,
		}
		spawned += 1
	}
}

update_particles :: proc(pool: ^Particle_Pool, dt: f32) {
	for i in 0 ..< MAX_PARTICLES {
		p := &pool.particles[i]
		if !p.active {
			continue
		}
		p.pos += p.vel * dt
		p.vel.y += PARTICLE_GRAVITY * dt
		p.lifetime += dt
		if p.lifetime >= p.max_life {
			p.active = false
		}
	}
}

draw_particles :: proc(pool: ^Particle_Pool) {
	for i in 0 ..< MAX_PARTICLES {
		p := &pool.particles[i]
		if !p.active {
			continue
		}
		alpha := 1.0 - (p.lifetime / p.max_life)
		color := p.color
		color.a = u8(f32(p.color.a) * alpha)
		rl.DrawCircleV(p.pos, p.size * alpha, color)
	}
}
