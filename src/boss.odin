package game

import "core:math"
import rl "vendor:raylib"

Boss_Kind :: enum {
	Golgatha,
	Morgan,
}

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
	kind:              Boss_Kind,
	// Morgan-only state. phase counts up 1..3; on phase advance hp resets to
	// MORGAN_PHASE_HP. shield_hp is non-zero only in phase 3; while > 0 it
	// absorbs damage instead of hp. shield_recover_timer counts down from
	// MORGAN_SHIELD_RECOVER_TIME after a break, and the shield refills when it
	// reaches zero. orb_timer is the cadence for the burst-on-EOL energy orbs.
	phase:                int,
	shield_hp:            int,
	shield_recover_timer: f32,
	orb_timer:            f32,
	// Counts down from MORGAN_PHASE_TRANSITION_DUR while the boss is between
	// phases. > 0 means the world is frozen and the HP bar is refilling 0 ->
	// MORGAN_PHASE_HP. Defeat does NOT trigger a transition.
	phase_transition_t: f32,
}

// True while Morgan is between phases. Main loop uses this to freeze the
// player + bullets so the only thing ticking is the boss itself, which is
// running the transition timer + HP refill.
boss_phase_pausing :: proc(b: ^Boss) -> bool {
	return b.kind == .Morgan && b.phase_transition_t > 0
}

Boss_Pool :: struct {
	boss:            Boss,
	tex:             rl.Texture2D,
	morgan_idle_tex: rl.Texture2D,
	flash_shader:    rl.Shader,
}

init_boss :: proc(pool: ^Boss_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_boss1_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.morgan_idle_tex = rl.LoadTexture("assets/sprites/boss_morgan_idle.png")
	rl.SetTextureFilter(pool.morgan_idle_tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.boss.active = false
}

unload_boss :: proc(pool: ^Boss_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadTexture(pool.morgan_idle_tex)
	rl.UnloadShader(pool.flash_shader)
}

boss_hit_radius :: proc(b: ^Boss) -> f32 {
	if b.kind == .Morgan {
		return MORGAN_HIT_RADIUS
	}
	return BOSS_HIT_RADIUS
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
		kind              = .Golgatha,
	}
}

spawn_morgan :: proc(pool: ^Boss_Pool) {
	pool.boss = Boss {
		pos        = {MORGAN_SPAWN_X, MORGAN_SPAWN_Y},
		hp         = MORGAN_PHASE_HP,
		active     = true,
		kind       = .Morgan,
		phase      = 1,
		orb_timer  = MORGAN_ORB_INTERVAL,
	}
}

boss_center :: proc(b: ^Boss) -> rl.Vector2 {
	return b.pos
}

damage_boss :: proc(b: ^Boss, amount: int) -> (killed: bool) {
	if !b.active {
		return false
	}
	b.hit_flash = BOSS_HIT_FLASH_TIME
	if b.kind == .Morgan {
		// Phase-3 shield soaks all damage until it breaks; remaining damage does
		// NOT carry over to hp (gives the shield a real defensive role).
		if b.phase == 3 && b.shield_hp > 0 {
			b.shield_hp -= amount
			if b.shield_hp <= 0 {
				b.shield_hp = 0
				b.shield_recover_timer = MORGAN_SHIELD_RECOVER_TIME
			}
			return false
		}
		b.hp -= amount
		if b.hp <= 0 {
			b.hp = 0
			if b.phase >= 3 {
				b.active = false
				b.defeated = true
				return true
			}
			// Enter the inter-phase pause. The HP bar is left at 0 and the
			// transition timer drives both the refill animation and the
			// gameplay freeze (see boss_phase_pausing). Phase index increments
			// now so phase-specific spawns (shield, sneaks, etc.) line up.
			b.phase += 1
			b.fire_timer = 0
			b.base_angle = 0
			b.orb_timer = MORGAN_ORB_INTERVAL
			b.sneak_spawn_timer = MORGAN_P2_SNEAK_INTERVAL
			b.phase_transition_t = MORGAN_PHASE_TRANSITION_DUR
			if b.phase == 3 {
				b.shield_hp = MORGAN_SHIELD_HP
				b.shield_recover_timer = 0
			}
		}
		return false
	}
	b.hp -= amount
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

	if b.kind == .Morgan {
		update_morgan(b, bullets, sneaks, dt)
		return
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

	rl.DrawRectangle(bar_x - 2, bar_y - 2, BOSS_HUD_BAR_W + 4, BOSS_HUD_BAR_H + 4, rl.BLACK)
	rl.DrawRectangle(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.Color{40, 10, 10, 255})

	hp := b.hp
	if hp < 0 {
		hp = 0
	}
	max_hp := BOSS_MAX_HP
	if b.kind == .Morgan {
		max_hp = MORGAN_PHASE_HP
	}
	fill_w := i32(f32(BOSS_HUD_BAR_W) * f32(hp) / f32(max_hp))
	if fill_w > 0 {
		rl.DrawRectangle(bar_x, bar_y, fill_w, BOSS_HUD_BAR_H, rl.Color{220, 40, 60, 255})
		rl.DrawRectangle(bar_x, bar_y, fill_w, 2, rl.Color{255, 120, 130, 255})
	}
	rl.DrawRectangleLines(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.WHITE)

	name: cstring = BOSS_NAME
	if b.kind == .Morgan {
		name = MORGAN_NAME
	}
	text_w := rl.MeasureText(name, BOSS_NAME_FONT_SIZE)
	name_x := (i32(SCREEN_WIDTH) - text_w) / 2
	rl.DrawText(name, name_x + 1, BOSS_HUD_NAME_Y + 1, BOSS_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, name_x, BOSS_HUD_NAME_Y, BOSS_NAME_FONT_SIZE, rl.WHITE)

	// Phase-3 shield bar sits right below the HP bar, narrower so it reads as a
	// distinct sub-stat. Stays drawn (empty) while recovering so the player can
	// anticipate the comeback. The phase count itself is not displayed — players
	// learn there are more phases by watching the HP bar refill.
	if b.kind == .Morgan && b.phase == 3 {
		sh_w: i32 = BOSS_HUD_BAR_W * 2 / 3
		sh_h: i32 = 4
		sh_x := (SCREEN_WIDTH - sh_w) / 2
		sh_y := bar_y + BOSS_HUD_BAR_H + 3
		rl.DrawRectangle(sh_x - 1, sh_y - 1, sh_w + 2, sh_h + 2, rl.BLACK)
		rl.DrawRectangle(sh_x, sh_y, sh_w, sh_h, rl.Color{20, 30, 50, 255})
		shield_fill := i32(f32(sh_w) * f32(b.shield_hp) / f32(MORGAN_SHIELD_HP))
		if shield_fill > 0 {
			rl.DrawRectangle(sh_x, sh_y, shield_fill, sh_h, rl.Color{120, 200, 255, 255})
		}
		rl.DrawRectangleLines(sh_x, sh_y, sh_w, sh_h, rl.Color{200, 230, 255, 255})
	}
}

draw_boss :: proc(pool: ^Boss_Pool) {
	b := &pool.boss
	if !b.active {
		return
	}

	tex := pool.tex
	frame_w := i32(BOSS_FRAME_W)
	frame_h := i32(BOSS_FRAME_H)
	scale: f32 = BOSS_DRAW_SCALE
	if b.kind == .Morgan {
		tex = pool.morgan_idle_tex
		frame_w = MORGAN_FRAME_W
		frame_h = MORGAN_FRAME_H
		scale = MORGAN_DRAW_SCALE
	}
	draw_w := f32(frame_w) * scale
	draw_h := f32(frame_h) * scale
	src := rl.Rectangle{f32(i32(b.frame) * frame_w), 0, f32(frame_w), f32(frame_h)}
	dst := rl.Rectangle{b.pos.x - draw_w * 0.5, b.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := b.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}

	// Phase-3 shield: pulsing ring around Morgan while shield_hp > 0. Drawn after
	// the body so it sits on top.
	if b.kind == .Morgan && b.phase == 3 && b.shield_hp > 0 {
		pulse := 0.5 + 0.5 * math.sin(f32(rl.GetTime()) * 4.0)
		ring_r := MORGAN_HIT_RADIUS + 4 + pulse * 2
		alpha := u8(120 + pulse * 80)
		rl.DrawCircleLinesV(b.pos, ring_r, rl.Color{120, 200, 255, alpha})
		rl.DrawCircleLinesV(b.pos, ring_r - 1, rl.Color{200, 230, 255, alpha / 2})
	}
}

@(private = "file")
update_morgan :: proc(b: ^Boss, bullets: ^Bullet_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	// Inter-phase pause: only refill the HP bar; skip movement, spiral, orbs,
	// sneak summons, animation. The world is frozen by the main loop.
	if b.phase_transition_t > 0 {
		b.phase_transition_t -= dt
		if b.phase_transition_t <= 0 {
			b.phase_transition_t = 0
			b.hp = MORGAN_PHASE_HP
		} else {
			progress := 1 - b.phase_transition_t / MORGAN_PHASE_TRANSITION_DUR
			b.hp = int(f32(MORGAN_PHASE_HP) * progress)
		}
		return
	}

	sway_amp, sway_freq, fire_int, angle_inc_deg, bullet_speed: f32
	rows: int
	switch b.phase {
	case 1:
		sway_amp, sway_freq = MORGAN_P1_SWAY_AMP, MORGAN_P1_SWAY_FREQ
		fire_int, rows = MORGAN_P1_FIRE_INTERVAL, MORGAN_P1_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P1_ANGLE_INC_DEG, MORGAN_P1_BULLET_SPEED
	case 2:
		sway_amp, sway_freq = MORGAN_P2_SWAY_AMP, MORGAN_P2_SWAY_FREQ
		fire_int, rows = MORGAN_P2_FIRE_INTERVAL, MORGAN_P2_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P2_ANGLE_INC_DEG, MORGAN_P2_BULLET_SPEED
	case:
		sway_amp, sway_freq = MORGAN_P3_SWAY_AMP, MORGAN_P3_SWAY_FREQ
		fire_int, rows = MORGAN_P3_FIRE_INTERVAL, MORGAN_P3_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P3_ANGLE_INC_DEG, MORGAN_P3_BULLET_SPEED
	}

	b.sway_phase += sway_freq * math.TAU * dt
	if b.sway_phase >= math.TAU {
		b.sway_phase -= math.TAU
	}
	b.pos.x = MORGAN_SPAWN_X + math.sin(b.sway_phase) * sway_amp
	b.pos.y = MORGAN_SPAWN_Y

	b.frame_time += dt
	frame_dur: f32 = 1.0 / MORGAN_ANIM_FPS
	if b.frame_time >= frame_dur {
		b.frame_time -= frame_dur
		b.frame = (b.frame + 1) % MORGAN_IDLE_FRAMES
	}

	color := rl.Color{200, 140, 255, 255}
	row_step: f32 = math.TAU / f32(rows)
	inc_rad: f32 = angle_inc_deg * math.PI / 180.0
	b.fire_timer += dt
	for b.fire_timer >= fire_int {
		b.fire_timer -= fire_int
		for r in 0 ..< rows {
			ang := b.base_angle + f32(r) * row_step
			vel := rl.Vector2{math.cos(ang) * bullet_speed, math.sin(ang) * bullet_speed}
			spawn_bullet(bullets, b.pos, vel, color)
		}
		b.base_angle += inc_rad
		if b.base_angle >= math.TAU {
			b.base_angle -= math.TAU
		}
	}

	// Energy orbs: aimed straight down with a small lateral wobble.
	b.orb_timer -= dt
	if b.orb_timer <= 0 {
		b.orb_timer = MORGAN_ORB_INTERVAL
		wobble := math.sin(b.sway_phase) * 0.3
		ang: f32 = math.PI / 2 + wobble
		vel := rl.Vector2{math.cos(ang) * MORGAN_ORB_SPEED, math.sin(ang) * MORGAN_ORB_SPEED}
		spawn_energy_orb(bullets, b.pos, vel)
	}

	if b.phase == 2 {
		b.sneak_spawn_timer -= dt
		if b.sneak_spawn_timer <= 0 {
			b.sneak_spawn_timer = MORGAN_P2_SNEAK_INTERVAL
			force_spawn_sneak(sneaks)
		}
	}

	if b.phase == 3 && b.shield_hp <= 0 && b.shield_recover_timer > 0 {
		b.shield_recover_timer -= dt
		if b.shield_recover_timer <= 0 {
			b.shield_recover_timer = 0
			b.shield_hp = MORGAN_SHIELD_HP
		}
	}
}
