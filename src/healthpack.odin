package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

HealthPack :: struct {
	pos:    rl.Vector2,
	phase:  f32,
	active: bool,
}

HealthPack_Pool :: struct {
	packs: [HEALTHPACK_MAX]HealthPack,
}

init_healthpacks :: proc(pool: ^HealthPack_Pool) {
	for i in 0 ..< HEALTHPACK_MAX {
		pool.packs[i].active = false
	}
}

try_drop_healthpack :: proc(pool: ^HealthPack_Pool, pos: rl.Vector2) {
	if rand.float32() >= HEALTHPACK_DROP_CHANCE {
		return
	}
	for i in 0 ..< HEALTHPACK_MAX {
		if !pool.packs[i].active {
			pool.packs[i] = HealthPack {
				pos    = pos,
				phase  = rand.float32() * math.TAU,
				active = true,
			}
			return
		}
	}
}

update_healthpacks :: proc(pool: ^HealthPack_Pool, player: ^Player, dt: f32) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	r := f32(PLAYER_HIT_RADIUS) + HEALTHPACK_RADIUS
	r_sq := r * r
	for i in 0 ..< HEALTHPACK_MAX {
		h := &pool.packs[i]
		if !h.active {
			continue
		}
		dx := h.pos.x - pcx
		dy := h.pos.y - pcy
		if dx * dx + dy * dy <= r_sq {
			h.active = false
			player.hp += HEALTHPACK_HEAL
			if player.hp > PLAYER_MAX_HP {
				player.hp = PLAYER_MAX_HP
			}
		}
	}
}

draw_healthpacks :: proc(pool: ^HealthPack_Pool) {
	t := f32(rl.GetTime())
	for i in 0 ..< HEALTHPACK_MAX {
		h := &pool.packs[i]
		if !h.active {
			continue
		}
		pulse: f32 = 0.85 + math.sin(t * HEALTHPACK_PULSE_HZ * math.TAU + h.phase) * 0.15
		arm: f32 = HEALTHPACK_ARM * pulse
		thick: f32 = HEALTHPACK_THICK

		// Soft green glow for visibility against busy backgrounds.
		glow := rl.Color{120, 255, 140, 80}
		rl.DrawCircleV(h.pos, arm * 1.6, glow)

		// White backing cross for outline.
		back_arm: f32 = arm + 1
		back_thick: f32 = thick + 2
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - back_arm, h.pos.y - back_thick * 0.5, back_arm * 2, back_thick},
			rl.WHITE,
		)
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - back_thick * 0.5, h.pos.y - back_arm, back_thick, back_arm * 2},
			rl.WHITE,
		)

		// Inner green cross.
		green := rl.Color{60, 220, 90, 255}
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - arm, h.pos.y - thick * 0.5, arm * 2, thick},
			green,
		)
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - thick * 0.5, h.pos.y - arm, thick, arm * 2},
			green,
		)
	}
}
