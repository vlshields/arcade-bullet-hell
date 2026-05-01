package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Enemy :: struct {
	anchor:     rl.Vector2,
	angle:      f32,
	radius:     f32,
	frame:      int,
	frame_time: f32,
	fire_timer: f32,
	hp:         int,
	hit_flash:  f32,
	active:     bool,
}

Enemy_Pool :: struct {
	enemies:      [ENEMY_COUNT]Enemy,
	tex:          rl.Texture2D,
	flash_shader: rl.Shader,
}

init_enemies :: proc(pool: ^Enemy_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_grunt_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.flash_shader = load_flash_shader()
	spawn_grunt_wave(pool)
}

spawn_grunt_wave :: proc(pool: ^Enemy_Pool) {
	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		e.anchor = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2}
		e.angle = f32(i) * math.TAU / f32(ENEMY_COUNT)
		e.radius = ENEMY_SPAWN_RADIUS
		e.fire_timer = rand.float32() * ENEMY_FIRE_INTERVAL
		e.frame = 0
		e.frame_time = 0
		e.hp = ENEMY_MAX_HP
		e.hit_flash = 0
		e.active = true
	}
}

damage_enemy :: proc(e: ^Enemy, amount: int) -> (killed: bool) {
	if !e.active {
		return false
	}
	e.hp -= amount
	e.hit_flash = ENEMY_HIT_FLASH_TIME
	if e.hp <= 0 {
		e.hp = 0
		e.active = false
		return true
	}
	return false
}

unload_enemies :: proc(pool: ^Enemy_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadShader(pool.flash_shader)
}

enemy_center :: proc(e: ^Enemy) -> rl.Vector2 {
	return {
		e.anchor.x + math.cos(e.angle) * e.radius,
		e.anchor.y + math.sin(e.angle) * e.radius,
	}
}

update_enemies :: proc(pool: ^Enemy_Pool, bullets: ^Bullet_Pool, dt: f32) {
	any_alive := false
	for i in 0 ..< ENEMY_COUNT {
		if pool.enemies[i].active {
			any_alive = true
			break
		}
	}
	if !any_alive {
		spawn_grunt_wave(pool)
	}

	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if !e.active {
			continue
		}
		if e.hit_flash > 0 {
			e.hit_flash -= dt
			if e.hit_flash < 0 {
				e.hit_flash = 0
			}
		}
		e.angle += ENEMY_ORBIT_SPEED * dt
		if e.angle >= math.TAU {
			e.angle -= math.TAU
		}

		if e.radius > ENEMY_ORBIT_RADIUS {
			e.radius -= ENEMY_APPROACH_SPEED * dt
			if e.radius < ENEMY_ORBIT_RADIUS {
				e.radius = ENEMY_ORBIT_RADIUS
			}
		}

		e.frame_time += dt
		frame_dur: f32 = 1.0 / ENEMY_ANIM_FPS
		if e.frame_time >= frame_dur {
			e.frame_time -= frame_dur
			e.frame = (e.frame + 1) % ENEMY_FRAMES
		}

		if e.radius > ENEMY_ORBIT_RADIUS {
			continue
		}

		e.fire_timer += dt
		if e.fire_timer >= ENEMY_FIRE_INTERVAL {
			e.fire_timer -= ENEMY_FIRE_INTERVAL
			center := enemy_center(e)
			for b in 0 ..< ENEMY_BULLETS_PER_BURST {
				angle := f32(b) * (math.TAU / f32(ENEMY_BULLETS_PER_BURST))
				vel := rl.Vector2 {
					math.cos(angle) * ENEMY_BULLET_SPEED,
					math.sin(angle) * ENEMY_BULLET_SPEED,
				}
				spawn_bullet(bullets, center, vel)
			}
		}
	}
}

draw_enemies :: proc(pool: ^Enemy_Pool) {
	draw_w := f32(ENEMY_FRAME_W * ENEMY_DRAW_SCALE)
	draw_h := f32(ENEMY_FRAME_H * ENEMY_DRAW_SCALE)

	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if !e.active {
			continue
		}
		center := enemy_center(e)
		src := rl.Rectangle {
			f32(e.frame * ENEMY_FRAME_W),
			0,
			f32(ENEMY_FRAME_W),
			f32(ENEMY_FRAME_H),
		}
		dst := rl.Rectangle{center.x - draw_w * 0.5, center.y - draw_h * 0.5, draw_w, draw_h}
		flashing := e.hit_flash > 0
		if flashing {
			rl.BeginShaderMode(pool.flash_shader)
		}
		rl.DrawTexturePro(pool.tex, src, dst, {0, 0}, 0, rl.WHITE)
		if flashing {
			rl.EndShaderMode()
		}
	}
}
