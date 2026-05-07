package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Beam_Type :: enum {
	Laser,
	Charge,
}

// `.Laser` is a moving projectile-style bolt: `start` is the tail, `end` is the
// tip, both advance by `vel * dt` each frame. `damage` is per-target and the
// bolt deactivates on first hit. `.Charge` stays hitscan: `start`/`end` define
// a static fat beam, damage is applied once on release, and the visual fades
// out over `max_life`.
Beam :: struct {
	type:      Beam_Type,
	start:     rl.Vector2,
	end:       rl.Vector2,
	vel:       rl.Vector2, // .Laser only
	damage:    int, // .Laser only
	lifetime:  f32,
	max_life:  f32,
	charging:  bool, // .Charge only
	charge:    f32, // .Charge only
	thickness: f32, // .Charge only (laser uses LASER_THICKNESS)
	active:    bool,
}

Beam_Pool :: struct {
	beams: [MAX_BEAMS]Beam,
}

// Closest-point-on-segment distance vs radius. Used by laser-bolt collision so
// a single test handles vertical vanilla bolts and angled Beam Blast bolts.
beam_segment_hits :: proc(start, end, c: rl.Vector2, r: f32) -> bool {
	seg := end - start
	seg_len_sq := rl.Vector2DotProduct(seg, seg)
	if seg_len_sq < 0.001 {
		return rl.Vector2Distance(start, c) <= r
	}
	t := rl.Vector2DotProduct(c - start, seg) / seg_len_sq
	if t < 0 {
		t = 0
	}
	if t > 1 {
		t = 1
	}
	closest := rl.Vector2{start.x + seg.x * t, start.y + seg.y * t}
	return rl.Vector2Distance(closest, c) <= r
}

spawn_laser_bolt :: proc(pool: ^Beam_Pool, origin, dir: rl.Vector2, damage: int) {
	vel := dir * LASER_BOLT_SPEED
	end := origin
	start := origin - dir * LASER_BOLT_LENGTH
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				type     = .Laser,
				start    = start,
				end      = end,
				vel      = vel,
				damage   = damage,
				lifetime = 0,
				max_life = LASER_LIFETIME,
				active   = true,
			}
			return
		}
	}
}

start_charging_beam :: proc(pool: ^Beam_Pool, start, end: rl.Vector2) -> int {
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				type      = .Charge,
				start     = start,
				end       = end,
				lifetime  = 0,
				max_life  = 999, // won't expire while charging
				charging  = true,
				charge    = 0,
				thickness = 2,
				active    = true,
			}
			return i
		}
	}
	return -1
}

release_charge_beam :: proc(b: ^Beam) {
	b.charging = false
	b.lifetime = 0
	b.max_life = CHARGE_BEAM_LIFETIME_BASE + b.charge * CHARGE_BEAM_LIFETIME_BONUS
	b.thickness = CHARGE_BEAM_THICKNESS_BASE + b.charge * CHARGE_BEAM_THICKNESS_BONUS
}

cancel_charge_beam :: proc(b: ^Beam) {
	b.active = false
	b.charging = false
}

update_beams :: proc(pool: ^Beam_Pool, dt: f32) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		if b.charging {
			continue
		}
		b.lifetime += dt
		if b.lifetime >= b.max_life {
			b.active = false
			continue
		}
		if b.type == .Laser {
			b.start += b.vel * dt
			b.end += b.vel * dt
			// Off-screen safety: once both endpoints are clearly outside the
			// playfield in the same direction, drop the bolt early.
			margin: f32 = LASER_BOLT_LENGTH
			if (b.start.y < -margin && b.end.y < -margin) ||
			   (b.start.y > SCREEN_HEIGHT + margin && b.end.y > SCREEN_HEIGHT + margin) ||
			   (b.start.x < -margin && b.end.x < -margin) ||
			   (b.start.x > SCREEN_WIDTH + margin && b.end.x > SCREEN_WIDTH + margin) {
				b.active = false
			}
		}
	}
}

// Per-frame collision pass for moving laser bolts. A bolt deactivates on its
// first contact (no piercing). Charge beams are NOT processed here — they
// damage at release time inside fire_charge_beam.
collide_beams_enemies :: proc(
	pool: ^Beam_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^int,
) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active || b.type != .Laser {
			continue
		}
		hit := false
		for ei in 0 ..< ENEMY_COUNT {
			e := &enemies.enemies[ei]
			if !e.active {
				continue
			}
			ec := enemy_center(e)
			if !beam_segment_hits(b.start, b.end, ec, enemy_hit_radius(e)) {
				continue
			}
			killed := damage_enemy(e, b.damage)
			spawn_impact_particles(particles, ec, rl.RED, LASER_IMPACT_PARTICLES)
			if killed {
				score^ += SCORE_KILL_LASER
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, ec)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		for si in 0 ..< SNEAK_MAX {
			s := &sneaks.sneaks[si]
			if !s.active {
				continue
			}
			sc := sneak_center(s)
			if !beam_segment_hits(b.start, b.end, sc, sneak_hit_radius(s)) {
				continue
			}
			killed := damage_sneak(s, b.damage)
			spawn_impact_particles(particles, sc, rl.RED, LASER_IMPACT_PARTICLES)
			if killed {
				score^ += SCORE_KILL_LASER
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, sc)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		for pi in 0 ..< PILLAR_COUNT {
			p := &pillars.pillars[pi]
			if !p.active {
				continue
			}
			pc := pillar_center(p)
			if !beam_segment_hits(b.start, b.end, pc, pillar_hit_radius(p)) {
				continue
			}
			applied, killed := damage_pillar(pillars, pi, b.damage)
			if applied {
				spawn_impact_particles(particles, pc, rl.RED, LASER_IMPACT_PARTICLES)
				if killed {
					score^ += PILLAR_KILL_SCORE
				}
			} else {
				spawn_impact_particles(particles, pc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		if boss.boss.active {
			bc := boss_center(&boss.boss)
			if beam_segment_hits(b.start, b.end, bc, boss_hit_radius(&boss.boss)) {
				killed := damage_boss(&boss.boss, b.damage)
				spawn_impact_particles(particles, bc, rl.RED, LASER_IMPACT_PARTICLES)
				if killed {
					score^ += SCORE_KILL_BOSS
					try_drop_healthpack(packs, bc)
				}
				b.active = false
			}
		}
	}
}

draw_beams :: proc(pool: ^Beam_Pool) {
	t := f32(rl.GetTime())
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		switch b.type {
		case .Laser:
			draw_laser_beam(b)
		case .Charge:
			if b.charging {
				draw_charging_beam(b, t)
			} else {
				draw_charge_beam(b)
			}
		}
	}
}

draw_laser_beam :: proc(b: ^Beam) {
	// Bolt stays full-bright while alive; it usually exits via hit or off-screen
	// long before max_life. The tip carries a soft glow halo for projectile feel.
	glow := rl.RED
	glow.a = 60
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * LASER_GLOW_MULT, glow)

	mid := rl.Color{255, 120, 120, 220}
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * 2, mid)

	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS, rl.WHITE)

	tip_glow := rl.Color{255, 200, 200, 140}
	rl.DrawCircleV(b.end, LASER_THICKNESS * LASER_GLOW_MULT * 0.6, tip_glow)
}

draw_charging_beam :: proc(b: ^Beam, t: f32) {
	// Visuals fade in with charge so quick taps stay laser-only.
	pulse: f32 = 0.8 + math.sin(t * 15) * 0.2
	ring_radius: f32 = 10 + b.charge * 30

	for ring in 0 ..< 3 {
		ring_color := rl.MAGENTA
		ring_color.a = u8((1 - f32(ring) * 0.3) * 150 * pulse * b.charge)
		rl.DrawCircleLines(
			i32(b.start.x),
			i32(b.start.y),
			ring_radius + f32(ring) * 5,
			ring_color,
		)
	}

	target_color := rl.MAGENTA
	target_color.a = u8(b.charge * 150)
	rl.DrawLineEx(b.start, b.end, 1 + b.charge * 3, target_color)
}

draw_charge_beam :: proc(b: ^Beam) {
	alpha := 1.0 - (b.lifetime / b.max_life)
	thickness := b.thickness

	// Multi-layer glow
	for layer in 0 ..< 5 {
		layer_t := f32(layer) / 5.0
		glow := rl.MAGENTA
		glow.a = u8(alpha * (50 - layer_t * 40))
		rl.DrawLineEx(b.start, b.end, thickness * (2 - layer_t), glow)
	}

	// Electric fringes
	dir := b.end - b.start
	length := rl.Vector2Length(dir)
	if length > 0.001 {
		dir /= length
		perp := rl.Vector2{-dir.y, dir.x}
		for i in 0 ..< CHARGE_BEAM_FRINGE_COUNT {
			f_t := f32(i) / f32(CHARGE_BEAM_FRINGE_COUNT)
			base := b.start + dir * length * f_t
			if rand.int31() % 3 == 0 {
				offset := (rand.float32() - 0.5) * thickness * 3
				fringe_end := base + perp * offset
				fringe_color := rl.MAGENTA
				fringe_color.a = u8(alpha * 150)
				rl.DrawLineEx(base, fringe_end, 2, fringe_color)
			}
		}
	}

	// Bright core
	core := rl.WHITE
	core.a = u8(alpha * 255)
	rl.DrawLineEx(b.start, b.end, thickness * 0.3, core)
}
