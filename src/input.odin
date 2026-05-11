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

// Reroll on the post-mission upgrade picker. Keyboard R / gamepad Y. No icon
// asset for either, so the upgrade screen draws a text prompt — keep this
// distinct from the gameplay-only bindings (shrink bomb F/X, dash SPACE/B).
input_reroll_pressed :: proc() -> bool {
	if rl.IsKeyPressed(.R) {
		return true
	}
	if rl.IsGamepadAvailable(GAMEPAD_ID) {
		if rl.IsGamepadButtonPressed(GAMEPAD_ID, .RIGHT_FACE_UP) {
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

// Semantic prompts the UI can ask to render an icon for. The mapping to a
// concrete texture is split per device in draw_input_hint.
Input_Hint :: enum {
	Move,
	Menu_Step_Horizontal,
	Attack,
	Dash,
	Slow_Time,
	Shrink_Bomb,
	Pause,
	Confirm,
	Back,
}

// Source PNGs are 64x64; we downscale to HINT_ICON_SIZE on the 640x360 render
// target. Bilinear filter keeps the icons readable at small sizes; the outer
// render-target upscale to the window stays POINT so pixel art elsewhere is
// unaffected.
@(private = "file")
hint_textures: struct {
	// Keyboard / mouse
	kb_arrows:        rl.Texture2D,
	kb_arrows_horiz:  rl.Texture2D,
	mouse_left:       rl.Texture2D,
	kb_space:         rl.Texture2D,
	kb_shift:         rl.Texture2D,
	kb_f:             rl.Texture2D,
	kb_escape:        rl.Texture2D,
	kb_enter:         rl.Texture2D,
	// Xbox-style gamepad
	gp_stick_l:       rl.Texture2D,
	gp_dpad:          rl.Texture2D,
	gp_dpad_horiz:    rl.Texture2D,
	gp_rt:            rl.Texture2D,
	gp_lt:            rl.Texture2D,
	gp_button_a:      rl.Texture2D,
	gp_button_b:      rl.Texture2D,
	gp_button_x:      rl.Texture2D,
	gp_button_menu:   rl.Texture2D,
}

@(private = "file")
load_hint_texture :: proc(path: cstring) -> rl.Texture2D {
	tex := rl.LoadTexture(path)
	rl.SetTextureFilter(tex, .BILINEAR)
	return tex
}

init_input_hints :: proc() {
	hint_textures.kb_arrows = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_arrows.png")
	hint_textures.kb_arrows_horiz = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_arrows_horizontal.png")
	hint_textures.mouse_left = load_hint_texture("assets/tiles/DefaultKeeb/mouse_left.png")
	hint_textures.kb_space = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_space.png")
	hint_textures.kb_shift = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_shift.png")
	hint_textures.kb_f = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_f.png")
	hint_textures.kb_escape = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_escape.png")
	hint_textures.kb_enter = load_hint_texture("assets/tiles/DefaultKeeb/keyboard_enter.png")

	hint_textures.gp_stick_l = load_hint_texture("assets/tiles/Default/xbox_stick_l.png")
	hint_textures.gp_dpad = load_hint_texture("assets/tiles/Default/xbox_dpad.png")
	hint_textures.gp_dpad_horiz = load_hint_texture("assets/tiles/Default/xbox_dpad_horizontal.png")
	hint_textures.gp_rt = load_hint_texture("assets/tiles/Default/xbox_rt.png")
	hint_textures.gp_lt = load_hint_texture("assets/tiles/Default/xbox_lt.png")
	hint_textures.gp_button_a = load_hint_texture("assets/tiles/Default/xbox_button_color_a.png")
	hint_textures.gp_button_b = load_hint_texture("assets/tiles/Default/xbox_button_color_b.png")
	hint_textures.gp_button_x = load_hint_texture("assets/tiles/Default/xbox_button_color_x.png")
	hint_textures.gp_button_menu = load_hint_texture("assets/tiles/Default/xbox_button_menu.png")
}

unload_input_hints :: proc() {
	rl.UnloadTexture(hint_textures.kb_arrows)
	rl.UnloadTexture(hint_textures.kb_arrows_horiz)
	rl.UnloadTexture(hint_textures.mouse_left)
	rl.UnloadTexture(hint_textures.kb_space)
	rl.UnloadTexture(hint_textures.kb_shift)
	rl.UnloadTexture(hint_textures.kb_f)
	rl.UnloadTexture(hint_textures.kb_escape)
	rl.UnloadTexture(hint_textures.kb_enter)
	rl.UnloadTexture(hint_textures.gp_stick_l)
	rl.UnloadTexture(hint_textures.gp_dpad)
	rl.UnloadTexture(hint_textures.gp_dpad_horiz)
	rl.UnloadTexture(hint_textures.gp_rt)
	rl.UnloadTexture(hint_textures.gp_lt)
	rl.UnloadTexture(hint_textures.gp_button_a)
	rl.UnloadTexture(hint_textures.gp_button_b)
	rl.UnloadTexture(hint_textures.gp_button_x)
	rl.UnloadTexture(hint_textures.gp_button_menu)
}

// Fills `out` with the textures to draw left-to-right for `kind` on the active
// device and returns how many slots were used. Most hints are a single icon;
// Move on gamepad is the only two-icon case (left stick + dpad).
@(private = "file")
hint_icons :: proc(kind: Input_Hint, out: ^[2]rl.Texture2D) -> int {
	on_gamepad := last_device == .Gamepad
	switch kind {
	case .Move:
		if on_gamepad {
			out[0] = hint_textures.gp_stick_l
			out[1] = hint_textures.gp_dpad
			return 2
		}
		out[0] = hint_textures.kb_arrows
		return 1
	case .Menu_Step_Horizontal:
		out[0] = on_gamepad ? hint_textures.gp_dpad_horiz : hint_textures.kb_arrows_horiz
		return 1
	case .Attack:
		out[0] = on_gamepad ? hint_textures.gp_rt : hint_textures.mouse_left
		return 1
	case .Dash:
		out[0] = on_gamepad ? hint_textures.gp_button_b : hint_textures.kb_space
		return 1
	case .Slow_Time:
		out[0] = on_gamepad ? hint_textures.gp_lt : hint_textures.kb_shift
		return 1
	case .Shrink_Bomb:
		out[0] = on_gamepad ? hint_textures.gp_button_x : hint_textures.kb_f
		return 1
	case .Pause:
		out[0] = on_gamepad ? hint_textures.gp_button_menu : hint_textures.kb_escape
		return 1
	case .Confirm:
		out[0] = on_gamepad ? hint_textures.gp_button_a : hint_textures.kb_enter
		return 1
	case .Back:
		out[0] = on_gamepad ? hint_textures.gp_button_b : hint_textures.kb_escape
		return 1
	}
	return 0
}

// Total width an `kind` hint will occupy when drawn at icon `size`. Caller
// uses this to lay out hint+text rows or center them on screen.
input_hint_width :: proc(kind: Input_Hint, size: i32) -> i32 {
	icons: [2]rl.Texture2D
	n := i32(hint_icons(kind, &icons))
	if n <= 0 {
		return 0
	}
	return n * size + (n - 1) * HINT_ICON_GAP
}

// Pending hint to be flushed at window resolution after the render-target
// upscale. Going through the render target's POINT filter mushes the
// downscaled icon detail; drawing post-upscale at native window resolution
// keeps them sharp while the game art stays chunky pixel-art.
@(private = "file")
Hint_Draw :: struct {
	kind:    Input_Hint,
	rt_x:    i32,
	rt_y:    i32,
	rt_size: i32,
}

@(private = "file")
hint_draw_queue: [32]Hint_Draw

@(private = "file")
hint_draw_count: int

// Records a hint at render-target coords (x, y) so flush_input_hints can later
// blit it at the matching window position. Returns the render-target width the
// icon will occupy so the caller can lay out adjacent text against it.
draw_input_hint :: proc(kind: Input_Hint, x, y: i32, size: i32) -> i32 {
	if hint_draw_count < len(hint_draw_queue) {
		hint_draw_queue[hint_draw_count] = Hint_Draw {
			kind    = kind,
			rt_x    = x,
			rt_y    = y,
			rt_size = size,
		}
		hint_draw_count += 1
	}
	return input_hint_width(kind, size)
}

// Blits queued hints onto the window using the same scale/offset as the
// render-target upscale. Call once per frame, after rl.DrawTexturePro and
// before rl.EndDrawing. Clears the queue on flush.
flush_input_hints :: proc(scale, offset_x, offset_y: f32) {
	src := rl.Rectangle{0, 0, 64, 64}
	icons: [2]rl.Texture2D
	for i in 0 ..< hint_draw_count {
		h := hint_draw_queue[i]
		n := hint_icons(h.kind, &icons)
		cursor_x := f32(h.rt_x)
		for j in 0 ..< n {
			dst := rl.Rectangle {
				offset_x + cursor_x * scale,
				offset_y + f32(h.rt_y) * scale,
				f32(h.rt_size) * scale,
				f32(h.rt_size) * scale,
			}
			rl.DrawTexturePro(icons[j], src, dst, {0, 0}, 0, rl.WHITE)
			cursor_x += f32(h.rt_size)
			if j < n - 1 {
				cursor_x += HINT_ICON_GAP
			}
		}
	}
	hint_draw_count = 0
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
