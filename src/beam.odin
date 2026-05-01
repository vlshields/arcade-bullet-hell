package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

Beam_Type :: enum {
	Laser,
	Charge,
}

Beam :: struct {
	type:      Beam_Type,
	start:     rl.Vector2,
	end:       rl.Vector2,
	lifetime:  f32,
	max_life:  f32,
	charging:  bool, // Charge only
	charge:    f32, // Charge only
	thickness: f32, // Charge only (laser uses LASER_THICKNESS)
	active:    bool,
}

Beam_Pool :: struct {
	beams: [MAX_BEAMS]Beam,
}

spawn_laser :: proc(pool: ^Beam_Pool, start, end: rl.Vector2) {
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				type     = .Laser,
				start    = start,
				end      = end,
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
	alpha := 1.0 - (b.lifetime / b.max_life)

	glow := rl.RED
	glow.a = u8(alpha * 40)
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * LASER_GLOW_MULT, glow)

	core := rl.WHITE
	core.a = u8(alpha * 255)
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS, core)

	inner := rl.Color{255, 200, 200, u8(alpha * 255)}
	rl.DrawLineEx(b.start, b.end, 1, inner)
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
