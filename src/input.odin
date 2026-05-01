package game

import rl "vendor:raylib"

input_move :: proc() -> rl.Vector2 {
	move := rl.Vector2{0, 0}

	if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) {
		move.y -= 1
	}
	if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) {
		move.y += 1
	}
	if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) {
		move.x -= 1
	}
	if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) {
		move.x += 1
	}

	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_UP) {
			move.y -= 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_DOWN) {
			move.y += 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_LEFT) {
			move.x -= 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_RIGHT) {
			move.x += 1
		}

		ax := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X)
		ay := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_Y)
		if abs(ax) > STICK_DEADZONE {
			move.x += ax
		}
		if abs(ay) > STICK_DEADZONE {
			move.y += ay
		}
	}

	mag_sq := move.x * move.x + move.y * move.y
	if mag_sq > 1 {
		inv := 1.0 / f32(rl.Vector2Length(move))
		move.x *= inv
		move.y *= inv
	}

	return move
}

input_attack :: proc() -> bool {
	if rl.IsMouseButtonDown(.LEFT) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .RIGHT_TRIGGER_2) {
			return true
		}
	}
	return false
}

// Returns whether dash was triggered this frame and the normalized direction.
// Keyboard (SPACE): direction is from player toward mouse cursor.
// Gamepad (B / RIGHT_FACE_RIGHT): direction is the left stick axis (dpad as fallback).
// `dir` is zero-length when the player gave no aim — caller should skip dashing then.
input_dash :: proc(player_center, mouse_game_pos: rl.Vector2) -> (pressed: bool, dir: rl.Vector2) {
	gpad_pressed := false
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT) {
			gpad_pressed = true
		}
	}
	kb_pressed := rl.IsKeyPressed(.SPACE)
	if !gpad_pressed && !kb_pressed {
		return false, {0, 0}
	}

	if gpad_pressed {
		ax := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X)
		ay := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_Y)
		d := rl.Vector2{0, 0}
		if abs(ax) > STICK_DEADZONE {
			d.x = ax
		}
		if abs(ay) > STICK_DEADZONE {
			d.y = ay
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_UP) {
			d.y -= 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_DOWN) {
			d.y += 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_LEFT) {
			d.x -= 1
		}
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_FACE_RIGHT) {
			d.x += 1
		}
		if rl.Vector2Length(d) < 0.001 {
			return true, {0, 0}
		}
		return true, rl.Vector2Normalize(d)
	}

	delta := mouse_game_pos - player_center
	if rl.Vector2Length(delta) < 0.001 {
		return true, {0, 0}
	}
	return true, rl.Vector2Normalize(delta)
}
