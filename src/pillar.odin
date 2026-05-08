package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// Final wave of level 4. Four pillars spawn one per screen corner with a
// random 1..4 number assignment. Numbers are visible for PILLAR_REVEAL_DUR
// seconds, then PILLAR_SHUFFLE_COUNT shuffles smoothly reposition the pillars.
// During Combat only the pillar whose number matches next_kill takes damage;
// out-of-order shots are absorbed without harm. Each pillar fires a continuous
// spiral; spin direction is bound to the corner so diagonally opposite
// pillars always rotate in opposite directions.
//
// Per-corner spin assignment:
//   0 (TL): +1     1 (TR): -1
//   3 (BL): +1     2 (BR): -1
// Diagonals: TL/BR opposite, TR/BL opposite. spin_dir is rebound when a
// shuffle settles so the rule survives reshuffling.

Pillar_Phase :: enum {
	Idle,
	Reveal,
	Shuffle,
	Combat,
}

Pillar :: struct {
	number:     int,
	pos:        rl.Vector2,
	from_pos:   rl.Vector2,
	to_pos:     rl.Vector2,
	hp:         int,
	hit_flash:  f32,
	fire_timer: f32,
	base_angle: f32,
	spin_dir:   f32,
	frame:      int,
	frame_time: f32,
	active:     bool,
}

Pillar_Wave :: struct {
	pillars:       [PILLAR_COUNT]Pillar,
	tex:           rl.Texture2D,
	flash_shader:  rl.Shader,
	phase:         Pillar_Phase,
	phase_t:       f32,
	shuffles_done: int,
	next_kill:     int,
}

init_pillars :: proc(wave: ^Pillar_Wave) {
	wave.tex = rl.LoadTexture("assets/sprites/enemy_pillar.png")
	rl.SetTextureFilter(wave.tex, .POINT)
	wave.flash_shader = load_flash_shader()
	wave.phase = .Idle
}

unload_pillars :: proc(wave: ^Pillar_Wave) {
	rl.UnloadTexture(wave.tex)
	rl.UnloadShader(wave.flash_shader)
}

clear_pillars :: proc(wave: ^Pillar_Wave) {
	for i in 0 ..< PILLAR_COUNT {
		wave.pillars[i].active = false
	}
	wave.phase = .Idle
	wave.phase_t = 0
	wave.shuffles_done = 0
	wave.next_kill = 0
}

spawn_pillar_wave :: proc(wave: ^Pillar_Wave) {
	nums: [PILLAR_COUNT]int = {1, 2, 3, 4}
	for i := PILLAR_COUNT - 1; i > 0; i -= 1 {
		j := int(rand.uint32() % u32(i + 1))
		nums[i], nums[j] = nums[j], nums[i]
	}
	for i in 0 ..< PILLAR_COUNT {
		c := corner_pos(i)
		wave.pillars[i] = Pillar {
			number     = nums[i],
			pos        = c,
			from_pos   = c,
			to_pos     = c,
			hp         = PILLAR_HP,
			spin_dir   = corner_spin(i),
			base_angle = rand.float32() * math.TAU,
			active     = true,
		}
	}
	wave.phase = .Reveal
	wave.phase_t = 0
	wave.shuffles_done = 0
	wave.next_kill = 1
}

update_pillars :: proc(wave: ^Pillar_Wave, bullets: ^Bullet_Pool, dt: f32) {
	if wave.phase == .Idle {
		return
	}

	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		if p.hit_flash > 0 {
			p.hit_flash -= dt
			if p.hit_flash < 0 {
				p.hit_flash = 0
			}
		}
		p.frame_time += dt
		frame_dur: f32 = 1.0 / PILLAR_ANIM_FPS
		if p.frame_time >= frame_dur {
			p.frame_time -= frame_dur
			p.frame = (p.frame + 1) % PILLAR_FRAMES
		}
	}

	wave.phase_t += dt

	switch wave.phase {
	case .Idle:
	// unreachable
	case .Reveal:
		if wave.phase_t >= PILLAR_REVEAL_DUR {
			start_shuffle(wave)
		}
	case .Shuffle:
		progress: f32 = wave.phase_t / PILLAR_SHUFFLE_DUR
		if progress > 1 {
			progress = 1
		}
		eased := smoothstep(progress)
		for i in 0 ..< PILLAR_COUNT {
			p := &wave.pillars[i]
			if !p.active {
				continue
			}
			p.pos.x = p.from_pos.x + (p.to_pos.x - p.from_pos.x) * eased
			p.pos.y = p.from_pos.y + (p.to_pos.y - p.from_pos.y) * eased
		}
		if wave.phase_t >= PILLAR_SHUFFLE_DUR {
			for i in 0 ..< PILLAR_COUNT {
				p := &wave.pillars[i]
				if !p.active {
					continue
				}
				p.pos = p.to_pos
				// Rebind spin_dir to the corner the pillar settled into so the
				// "opposite corners spin opposite" invariant holds post-shuffle.
				p.spin_dir = corner_spin(corner_index_for(p.pos))
			}
			wave.shuffles_done += 1
			if wave.shuffles_done >= PILLAR_SHUFFLE_COUNT {
				wave.phase = .Combat
				wave.phase_t = 0
			} else {
				start_shuffle(wave)
			}
		}
	case .Combat:
		update_pillar_combat(wave, bullets, dt)
	}
}

@(private = "file")
start_shuffle :: proc(wave: ^Pillar_Wave) {
	perm: [PILLAR_COUNT]int = {0, 1, 2, 3}
	// Reshuffle until the permutation moves at least one pillar — pure identity
	// would defeat the visual-tracking rule. 8 attempts is overkill (1/24 per
	// try) but keeps the loop bounded.
	for attempt in 0 ..< 8 {
		_ = attempt
		for i := PILLAR_COUNT - 1; i > 0; i -= 1 {
			j := int(rand.uint32() % u32(i + 1))
			perm[i], perm[j] = perm[j], perm[i]
		}
		identity := true
		for i in 0 ..< PILLAR_COUNT {
			if perm[i] != i {
				identity = false
				break
			}
		}
		if !identity {
			break
		}
	}
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		p.from_pos = p.pos
		p.to_pos = corner_pos(perm[i])
	}
	wave.phase = .Shuffle
	wave.phase_t = 0
}

@(private = "file")
update_pillar_combat :: proc(wave: ^Pillar_Wave, bullets: ^Bullet_Pool, dt: f32) {
	color := rl.Color{255, 220, 100, 255}
	inc_rad: f32 = PILLAR_ANGLE_INC_DEG * math.PI / 180.0
	row_step: f32 = math.TAU / f32(PILLAR_BULLETS_PER_BURST)
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		p.fire_timer += dt
		for p.fire_timer >= PILLAR_FIRE_INTERVAL {
			p.fire_timer -= PILLAR_FIRE_INTERVAL
			for r in 0 ..< PILLAR_BULLETS_PER_BURST {
				ang := p.base_angle + f32(r) * row_step
				vel := rl.Vector2 {
					math.cos(ang) * PILLAR_BULLET_SPEED,
					math.sin(ang) * PILLAR_BULLET_SPEED,
				}
				spawn_bullet(bullets, p.pos, vel, color, .Enemy, .Pillar, i)
			}
			p.base_angle += inc_rad * p.spin_dir
			if p.base_angle >= math.TAU {
				p.base_angle -= math.TAU
			}
			if p.base_angle < 0 {
				p.base_angle += math.TAU
			}
		}
	}
}

// applied = damage actually landed; killed = pillar reached 0 hp this call.
// Out-of-order shots and shots taken outside Combat absorb the projectile
// (callers always treat the projectile as consumed) but apply no damage.
damage_pillar :: proc(wave: ^Pillar_Wave, idx: int, amount: int) -> (applied: bool, killed: bool) {
	if idx < 0 || idx >= PILLAR_COUNT {
		return false, false
	}
	p := &wave.pillars[idx]
	if !p.active {
		return false, false
	}
	if wave.phase != .Combat {
		return false, false
	}
	if p.number != wave.next_kill {
		return false, false
	}
	p.hp -= amount
	p.hit_flash = PILLAR_HIT_FLASH_TIME
	if p.hp <= 0 {
		p.hp = 0
		p.active = false
		wave.next_kill += 1
		return true, true
	}
	return true, false
}

pillar_center :: proc(p: ^Pillar) -> rl.Vector2 {
	return p.pos
}

pillar_hit_radius :: proc(p: ^Pillar) -> f32 {
	return PILLAR_HIT_RADIUS
}

pillar_wave_complete :: proc(wave: ^Pillar_Wave) -> bool {
	if wave.phase != .Combat {
		return false
	}
	for i in 0 ..< PILLAR_COUNT {
		if wave.pillars[i].active {
			return false
		}
	}
	return true
}

@(private = "file")
corner_pos :: proc(idx: int) -> rl.Vector2 {
	switch idx {
	case 0:
		return {PILLAR_CORNER_MARGIN, PILLAR_CORNER_MARGIN}
	case 1:
		return {SCREEN_WIDTH - PILLAR_CORNER_MARGIN, PILLAR_CORNER_MARGIN}
	case 2:
		return {SCREEN_WIDTH - PILLAR_CORNER_MARGIN, SCREEN_HEIGHT - PILLAR_CORNER_MARGIN}
	case 3:
		return {PILLAR_CORNER_MARGIN, SCREEN_HEIGHT - PILLAR_CORNER_MARGIN}
	}
	return {0, 0}
}

@(private = "file")
corner_spin :: proc(idx: int) -> f32 {
	switch idx {
	case 0, 3:
		return 1
	case 1, 2:
		return -1
	}
	return 1
}

@(private = "file")
corner_index_for :: proc(p: rl.Vector2) -> int {
	best := 0
	best_dsq: f32 = 1e9
	for i in 0 ..< PILLAR_COUNT {
		c := corner_pos(i)
		dx := p.x - c.x
		dy := p.y - c.y
		d := dx * dx + dy * dy
		if d < best_dsq {
			best_dsq = d
			best = i
		}
	}
	return best
}

draw_pillars :: proc(wave: ^Pillar_Wave) {
	if wave.phase == .Idle {
		return
	}
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		draw_w := f32(PILLAR_FRAME_W * PILLAR_DRAW_SCALE)
		draw_h := f32(PILLAR_FRAME_H * PILLAR_DRAW_SCALE)
		src := rl.Rectangle{f32(p.frame * PILLAR_FRAME_W), 0, f32(PILLAR_FRAME_W), f32(PILLAR_FRAME_H)}
		dst := rl.Rectangle{p.pos.x - draw_w * 0.5, p.pos.y - draw_h * 0.5, draw_w, draw_h}
		flashing := p.hit_flash > 0
		if flashing {
			rl.BeginShaderMode(wave.flash_shader)
		}
		rl.DrawTexturePro(wave.tex, src, dst, {0, 0}, 0, rl.WHITE)
		if flashing {
			rl.EndShaderMode()
		}
	}

	if wave.phase == .Reveal {
		for i in 0 ..< PILLAR_COUNT {
			p := &wave.pillars[i]
			if !p.active {
				continue
			}
			num := fmt.ctprintf("%d", p.number)
			tw := rl.MeasureText(num, PILLAR_NUMBER_FONT_SIZE)
			tx := i32(p.pos.x) - tw / 2
			ty := i32(p.pos.y) - i32(PILLAR_FRAME_H * PILLAR_DRAW_SCALE) / 2 - PILLAR_NUMBER_FONT_SIZE - 4
			rl.DrawText(num, tx + 1, ty + 1, PILLAR_NUMBER_FONT_SIZE, rl.BLACK)
			rl.DrawText(num, tx, ty, PILLAR_NUMBER_FONT_SIZE, rl.YELLOW)
		}
	}
}
