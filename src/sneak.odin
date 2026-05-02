package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Sneak :: struct {
	anchor:         rl.Vector2,
	sway_phase:     f32,
	pos:            rl.Vector2,
	fire_timer:     f32,
	teleport_timer: f32,
	hp:             int,
	hit_flash:      f32,
	active:         bool,
}

Sneak_Pool :: struct {
	sneaks:       [SNEAK_MAX]Sneak,
	tex:          rl.Texture2D,
	flash_shader: rl.Shader,
}

init_sneaks :: proc(pool: ^Sneak_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_sneak_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.flash_shader = load_flash_shader()
	for i in 0 ..< SNEAK_MAX {
		pool.sneaks[i].active = false
	}
}

unload_sneaks :: proc(pool: ^Sneak_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadShader(pool.flash_shader)
}

damage_sneak :: proc(s: ^Sneak, amount: int) -> (killed: bool) {
	if !s.active {
		return false
	}
	s.hp -= amount
	s.hit_flash = SNEAK_HIT_FLASH_TIME
	if s.hp <= 0 {
		s.hp = 0
		s.active = false
		return true
	}
	return false
}

sneak_center :: proc(s: ^Sneak) -> rl.Vector2 {
	return s.pos
}

random_viewport_point :: proc() -> rl.Vector2 {
	margin := f32(SNEAK_SPAWN_MARGIN)
	x := margin + rand.float32() * (f32(SCREEN_WIDTH) - 2 * margin)
	y := margin + rand.float32() * (f32(SCREEN_HEIGHT) - 2 * margin)
	return {x, y}
}

// Roll the 50/50 spawn dice and, on success and below the cap, spawn a sneak
// at a random viewport position. Called whenever any enemy dies.
try_spawn_sneak :: proc(pool: ^Sneak_Pool) {
	if rand.float32() >= SNEAK_SPAWN_CHANCE {
		return
	}
	slot := -1
	for i in 0 ..< SNEAK_MAX {
		if !pool.sneaks[i].active {
			slot = i
			break
		}
	}
	if slot < 0 {
		return
	}
	anchor := random_viewport_point()
	pool.sneaks[slot] = Sneak {
		anchor         = anchor,
		sway_phase     = rand.float32() * math.TAU,
		pos            = anchor,
		fire_timer     = rand.float32() * SNEAK_BURST_INTERVAL,
		teleport_timer = SNEAK_TELEPORT_INTERVAL,
		hp             = SNEAK_MAX_HP,
		hit_flash      = 0,
		active         = true,
	}
}

update_sneaks :: proc(pool: ^Sneak_Pool, player: ^Player, bullets: ^Bullet_Pool, dt: f32) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	player_center := rl.Vector2{pcx, pcy}

	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if !s.active {
			continue
		}

		if s.hit_flash > 0 {
			s.hit_flash -= dt
			if s.hit_flash < 0 {
				s.hit_flash = 0
			}
		}

		s.sway_phase += SNEAK_SWAY_FREQ * math.TAU * dt
		if s.sway_phase >= math.TAU {
			s.sway_phase -= math.TAU
		}
		s.pos.x = s.anchor.x + math.sin(s.sway_phase) * SNEAK_SWAY_AMPLITUDE
		s.pos.y = s.anchor.y

		s.teleport_timer -= dt
		if s.teleport_timer <= 0 {
			s.teleport_timer = SNEAK_TELEPORT_INTERVAL
			s.anchor = random_viewport_point()
			s.sway_phase = rand.float32() * math.TAU
			s.pos = s.anchor
		}

		s.fire_timer += dt
		if s.fire_timer >= SNEAK_BURST_INTERVAL {
			s.fire_timer -= SNEAK_BURST_INTERVAL
			to_player := player_center - s.pos
			if rl.Vector2Length(to_player) < 0.001 {
				to_player = {0, 1}
			}
			base_angle := math.atan2(to_player.y, to_player.x)
			fan_rad := f32(SNEAK_BURST_FAN_DEG) * math.PI / 180.0
			n := f32(SNEAK_BULLETS_PER_BURST)
			color := rl.Color{0x99, 0x33, 0x66, 0xff}
			for b in 0 ..< SNEAK_BULLETS_PER_BURST {
				t := f32(b) / (n - 1) - 0.5
				angle := base_angle + t * fan_rad
				vel := rl.Vector2 {
					math.cos(angle) * SNEAK_BULLET_SPEED,
					math.sin(angle) * SNEAK_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color)
			}
		}
	}
}

draw_sneaks :: proc(pool: ^Sneak_Pool) {
	draw_w := f32(SNEAK_FRAME_W * SNEAK_DRAW_SCALE)
	draw_h := f32(SNEAK_FRAME_H * SNEAK_DRAW_SCALE)
	src := rl.Rectangle{0, 0, f32(SNEAK_FRAME_W), f32(SNEAK_FRAME_H)}

	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if !s.active {
			continue
		}
		dst := rl.Rectangle{s.pos.x - draw_w * 0.5, s.pos.y - draw_h * 0.5, draw_w, draw_h}
		flashing := s.hit_flash > 0
		if flashing {
			rl.BeginShaderMode(pool.flash_shader)
		}
		rl.DrawTexturePro(pool.tex, src, dst, {0, 0}, 0, rl.WHITE)
		if flashing {
			rl.EndShaderMode()
		}
	}
}
