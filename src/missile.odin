package game

import "core:math"
import rl "vendor:raylib"

// Homing missile spawned by the Dash Frenzy upgrade. Projectiles are not
// sprites — the body is a stack of additive purple circles and the trail is a
// ring buffer of past positions, also drawn as fading purple glow circles.

Missile :: struct {
	pos:           rl.Vector2,
	vel:           rl.Vector2,
	life:          f32,
	blind_time:    f32, // grace before homing kicks in so the launch fan is visible
	trail:         [MISSILE_TRAIL_LEN]rl.Vector2,
	trail_count:   int,
	trail_sample:  f32,
	active:        bool,
}

Missile_Pool :: struct {
	missiles: [MAX_MISSILES]Missile,
}

launch_dash_missiles :: proc(pool: ^Missile_Pool, origin: rl.Vector2, dash_dir: rl.Vector2) {
	dir := dash_dir
	if rl.Vector2Length(dir) < 0.001 {
		dir = {0, -1}
	}
	dir = rl.Vector2Normalize(dir)
	base_angle := math.atan2(dir.y, dir.x)

	fan_rad := f32(DASH_FRENZY_LAUNCH_FAN_DEG) * math.PI / 180.0
	half_fan := fan_rad * 0.5

	for i in 0 ..< DASH_FRENZY_MISSILES_PER_DASH {
		t: f32 = 0
		if DASH_FRENZY_MISSILES_PER_DASH > 1 {
			t = f32(i) / f32(DASH_FRENZY_MISSILES_PER_DASH - 1)
		}
		// Spread evenly across the fan, centered on the dash direction.
		angle := base_angle - half_fan + t * fan_rad
		vel := rl.Vector2{math.cos(angle) * MISSILE_SPEED, math.sin(angle) * MISSILE_SPEED}
		spawn_missile(pool, origin, vel)
	}
}

@(private = "file")
spawn_missile :: proc(pool: ^Missile_Pool, pos, vel: rl.Vector2) {
	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if m.active {
			continue
		}
		m^ = Missile {
			pos          = pos,
			vel          = vel,
			life         = MISSILE_LIFE,
			blind_time   = MISSILE_INITIAL_BLIND_TIME,
			trail_count  = 0,
			trail_sample = 0,
			active       = true,
		}
		return
	}
}

update_missiles :: proc(
	pool: ^Missile_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^int,
	dt: f32,
) {
	steer_k := f32(1) - math.exp(-MISSILE_TURN_RATE * dt)

	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if !m.active {
			continue
		}

		if m.blind_time > 0 {
			m.blind_time -= dt
			if m.blind_time < 0 {
				m.blind_time = 0
			}
		} else {
			target, found := nearest_target(m.pos, enemies, sneaks, boss)
			if found {
				speed := rl.Vector2Length(m.vel)
				if speed > 0.001 {
					to_t := rl.Vector2Normalize(target - m.pos)
					target_vel := to_t * speed
					new_vel := m.vel * (1 - steer_k) + target_vel * steer_k
					nlen := rl.Vector2Length(new_vel)
					if nlen > 0.001 {
						// Renormalize to keep the cruise speed constant.
						m.vel = new_vel * (speed / nlen)
					}
				}
			}
		}

		m.pos += m.vel * dt
		m.life -= dt

		// Sample trail at fixed cadence rather than every frame so the spacing
		// is independent of framerate and the trail looks consistent.
		m.trail_sample += dt
		for m.trail_sample >= MISSILE_TRAIL_SAMPLE_INTERVAL {
			m.trail_sample -= MISSILE_TRAIL_SAMPLE_INTERVAL
			push_trail_sample(m, m.pos)
		}

		// Despawn if off-screen by a comfortable margin or out of life.
		if m.life <= 0 ||
		   m.pos.x < -32 ||
		   m.pos.y < -32 ||
		   m.pos.x > f32(SCREEN_WIDTH) + 32 ||
		   m.pos.y > f32(SCREEN_HEIGHT) + 32 {
			m.active = false
			continue
		}

		// Collision: first hit detonates the missile.
		if try_hit_missile(m, enemies, sneaks, boss, packs, particles, score) {
			m.active = false
		}
	}
}

@(private = "file")
push_trail_sample :: proc(m: ^Missile, p: rl.Vector2) {
	if m.trail_count < MISSILE_TRAIL_LEN {
		m.trail_count += 1
	}
	for i := m.trail_count - 1; i > 0; i -= 1 {
		m.trail[i] = m.trail[i - 1]
	}
	m.trail[0] = p
}

@(private = "file")
nearest_target :: proc(
	from: rl.Vector2,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
) -> (
	target: rl.Vector2,
	found: bool,
) {
	best_d_sq := f32(1e18)
	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if !e.active {
			continue
		}
		ec := enemy_center(e)
		dx := ec.x - from.x
		dy := ec.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = ec
			found = true
		}
	}
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if !s.active {
			continue
		}
		sc := sneak_center(s)
		dx := sc.x - from.x
		dy := sc.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = sc
			found = true
		}
	}
	if boss.boss.active {
		bc := boss_center(&boss.boss)
		dx := bc.x - from.x
		dy := bc.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = bc
			found = true
		}
	}
	return
}

@(private = "file")
try_hit_missile :: proc(
	m: ^Missile,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^int,
) -> bool {
	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if !e.active {
			continue
		}
		ec := enemy_center(e)
		r := enemy_hit_radius(e) + MISSILE_HIT_RADIUS
		dx := m.pos.x - ec.x
		dy := m.pos.y - ec.y
		if dx * dx + dy * dy <= r * r {
			killed := damage_enemy(e, MISSILE_DAMAGE)
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				score^ += SCORE_KILL_REFLECT
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, ec)
			}
			return true
		}
	}
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if !s.active {
			continue
		}
		sc := sneak_center(s)
		r := sneak_hit_radius(s) + MISSILE_HIT_RADIUS
		dx := m.pos.x - sc.x
		dy := m.pos.y - sc.y
		if dx * dx + dy * dy <= r * r {
			killed := damage_sneak(s, MISSILE_DAMAGE)
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				score^ += SCORE_KILL_REFLECT
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, sc)
			}
			return true
		}
	}
	if boss.boss.active {
		bc := boss_center(&boss.boss)
		r := f32(BOSS_HIT_RADIUS) + MISSILE_HIT_RADIUS
		dx := m.pos.x - bc.x
		dy := m.pos.y - bc.y
		if dx * dx + dy * dy <= r * r {
			killed := damage_boss(&boss.boss, MISSILE_DAMAGE)
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				score^ += SCORE_KILL_BOSS
				try_drop_healthpack(packs, bc)
			}
			return true
		}
	}
	return false
}

draw_missiles :: proc(pool: ^Missile_Pool) {
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if !m.active {
			continue
		}
		draw_missile_trail(m)
		draw_missile_body(m)
	}
}

@(private = "file")
draw_missile_body :: proc(m: ^Missile) {
	// Layered concentric circles produce the soft purple glow. Outer layers are
	// dimmer and wider; the inner core is a hot near-white pixel.
	for layer in 0 ..< MISSILE_GLOW_LAYERS {
		t := f32(layer) / f32(MISSILE_GLOW_LAYERS - 1)
		radius := f32(MISSILE_BODY_RADIUS) * (1.0 + t * 3.5)
		// Outer glow: deep purple. Inner: hotter magenta-white.
		r := u8(180 + (1.0 - t) * 60)
		g := u8(60 + (1.0 - t) * 140)
		b := u8(220 + (1.0 - t) * 30)
		a := u8(40 + (1.0 - t) * 160)
		rl.DrawCircleV(m.pos, radius, rl.Color{r, g, b, a})
	}
	// Bright white-ish core for the lit-fuse impression.
	rl.DrawCircleV(m.pos, MISSILE_BODY_RADIUS * 0.6, rl.Color{255, 230, 255, 255})
}

@(private = "file")
draw_missile_trail :: proc(m: ^Missile) {
	if m.trail_count == 0 {
		return
	}
	// Iterate oldest-first so newer (more opaque) glow nodes overdraw older ones,
	// matching the dash trail convention elsewhere in the codebase.
	for k := m.trail_count - 1; k >= 0; k -= 1 {
		ratio := 1.0 - f32(k) / f32(MISSILE_TRAIL_LEN)
		if ratio <= 0 {
			continue
		}
		base_radius := f32(MISSILE_TRAIL_NODE_RADIUS) * ratio
		for layer in 0 ..< MISSILE_GLOW_LAYERS {
			lt := f32(layer) / f32(MISSILE_GLOW_LAYERS - 1)
			radius := base_radius * (1.0 + lt * 3.0)
			r := u8(160 + (1.0 - lt) * 60)
			g := u8(40 + (1.0 - lt) * 100)
			b := u8(200 + (1.0 - lt) * 40)
			alpha := f32(30 + (1.0 - lt) * 120) * ratio
			rl.DrawCircleV(m.trail[k], radius, rl.Color{r, g, b, u8(alpha)})
		}
	}
}
