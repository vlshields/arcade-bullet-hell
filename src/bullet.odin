package game

import "core:math"
import rl "vendor:raylib"

// Bullets are pooled and tagged. Enemy bullets damage the player; Reflected
// bullets are former-enemy bullets the player turned by dashing through them
// and now home toward enemies; Rapid_Fire bullets are spawned by the player's
// Rapid Fire upgrade — they fly straight up at constant velocity and use the
// laser color palette.
Bullet_Kind :: enum {
	Enemy,
	Reflected,
	Rapid_Fire,
}

Bullet :: struct {
	pos:       rl.Vector2,
	vel:       rl.Vector2,
	life:      f32,
	color:     rl.Color,
	kind:      Bullet_Kind,
	active:    bool,
	// Shrink-bomb state. Only set on Enemy bullets caught in a bomb. Ramps 0->1
	// over SHRINK_BOMB_DURATION; while shrinking, hit radius and visuals scale by
	// (1 - shrink_t), and the bullet deactivates once shrink_t hits 1.
	shrinking: bool,
	shrink_t:  f32,
	// Morgan's energy-orb projectile: oversized .Enemy bullet that bursts into a
	// MORGAN_ORB_BURST_COUNT-bullet ring on EOL. Visual + collision radius differ
	// from the regular bullet path; collision hit-radius queried via bullet_hit_radius.
	is_burst_orb: bool,
}

Bullet_Pool :: struct {
	bullets: [MAX_BULLETS]Bullet,
}

spawn_bullet :: proc(
	pool: ^Bullet_Pool,
	pos, vel: rl.Vector2,
	color: rl.Color = rl.RED,
	kind: Bullet_Kind = .Enemy,
) {
	life: f32 = BULLET_LIFE
	if kind == .Rapid_Fire {
		life = RAPID_FIRE_LIFE
	}
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos    = pos,
				vel    = vel,
				life   = life,
				color  = color,
				kind   = kind,
				active = true,
			}
			return
		}
	}
}

spawn_energy_orb :: proc(pool: ^Bullet_Pool, pos, vel: rl.Vector2) {
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos          = pos,
				vel          = vel,
				life         = MORGAN_ORB_LIFE,
				color        = rl.Color{160, 80, 255, 255},
				kind         = .Enemy,
				active       = true,
				is_burst_orb = true,
			}
			return
		}
	}
}

bullet_hit_radius :: proc(b: ^Bullet) -> f32 {
	if b.is_burst_orb {
		return MORGAN_ORB_HIT_RADIUS
	}
	return BULLET_RADIUS
}

@(private = "file")
detonate_orb :: proc(pool: ^Bullet_Pool, pos: rl.Vector2) {
	step := math.TAU / f32(MORGAN_ORB_BURST_COUNT)
	color := rl.Color{200, 140, 255, 255}
	for i in 0 ..< MORGAN_ORB_BURST_COUNT {
		ang := f32(i) * step
		vel := rl.Vector2{math.cos(ang) * MORGAN_ORB_BURST_SPEED, math.sin(ang) * MORGAN_ORB_BURST_SPEED}
		spawn_bullet(pool, pos, vel, color)
	}
}

update_bullets :: proc(
	pool: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	dt: f32,
	world_dt: f32,
) {
	steer_k := f32(1) - math.exp(-REFLECT_HOMING_RATE * dt)
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
		}
		// Only Reflected bullets home; Rapid_Fire flies straight by design.
		if b.kind == .Reflected {
			best_target: rl.Vector2
			best_d_sq := f32(1e18)
			found := false
			for ei in 0 ..< ENEMY_COUNT {
				e := &enemies.enemies[ei]
				if !e.active {
					continue
				}
				ec := enemy_center(e)
				dx := ec.x - b.pos.x
				dy := ec.y - b.pos.y
				d_sq := dx * dx + dy * dy
				if d_sq < best_d_sq {
					best_d_sq = d_sq
					best_target = ec
					found = true
				}
			}
			for si in 0 ..< SNEAK_MAX {
				s := &sneaks.sneaks[si]
				if !s.active {
					continue
				}
				sc := sneak_center(s)
				dx := sc.x - b.pos.x
				dy := sc.y - b.pos.y
				d_sq := dx * dx + dy * dy
				if d_sq < best_d_sq {
					best_d_sq = d_sq
					best_target = sc
					found = true
				}
			}
			if boss.boss.active {
				bc := boss_center(&boss.boss)
				dx := bc.x - b.pos.x
				dy := bc.y - b.pos.y
				d_sq := dx * dx + dy * dy
				if d_sq < best_d_sq {
					best_d_sq = d_sq
					best_target = bc
					found = true
				}
			}
			if found {
				speed := rl.Vector2Length(b.vel)
				if speed > 0.001 {
					to_t := rl.Vector2Normalize(best_target - b.pos)
					target_vel := to_t * speed
					new_vel := b.vel * (1 - steer_k) + target_vel * steer_k
					nlen := rl.Vector2Length(new_vel)
					if nlen > 0.001 {
						b.vel = new_vel * (speed / nlen)
					}
				}
			}
		}
		// Player-side projectiles ignore slow-time so the player's offense stays
		// crisp regardless of the world tempo.
		use_dt := b.kind == .Enemy ? world_dt : dt
		b.pos += b.vel * use_dt
		b.life -= use_dt
		if b.life <= 0 {
			if b.is_burst_orb && b.kind == .Enemy && !b.shrinking {
				detonate_orb(pool, b.pos)
			}
			b.active = false
			continue
		}
		if b.shrinking {
			b.shrink_t += use_dt / SHRINK_BOMB_DURATION
			if b.shrink_t >= 1 {
				b.active = false
			}
		}
	}
}

// Flags every active enemy bullet for the shrink animation. They keep moving
// and drawing while shrinking, but their hit radius collapses to 0 immediately
// since collide_bullets_player skips any shrinking bullet.
shrink_all_enemy_bullets :: proc(pool: ^Bullet_Pool) {
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind != .Enemy || b.shrinking {
			continue
		}
		b.shrinking = true
		b.shrink_t = 0
	}
}

collide_bullets_player :: proc(pool: ^Bullet_Pool, player: ^Player, audio: ^Audio) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	reflected_any := false
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind != .Enemy || b.shrinking {
			continue
		}
		r := f32(PLAYER_HIT_RADIUS) + bullet_hit_radius(b)
		r_sq := r * r
		dx := b.pos.x - pcx
		dy := b.pos.y - pcy
		if dx * dx + dy * dy > r_sq {
			continue
		}
		if player.dash_timer > 0 {
			b.kind = .Reflected
			b.vel = -b.vel
			reflected_any = true
			continue
		}
		b.active = false
		damage_player(player, audio, PLAYER_HIT_DAMAGE)
		if player.invuln_timer > 0 {
			break
		}
	}
	if reflected_any {
		play_reflect_sfx(audio)
	}
}

collide_bullets_enemies :: proc(
	pool: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^int,
) {
	r_boss := boss_hit_radius(&boss.boss) + BULLET_RADIUS
	r_boss_sq := r_boss * r_boss
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind == .Enemy {
			continue
		}
		damage := REFLECT_DAMAGE
		impact_color := rl.Color{160, 220, 255, 255}
		score_val := SCORE_KILL_REFLECT
		if b.kind == .Rapid_Fire {
			damage = RAPID_FIRE_DAMAGE
			impact_color = rl.Color{255, 80, 80, 255}
			score_val = SCORE_KILL_RAPID
		}
		hit := false
		for ei in 0 ..< ENEMY_COUNT {
			e := &enemies.enemies[ei]
			if !e.active {
				continue
			}
			ec := enemy_center(e)
			r := enemy_hit_radius(e) + BULLET_RADIUS
			dx := b.pos.x - ec.x
			dy := b.pos.y - ec.y
			if dx * dx + dy * dy <= r * r {
				killed := damage_enemy(e, damage)
				spawn_impact_particles(particles, ec, impact_color, REFLECT_IMPACT_PARTICLES)
				b.active = false
				if killed {
					score^ += score_val
					try_spawn_sneak(sneaks)
					try_drop_healthpack(packs, ec)
				}
				hit = true
				break
			}
		}
		if hit {
			continue
		}
		for si in 0 ..< SNEAK_MAX {
			s := &sneaks.sneaks[si]
			if !s.active {
				continue
			}
			sc := sneak_center(s)
			r := sneak_hit_radius(s) + BULLET_RADIUS
			dx := b.pos.x - sc.x
			dy := b.pos.y - sc.y
			if dx * dx + dy * dy <= r * r {
				killed := damage_sneak(s, damage)
				spawn_impact_particles(particles, sc, impact_color, REFLECT_IMPACT_PARTICLES)
				b.active = false
				if killed {
					score^ += score_val
					try_spawn_sneak(sneaks)
					try_drop_healthpack(packs, sc)
				}
				hit = true
				break
			}
		}
		if hit {
			continue
		}
		if boss.boss.active {
			bc := boss_center(&boss.boss)
			dx := b.pos.x - bc.x
			dy := b.pos.y - bc.y
			if dx * dx + dy * dy <= r_boss_sq {
				killed := damage_boss(&boss.boss, damage)
				spawn_impact_particles(particles, bc, impact_color, REFLECT_IMPACT_PARTICLES)
				b.active = false
				if killed {
					score^ += SCORE_KILL_BOSS
					try_drop_healthpack(packs, bc)
				}
			}
		}
	}
}

draw_bullets :: proc(pool: ^Bullet_Pool) {
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
		}
		switch b.kind {
		case .Enemy:
			scale := f32(1)
			if b.shrinking {
				scale = 1 - b.shrink_t
				if scale < 0 {
					scale = 0
				}
			}
			if b.is_burst_orb {
				draw_energy_orb(b, scale)
			} else {
				rl.DrawCircleV(b.pos, BULLET_RADIUS * scale, b.color)
			}
		case .Reflected:
			rl.DrawCircleV(b.pos, BULLET_RADIUS, rl.Color{160, 220, 255, 255})
		case .Rapid_Fire:
			draw_rapid_fire_bullet(b)
		}
	}
}

@(private = "file")
draw_energy_orb :: proc(b: ^Bullet, scale: f32) {
	if scale <= 0 {
		return
	}
	core_r := MORGAN_ORB_DRAW_RADIUS * scale
	glow := rl.Color{160, 80, 255, 70}
	rl.DrawCircleV(b.pos, core_r * 2.4, glow)
	rl.DrawCircleV(b.pos, core_r * 1.5, rl.Color{200, 140, 255, 160})
	rl.DrawCircleV(b.pos, core_r, rl.Color{230, 200, 255, 255})
	rl.DrawCircleV(b.pos, core_r * 0.45, rl.WHITE)
}

@(private = "file")
draw_rapid_fire_bullet :: proc(b: ^Bullet) {
	// Mirrors the laser palette: wide red glow, light pink mid, white core.
	glow := rl.RED
	glow.a = 70
	rl.DrawCircleV(b.pos, RAPID_FIRE_RADIUS * RAPID_FIRE_GLOW_MULT, glow)
	rl.DrawCircleV(b.pos, RAPID_FIRE_RADIUS * 1.6, rl.Color{255, 200, 200, 220})
	rl.DrawCircleV(b.pos, RAPID_FIRE_RADIUS, rl.WHITE)
}
