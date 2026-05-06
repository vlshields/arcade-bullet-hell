package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Minor_Enemy_Kind :: enum {
	Sneak,
	Cyclops,
}

Sneak_Data :: struct {
	anchor:         rl.Vector2,
	sway_phase:     f32,
	teleport_timer: f32,
}

Cyclops_Data :: struct {
	cross_t:      f32,
	cross_dir:    f32,
	pattern:      int,
	spiral_angle: f32,
	frame:        int,
	frame_time:   f32,
}

Sneak :: struct {
	kind:       Minor_Enemy_Kind,
	pos:        rl.Vector2,
	hp:         int,
	hit_flash:  f32,
	fire_timer: f32,
	active:     bool,
	data:       union {
		Sneak_Data,
		Cyclops_Data,
	},
}

Sneak_Pool :: struct {
	sneaks:       [SNEAK_MAX]Sneak,
	tex:          rl.Texture2D,
	cyclops_tex:  rl.Texture2D,
	flash_shader: rl.Shader,
	level:        int,
	// Mirror of Enemy_Pool.level2_phase, kept in sync so try_spawn_sneak can
	// gate kill-driven minor spawns without needing a back-reference to Enemy_Pool.
	level2_phase: Level2_Phase,
}

init_sneaks :: proc(pool: ^Sneak_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_sneak_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.cyclops_tex = rl.LoadTexture("assets/sprites/enemy_cyclops_move.png")
	rl.SetTextureFilter(pool.cyclops_tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.level = 1
	for i in 0 ..< SNEAK_MAX {
		pool.sneaks[i].active = false
	}
}

unload_sneaks :: proc(pool: ^Sneak_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadTexture(pool.cyclops_tex)
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

sneak_hit_radius :: proc(s: ^Sneak) -> f32 {
	if s.kind == .Cyclops {
		return CYCLOPS_HIT_RADIUS
	}
	return SNEAK_HIT_RADIUS
}

random_viewport_point :: proc() -> rl.Vector2 {
	margin := f32(SNEAK_SPAWN_MARGIN)
	x := margin + rand.float32() * (f32(SCREEN_WIDTH) - 2 * margin)
	y := margin + rand.float32() * (f32(SCREEN_HEIGHT) - 2 * margin)
	return {x, y}
}

// Effective active-minor-enemy cap for the current level. Level 1 keeps the
// historical cap of 2 even though the underlying pool can hold more, so that
// bumping SNEAK_MAX for the level-2 scripted phases doesn't accidentally
// inflate level-1 difficulty.
effective_sneak_cap :: proc(pool: ^Sneak_Pool) -> int {
	if pool.level <= 1 {
		return LEVEL1_SNEAK_CAP
	}
	return SNEAK_MAX
}

// Kill-driven minor-enemy spawn funnel. Behavior depends on the current pacing
// phase (see Level2_Phase). Level 1 retains the historical 50% sneak / 50% no-op
// roll. Scripted level-2 phases do nothing here — they spawn from level2.odin
// directly.
try_spawn_sneak :: proc(pool: ^Sneak_Pool) {
	if pool.level < 2 {
		// Level 1: 50% sneak, 50% nothing (cyclops never spawn on level 1).
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		}
		return
	}
	switch pool.level2_phase {
	case .Wave1_WG_Only,
	     .Between_1Cyclops,
	     .Between_1Cyc_2Sneaks,
	     .Between_4Sneaks:
		// Scripted-only phases: kills must not bleed extra spawns in.
		return
	case .Wave2_WG_Sneaks:
		// "Weird guys and sneaks" — only sneaks here, no cyclops.
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		}
	case .Between_3Cyc_Sneaks:
		// Cyclops are spawned by the pacing manager; kills here may mint sneaks.
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		}
	case .Free_For_All:
		// Original level-2 mix.
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		} else {
			force_spawn_cyclops(pool)
		}
	}
}

force_spawn_sneak :: proc(pool: ^Sneak_Pool) {
	cap := effective_sneak_cap(pool)
	slot := -1
	for i in 0 ..< cap {
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
		kind = .Sneak,
		pos = anchor,
		hp = SNEAK_MAX_HP,
		hit_flash = 0,
		fire_timer = rand.float32() * SNEAK_BURST_INTERVAL,
		active = true,
		data = Sneak_Data {
			anchor = anchor,
			sway_phase = rand.float32() * math.TAU,
			teleport_timer = SNEAK_TELEPORT_INTERVAL,
		},
	}
}

// Forced cyclops spawn. Bypasses the level guard (caller is responsible for
// gating) but keeps the "only one cyclops alive at a time" rule because two
// cyclops is too much screen real estate for the existing bullet patterns.
force_spawn_cyclops :: proc(pool: ^Sneak_Pool) {
	cap := effective_sneak_cap(pool)
	slot := -1
	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if s.active && s.kind == .Cyclops {
			return
		}
		if !s.active && slot < 0 && i < cap {
			slot = i
		}
	}
	if slot < 0 {
		return
	}
	dir: f32 = rand.float32() < 0.5 ? 1.0 : -1.0
	y := CYCLOPS_Y_MIN + rand.float32() * (CYCLOPS_Y_MAX - CYCLOPS_Y_MIN)
	margin := f32(CYCLOPS_OFFSCREEN_MARGIN)
	start_x: f32 = dir > 0 ? -margin : f32(SCREEN_WIDTH) + margin
	pool.sneaks[slot] = Sneak {
		kind = .Cyclops,
		pos = {start_x, y},
		hp = CYCLOPS_MAX_HP,
		hit_flash = 0,
		fire_timer = 0,
		active = true,
		data = Cyclops_Data {
			cross_t = 0,
			cross_dir = dir,
			pattern = int(rand.uint32() % CYCLOPS_PATTERN_COUNT),
			spiral_angle = rand.float32() * math.TAU,
			frame = 0,
			frame_time = 0,
		},
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

		switch s.kind {
		case .Sneak:
			update_sneak_one(s, player_center, bullets, dt)
		case .Cyclops:
			update_cyclops_one(s, player_center, bullets, dt)
		}
	}
}

@(private = "file")
update_sneak_one :: proc(s: ^Sneak, player_center: rl.Vector2, bullets: ^Bullet_Pool, dt: f32) {
	d := &s.data.(Sneak_Data)

	d.sway_phase += SNEAK_SWAY_FREQ * math.TAU * dt
	if d.sway_phase >= math.TAU {
		d.sway_phase -= math.TAU
	}
	s.pos.x = d.anchor.x + math.sin(d.sway_phase) * SNEAK_SWAY_AMPLITUDE
	s.pos.y = d.anchor.y

	d.teleport_timer -= dt
	if d.teleport_timer <= 0 {
		d.teleport_timer = SNEAK_TELEPORT_INTERVAL
		d.anchor = random_viewport_point()
		d.sway_phase = rand.float32() * math.TAU
		s.pos = d.anchor
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

@(private = "file")
update_cyclops_one :: proc(
	s: ^Sneak,
	player_center: rl.Vector2,
	bullets: ^Bullet_Pool,
	dt: f32,
) {
	d := &s.data.(Cyclops_Data)

	// Animation cycles through all 9 frames of the cyclops sheet.
	d.frame_time += dt
	frame_dur: f32 = 1.0 / CYCLOPS_ANIM_FPS
	if d.frame_time >= frame_dur {
		d.frame_time -= frame_dur
		d.frame = (d.frame + 1) % CYCLOPS_FRAMES
	}

	// Side-to-side pass: cross_t goes 0->1 over CYCLOPS_CROSS_DURATION, then
	// flips direction, picks a new altitude, and rerolls the bullet pattern.
	d.cross_t += dt / CYCLOPS_CROSS_DURATION
	if d.cross_t >= 1.0 {
		d.cross_t = 0
		d.cross_dir = -d.cross_dir
		s.pos.y = CYCLOPS_Y_MIN + rand.float32() * (CYCLOPS_Y_MAX - CYCLOPS_Y_MIN)
		d.pattern = int(rand.uint32() % CYCLOPS_PATTERN_COUNT)
		d.spiral_angle = rand.float32() * math.TAU
		s.fire_timer = 0
	}

	margin := f32(CYCLOPS_OFFSCREEN_MARGIN)
	start_x, end_x: f32
	if d.cross_dir > 0 {
		start_x = -margin
		end_x = f32(SCREEN_WIDTH) + margin
	} else {
		start_x = f32(SCREEN_WIDTH) + margin
		end_x = -margin
	}
	s.pos.x = start_x + (end_x - start_x) * d.cross_t

	color := rl.Color{0xff, 0xcc, 0x99, 0xff}
	s.fire_timer += dt

	switch d.pattern {
	case 0:
		// Aimed fan at the player.
		for s.fire_timer >= CYCLOPS_AIMED_INTERVAL {
			s.fire_timer -= CYCLOPS_AIMED_INTERVAL
			to_player := player_center - s.pos
			if rl.Vector2Length(to_player) < 0.001 {
				to_player = {0, 1}
			}
			base_angle := math.atan2(to_player.y, to_player.x)
			fan_rad := f32(CYCLOPS_AIMED_FAN_DEG) * math.PI / 180.0
			n := f32(CYCLOPS_AIMED_BULLETS)
			for b in 0 ..< CYCLOPS_AIMED_BULLETS {
				t := f32(b) / (n - 1) - 0.5
				angle := base_angle + t * fan_rad
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color)
			}
		}
	case 1:
		// Full ring — player must dodge into a gap.
		for s.fire_timer >= CYCLOPS_RING_INTERVAL {
			s.fire_timer -= CYCLOPS_RING_INTERVAL
			step := math.TAU / f32(CYCLOPS_RING_BULLETS)
			for b in 0 ..< CYCLOPS_RING_BULLETS {
				angle := f32(b) * step
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color)
			}
		}
	case 2:
		// Rotating opposing arms — continuous spiral hose.
		arm_step := math.TAU / f32(CYCLOPS_SPIRAL_ARMS)
		inc_rad := f32(CYCLOPS_SPIRAL_INC_DEG) * math.PI / 180.0
		for s.fire_timer >= CYCLOPS_SPIRAL_INTERVAL {
			s.fire_timer -= CYCLOPS_SPIRAL_INTERVAL
			for arm in 0 ..< CYCLOPS_SPIRAL_ARMS {
				angle := d.spiral_angle + f32(arm) * arm_step
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color)
			}
			d.spiral_angle += inc_rad
			if d.spiral_angle >= math.TAU {
				d.spiral_angle -= math.TAU
			}
		}
	}
}

draw_sneaks :: proc(pool: ^Sneak_Pool) {
	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if !s.active {
			continue
		}
		switch s.kind {
		case .Sneak:
			draw_sneak_one(pool, s)
		case .Cyclops:
			draw_cyclops_one(pool, s)
		}
	}
}

@(private = "file")
draw_sneak_one :: proc(pool: ^Sneak_Pool, s: ^Sneak) {
	draw_w := f32(SNEAK_FRAME_W * SNEAK_DRAW_SCALE)
	draw_h := f32(SNEAK_FRAME_H * SNEAK_DRAW_SCALE)
	src := rl.Rectangle{0, 0, f32(SNEAK_FRAME_W), f32(SNEAK_FRAME_H)}
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

@(private = "file")
draw_cyclops_one :: proc(pool: ^Sneak_Pool, s: ^Sneak) {
	d := &s.data.(Cyclops_Data)
	draw_w := f32(CYCLOPS_FRAME_W * CYCLOPS_DRAW_SCALE)
	draw_h := f32(CYCLOPS_FRAME_H * CYCLOPS_DRAW_SCALE)
	src := rl.Rectangle {
		f32(d.frame * CYCLOPS_FRAME_W),
		0,
		f32(CYCLOPS_FRAME_W),
		f32(CYCLOPS_FRAME_H),
	}
	dst := rl.Rectangle{s.pos.x - draw_w * 0.5, s.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := s.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.cyclops_tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}
