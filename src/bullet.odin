package game

import "core:math"
import rl "vendor:raylib"

Bullet :: struct {
	pos:         rl.Vector2,
	vel:         rl.Vector2,
	life:        f32,
	color:       rl.Color,
	active:      bool,
	from_player: bool,
}

Bullet_Pool :: struct {
	bullets: [MAX_BULLETS]Bullet,
}

spawn_bullet :: proc(
	pool: ^Bullet_Pool,
	pos, vel: rl.Vector2,
	color: rl.Color = rl.RED,
	from_player := false,
) {
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos         = pos,
				vel         = vel,
				life        = BULLET_LIFE,
				color       = color,
				active      = true,
				from_player = from_player,
			}
			return
		}
	}
}

update_bullets :: proc(
	pool: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	dt: f32,
) {
	steer_k := f32(1) - math.exp(-REFLECT_HOMING_RATE * dt)
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
		}
		if b.from_player {
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
		b.pos += b.vel * dt
		b.life -= dt
		if b.life <= 0 {
			b.active = false
		}
	}
}

collide_bullets_player :: proc(pool: ^Bullet_Pool, player: ^Player) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	r := f32(PLAYER_HIT_RADIUS + BULLET_RADIUS)
	r_sq := r * r
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.from_player {
			continue
		}
		dx := b.pos.x - pcx
		dy := b.pos.y - pcy
		if dx * dx + dy * dy > r_sq {
			continue
		}
		if player.dash_timer > 0 {
			b.from_player = true
			b.vel = -b.vel
			continue
		}
		b.active = false
		damage_player(player, PLAYER_HIT_DAMAGE)
		if player.invuln_timer > 0 {
			return
		}
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
	r_grunt := f32(ENEMY_HIT_RADIUS + BULLET_RADIUS)
	r_grunt_sq := r_grunt * r_grunt
	r_sneak := f32(SNEAK_HIT_RADIUS + BULLET_RADIUS)
	r_sneak_sq := r_sneak * r_sneak
	r_boss := f32(BOSS_HIT_RADIUS + BULLET_RADIUS)
	r_boss_sq := r_boss * r_boss
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || !b.from_player {
			continue
		}
		hit := false
		for ei in 0 ..< ENEMY_COUNT {
			e := &enemies.enemies[ei]
			if !e.active {
				continue
			}
			ec := enemy_center(e)
			dx := b.pos.x - ec.x
			dy := b.pos.y - ec.y
			if dx * dx + dy * dy <= r_grunt_sq {
				killed := damage_enemy(e, REFLECT_DAMAGE)
				spawn_impact_particles(
					particles,
					ec,
					rl.Color{160, 220, 255, 255},
					REFLECT_IMPACT_PARTICLES,
				)
				b.active = false
				if killed {
					score^ += SCORE_KILL_REFLECT
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
			dx := b.pos.x - sc.x
			dy := b.pos.y - sc.y
			if dx * dx + dy * dy <= r_sneak_sq {
				killed := damage_sneak(s, REFLECT_DAMAGE)
				spawn_impact_particles(
					particles,
					sc,
					rl.Color{160, 220, 255, 255},
					REFLECT_IMPACT_PARTICLES,
				)
				b.active = false
				if killed {
					score^ += SCORE_KILL_REFLECT
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
				killed := damage_boss(&boss.boss, REFLECT_DAMAGE)
				spawn_impact_particles(
					particles,
					bc,
					rl.Color{160, 220, 255, 255},
					REFLECT_IMPACT_PARTICLES,
				)
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
		col := b.color
		if b.from_player {
			col = rl.Color{160, 220, 255, 255}
		}
		rl.DrawCircleV(b.pos, BULLET_RADIUS, col)
	}
}
