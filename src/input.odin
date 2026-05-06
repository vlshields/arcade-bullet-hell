package game

import rl "vendor:raylib"

// Feeds the SDL2 game-controller mapping database into raylib so GLFW can
// translate raw HID input from third-party pads (8BitDo, generic clones, etc.)
// into the standard Xbox-style button/axis enums the rest of the input code
// already uses. Without this many controllers are detected but report no
// presses. Call once after rl.InitWindow.
load_gamepad_mappings :: proc() {
	data, ok := read_entire_file("assets/gamecontrollerdb.txt")
	if !ok {
		return
	}
	defer delete(data)

	// rl.SetGamepadMappings expects a null-terminated cstring; clone with a
	// trailing zero rather than mutating the read buffer.
	buf := make([]byte, len(data) + 1)
	defer delete(buf)
	copy(buf, data)
	buf[len(data)] = 0
	rl.SetGamepadMappings(cstring(raw_data(buf)))
}

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

input_attack_pressed :: proc() -> bool {
	if rl.IsMouseButtonPressed(.LEFT) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_TRIGGER_2) {
			return true
		}
	}
	return false
}

input_attack_held :: proc() -> bool {
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

input_slow_time_held :: proc() -> bool {
	if rl.IsKeyDown(.LEFT_SHIFT) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonDown(GAMEPAD_ID, .LEFT_TRIGGER_2) {
			return true
		}
	}
	return false
}

input_shrink_bomb_pressed :: proc() -> bool {
	if rl.IsKeyPressed(.F) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_LEFT) {
			return true
		}
	}
	return false
}

input_confirm_pressed :: proc() -> bool {
	if rl.IsKeyPressed(.ENTER) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_DOWN) {
			return true
		}
	}
	return false
}

// Edge-detected horizontal nudge for menus. Returns -1 / 0 / +1 the frame the
// user taps left/right; held keys do not auto-repeat. Uses dpad + face buttons
// on gamepad; the analog stick is intentionally excluded so a held stick during
// gameplay does not flicker the menu cursor.
input_menu_step_x :: proc() -> int {
	if rl.IsKeyPressed(.A) || rl.IsKeyPressed(.LEFT) {
		return -1
	}
	if rl.IsKeyPressed(.D) || rl.IsKeyPressed(.RIGHT) {
		return 1
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_LEFT) {
			return -1
		}
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_RIGHT) {
			return 1
		}
	}
	return 0
}

input_attack_released :: proc() -> bool {
	if rl.IsMouseButtonReleased(.LEFT) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonReleased(GAMEPAD_ID, .RIGHT_TRIGGER_2) {
			return true
		}
	}
	return false
}

Input_Device :: enum {
	Keyboard,
	Gamepad,
}

@(private = "file")
last_device: Input_Device = .Keyboard

// Picks the device most recently used so menus (e.g. the controls list) can
// label binds for whichever the player is on. Call once per frame before any
// menu code that reads input_last_device.
input_track_device :: proc() {
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		gp_buttons := [?]rl.GamepadButton {
			.LEFT_FACE_UP,
			.LEFT_FACE_DOWN,
			.LEFT_FACE_LEFT,
			.LEFT_FACE_RIGHT,
			.RIGHT_FACE_UP,
			.RIGHT_FACE_DOWN,
			.RIGHT_FACE_LEFT,
			.RIGHT_FACE_RIGHT,
			.LEFT_TRIGGER_1,
			.LEFT_TRIGGER_2,
			.RIGHT_TRIGGER_1,
			.RIGHT_TRIGGER_2,
			.MIDDLE_LEFT,
			.MIDDLE_RIGHT,
		}
		for b in gp_buttons {
			if rl.IsGamepadButtonDown(GAMEPAD_ID, b) {
				last_device = .Gamepad
				return
			}
		}
		ax := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_X)
		ay := rl.GetGamepadAxisMovement(GAMEPAD_ID, .LEFT_Y)
		if abs(ax) > STICK_DEADZONE || abs(ay) > STICK_DEADZONE {
			last_device = .Gamepad
			return
		}
	}

	kb_keys := [?]rl.KeyboardKey {
		.W,
		.A,
		.S,
		.D,
		.UP,
		.DOWN,
		.LEFT,
		.RIGHT,
		.SPACE,
		.LEFT_SHIFT,
		.F,
		.ENTER,
		.ESCAPE,
	}
	for k in kb_keys {
		if rl.IsKeyDown(k) {
			last_device = .Keyboard
			return
		}
	}
	if rl.IsMouseButtonDown(.LEFT) {
		last_device = .Keyboard
	}
}

input_last_device :: proc() -> Input_Device {
	return last_device
}

// Picks between two prebuilt cstring hints based on the player's most recent
// input device. Centralises the kb/gp branch so on-screen prompts stay in sync
// with the active device.
input_hint :: proc(kb_text, gp_text: cstring) -> cstring {
	if last_device == .Gamepad {
		return gp_text
	}
	return kb_text
}

input_pause_toggle_pressed :: proc() -> bool {
	if rl.IsKeyPressed(.ESCAPE) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .MIDDLE_RIGHT) {
			return true
		}
	}
	return false
}

input_menu_back_pressed :: proc() -> bool {
	if rl.IsKeyPressed(.ESCAPE) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_RIGHT) {
			return true
		}
	}
	return false
}

// Edge-detected vertical menu nudge. Mirror of input_menu_step_x but on the
// up/down axis. Excludes the analog stick for the same reason.
input_menu_step_y :: proc() -> int {
	if rl.IsKeyPressed(.W) || rl.IsKeyPressed(.UP) {
		return -1
	}
	if rl.IsKeyPressed(.S) || rl.IsKeyPressed(.DOWN) {
		return 1
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_UP) {
			return -1
		}
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .LEFT_FACE_DOWN) {
			return 1
		}
	}
	return 0
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
