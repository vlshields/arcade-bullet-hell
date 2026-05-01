package game

import rl "vendor:raylib"

Bullet :: struct {
	pos:    rl.Vector2,
	vel:    rl.Vector2,
	life:   f32,
	active: bool,
}

Bullet_Pool :: struct {
	bullets: [MAX_BULLETS]Bullet,
}

spawn_bullet :: proc(pool: ^Bullet_Pool, pos, vel: rl.Vector2) {
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos    = pos,
				vel    = vel,
				life   = BULLET_LIFE,
				active = true,
			}
			return
		}
	}
}

update_bullets :: proc(pool: ^Bullet_Pool, dt: f32) {
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
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
		if !b.active {
			continue
		}
		dx := b.pos.x - pcx
		dy := b.pos.y - pcy
		if dx * dx + dy * dy <= r_sq {
			b.active = false
			damage_player(player, PLAYER_HIT_DAMAGE)
			if player.invuln_timer > 0 {
				return
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
		rl.DrawCircleV(b.pos, BULLET_RADIUS, rl.RED)
	}
}
