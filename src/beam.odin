package game

import rl "vendor:raylib"

Beam :: struct {
	start:    rl.Vector2,
	end:      rl.Vector2,
	lifetime: f32,
	active:   bool,
}

Beam_Pool :: struct {
	beams: [MAX_BEAMS]Beam,
}

spawn_laser :: proc(pool: ^Beam_Pool, start, end: rl.Vector2) {
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				start    = start,
				end      = end,
				lifetime = 0,
				active   = true,
			}
			return
		}
	}
}

update_beams :: proc(pool: ^Beam_Pool, dt: f32) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		b.lifetime += dt
		if b.lifetime >= LASER_LIFETIME {
			b.active = false
		}
	}
}

draw_beams :: proc(pool: ^Beam_Pool) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		alpha := 1.0 - (b.lifetime / LASER_LIFETIME)

		glow := rl.RED
		glow.a = u8(alpha * 40)
		rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * LASER_GLOW_MULT, glow)

		core := rl.WHITE
		core.a = u8(alpha * 255)
		rl.DrawLineEx(b.start, b.end, LASER_THICKNESS, core)

		inner := rl.Color{255, 200, 200, u8(alpha * 255)}
		rl.DrawLineEx(b.start, b.end, 1, inner)
	}
}
