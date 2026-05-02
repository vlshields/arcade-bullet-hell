package game

import "core:math"
import rl "vendor:raylib"

Boss :: struct {
	pos:               rl.Vector2,
	sway_phase:        f32,
	base_angle:        f32,
	fire_timer:        f32,
	sneak_spawn_timer: f32,
	frame:             int,
	frame_time:        f32,
	hp:                int,
	hit_flash:         f32,
	active:            bool,
	defeated:          bool,
}

Boss_Pool :: struct {
	boss:         Boss,
	tex:          rl.Texture2D,
	flash_shader: rl.Shader,
}

init_boss :: proc(pool: ^Boss_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_boss1_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.boss.active = false
}

unload_boss :: proc(pool: ^Boss_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadShader(pool.flash_shader)
}

spawn_boss :: proc(pool: ^Boss_Pool) {
	pool.boss = Boss {
		pos               = {BOSS_SPAWN_X, BOSS_SPAWN_Y},
		sway_phase        = 0,
		base_angle        = 0,
		fire_timer        = 0,
		sneak_spawn_timer = BOSS_SNEAK_SPAWN_INTERVAL,
		frame             = 0,
		frame_time        = 0,
		hp                = BOSS_MAX_HP,
		hit_flash         = 0,
		active            = true,
	}
}

boss_center :: proc(b: ^Boss) -> rl.Vector2 {
	return b.pos
}

damage_boss :: proc(b: ^Boss, amount: int) -> (killed: bool) {
	if !b.active {
		return false
	}
	b.hp -= amount
	b.hit_flash = BOSS_HIT_FLASH_TIME
	if b.hp <= 0 {
		b.hp = 0
		b.active = false
		b.defeated = true
		return true
	}
	return false
}

update_boss :: proc(pool: ^Boss_Pool, bullets: ^Bullet_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	b := &pool.boss
	if !b.active {
		return
	}

	if b.hit_flash > 0 {
		b.hit_flash -= dt
		if b.hit_flash < 0 {
			b.hit_flash = 0
		}
	}

	b.sway_phase += BOSS_SWAY_FREQ * math.TAU * dt
	if b.sway_phase >= math.TAU {
		b.sway_phase -= math.TAU
	}
	b.pos.x = BOSS_SPAWN_X + math.sin(b.sway_phase) * BOSS_SWAY_AMPLITUDE
	b.pos.y = BOSS_SPAWN_Y

	b.frame_time += dt
	frame_dur: f32 = 1.0 / BOSS_ANIM_FPS
	if b.frame_time >= frame_dur {
		b.frame_time -= frame_dur
		b.frame = (b.frame + 1) % BOSS_FRAMES
	}

	// Continuous spiral: every BOSS_FIRE_INTERVAL, emit BOSS_BULLET_ROWS evenly
	// spaced bullets around base_angle, then rotate base_angle by the increment.
	// Mirrors ~/bhport defaults: 6 rows, 5° per burst, ~2 frame cadence.
	b.fire_timer += dt
	row_step: f32 = math.TAU / f32(BOSS_BULLET_ROWS)
	inc_rad: f32 = f32(BOSS_ANGLE_INCREMENT_DEG) * math.PI / 180.0
	color := rl.Color{0xff, 0xcc, 0xcc, 0xff}
	for b.fire_timer >= BOSS_FIRE_INTERVAL {
		b.fire_timer -= BOSS_FIRE_INTERVAL
		for r in 0 ..< BOSS_BULLET_ROWS {
			ang := b.base_angle + f32(r) * row_step
			vel := rl.Vector2 {
				math.cos(ang) * BOSS_BULLET_SPEED,
				math.sin(ang) * BOSS_BULLET_SPEED,
			}
			spawn_bullet(bullets, b.pos, vel, color)
		}
		b.base_angle += inc_rad
		if b.base_angle >= math.TAU {
			b.base_angle -= math.TAU
		}
	}

	b.sneak_spawn_timer -= dt
	if b.sneak_spawn_timer <= 0 {
		b.sneak_spawn_timer = BOSS_SNEAK_SPAWN_INTERVAL
		try_spawn_sneak(sneaks)
	}
}

draw_boss_hud :: proc(pool: ^Boss_Pool) {
	b := &pool.boss
	if !b.active {
		return
	}

	bar_x: i32 = (SCREEN_WIDTH - BOSS_HUD_BAR_W) / 2
	bar_y: i32 = BOSS_HUD_BAR_Y

	// Outer frame (drop shadow + border) for boss-fight emphasis.
	rl.DrawRectangle(bar_x - 2, bar_y - 2, BOSS_HUD_BAR_W + 4, BOSS_HUD_BAR_H + 4, rl.BLACK)
	rl.DrawRectangle(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.Color{40, 10, 10, 255})

	hp := b.hp
	if hp < 0 {
		hp = 0
	}
	fill_w := i32(f32(BOSS_HUD_BAR_W) * f32(hp) / f32(BOSS_MAX_HP))
	if fill_w > 0 {
		rl.DrawRectangle(bar_x, bar_y, fill_w, BOSS_HUD_BAR_H, rl.Color{220, 40, 60, 255})
		// Highlight band for a chunkier boss-bar feel.
		rl.DrawRectangle(bar_x, bar_y, fill_w, 2, rl.Color{255, 120, 130, 255})
	}
	rl.DrawRectangleLines(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.WHITE)

	name: cstring = BOSS_NAME
	text_w := rl.MeasureText(name, BOSS_NAME_FONT_SIZE)
	name_x := (i32(SCREEN_WIDTH) - text_w) / 2
	rl.DrawText(name, name_x + 1, BOSS_HUD_NAME_Y + 1, BOSS_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, name_x, BOSS_HUD_NAME_Y, BOSS_NAME_FONT_SIZE, rl.WHITE)
}

draw_boss :: proc(pool: ^Boss_Pool) {
	b := &pool.boss
	if !b.active {
		return
	}
	draw_w := f32(BOSS_FRAME_W * BOSS_DRAW_SCALE)
	draw_h := f32(BOSS_FRAME_H * BOSS_DRAW_SCALE)
	src := rl.Rectangle {
		f32(b.frame * BOSS_FRAME_W),
		0,
		f32(BOSS_FRAME_W),
		f32(BOSS_FRAME_H),
	}
	dst := rl.Rectangle{b.pos.x - draw_w * 0.5, b.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := b.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}
