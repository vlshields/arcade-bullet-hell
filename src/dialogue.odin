package game

import "core:strings"
import rl "vendor:raylib"

// Scripted in-mission dialogue. Source data lives in
// assets/dialogue/scenes_level1/hints.json — the strings here are transcribed
// from that file; tokens like {attack} are inline input-hint icons.

Dialogue_Speaker :: enum {
	Paprika,
	Zombi,
}

Dialogue_Line :: struct {
	speaker: Dialogue_Speaker,
	text:    string,
}

Dialogue :: struct {
	active:           bool,
	intro_done:       bool, // level-1 hint_01 fires once per run
	wave2_intro_done: bool, // level-1 hint_02 fires once per run, before wave 2
	lines:            [4]Dialogue_Line,
	line_count:       int,
	line_idx:         int,
	atoms_revealed:   int,
	char_timer:       f32,
	icon_frame:       int,
	icon_frame_t:     f32,
	paprika_tex:      rl.Texture2D,
	zombi_tex:        rl.Texture2D,
}

init_dialogue :: proc(d: ^Dialogue) {
	d.paprika_tex = rl.LoadTexture("assets/sprites/captain_paprika_dialogue_box_icon.png")
	d.zombi_tex = rl.LoadTexture("assets/sprites/player_dialogue_box_icon.png")
	rl.SetTextureFilter(d.paprika_tex, .POINT)
	rl.SetTextureFilter(d.zombi_tex, .POINT)
}

unload_dialogue :: proc(d: ^Dialogue) {
	rl.UnloadTexture(d.paprika_tex)
	rl.UnloadTexture(d.zombi_tex)
}

start_level1_intro :: proc(d: ^Dialogue) {
	if d.intro_done {
		return
	}
	d.lines[0] = Dialogue_Line {
		speaker = .Paprika,
		text    = "It's quiet... Too quiet. Zombi, fire your lasers {attack} to take 'em out",
	}
	d.lines[1] = Dialogue_Line{speaker = .Zombi, text = "Roger that."}
	d.line_count = 2
	dialogue_begin(d)
	d.intro_done = true
}

start_level1_wave2_intro :: proc(d: ^Dialogue) {
	if d.wave2_intro_done {
		return
	}
	d.lines[0] = Dialogue_Line {
		speaker = .Zombi,
		text    = "Grr, there's bullets everywhere!",
	}
	d.lines[1] = Dialogue_Line {
		speaker = .Paprika,
		text    = "Evade them by dashing {dash} - dash into a bullet to reflect it!",
	}
	d.lines[2] = Dialogue_Line {
		speaker = .Paprika,
		text    = "Try your special shrink ability {shrink} too!",
	}
	d.line_count = 3
	dialogue_begin(d)
	d.wave2_intro_done = true
}

@(private = "file")
dialogue_begin :: proc(d: ^Dialogue) {
	d.line_idx = 0
	d.atoms_revealed = 0
	d.char_timer = 0
	d.icon_frame = 0
	d.icon_frame_t = 0
	d.active = true
}

// One atom = one byte of plain text OR one full {token}. Tokens reveal as a
// single typewriter step rather than character-by-character.
@(private = "file")
line_atom_count :: proc(text: string) -> int {
	n := 0
	i := 0
	for i < len(text) {
		if text[i] == '{' {
			for i < len(text) && text[i] != '}' {
				i += 1
			}
			if i < len(text) {
				i += 1
			}
			n += 1
			continue
		}
		n += 1
		i += 1
	}
	return n
}

update_dialogue :: proc(d: ^Dialogue, dt: f32) {
	if !d.active {
		return
	}
	if d.line_idx >= d.line_count {
		d.active = false
		return
	}

	d.icon_frame_t += dt
	for d.icon_frame_t >= DIALOGUE_ICON_FRAME_DUR {
		d.icon_frame_t -= DIALOGUE_ICON_FRAME_DUR
		d.icon_frame = (d.icon_frame + 1) % DIALOGUE_ICON_SRC_FRAMES
	}

	line := d.lines[d.line_idx]
	total := line_atom_count(line.text)

	// Confirm: first press skips typewriter to end; second advances line.
	if input_confirm_pressed() {
		if d.atoms_revealed < total {
			d.atoms_revealed = total
			return
		}
		d.line_idx += 1
		d.atoms_revealed = 0
		d.char_timer = 0
		if d.line_idx >= d.line_count {
			d.active = false
		}
		return
	}

	if d.atoms_revealed < total {
		d.char_timer += dt
		for d.char_timer >= DIALOGUE_CHAR_INTERVAL && d.atoms_revealed < total {
			d.char_timer -= DIALOGUE_CHAR_INTERVAL
			d.atoms_revealed += 1
		}
	}
}

draw_dialogue :: proc(d: ^Dialogue) {
	if !d.active || d.line_idx >= d.line_count {
		return
	}

	box_x: i32 = (SCREEN_WIDTH - DIALOGUE_BOX_W) / 2
	box_y: i32 = SCREEN_HEIGHT - DIALOGUE_BOX_H - DIALOGUE_BOX_BOTTOM_MARGIN

	rl.DrawRectangle(box_x, box_y, DIALOGUE_BOX_W, DIALOGUE_BOX_H, rl.Color{8, 8, 14, 252})
	rl.DrawRectangleLines(box_x, box_y, DIALOGUE_BOX_W, DIALOGUE_BOX_H, rl.Color{200, 200, 220, 255})

	line := d.lines[d.line_idx]

	tex: rl.Texture2D
	name: cstring
	accent: rl.Color
	switch line.speaker {
	case .Paprika:
		tex = d.paprika_tex
		name = "CAPTAIN PAPRIKA"
		accent = rl.Color{255, 140, 80, 255}
	case .Zombi:
		tex = d.zombi_tex
		name = "ZOMBI"
		accent = rl.Color{120, 220, 160, 255}
	}

	icon_x: f32 = f32(box_x + DIALOGUE_BOX_PAD)
	icon_y: f32 =
		f32(box_y) + (f32(DIALOGUE_BOX_H) - f32(DIALOGUE_ICON_DRAW_SIZE)) * 0.5
	src := rl.Rectangle {
		f32(d.icon_frame * DIALOGUE_ICON_SRC_W),
		0,
		f32(DIALOGUE_ICON_SRC_W),
		f32(DIALOGUE_ICON_SRC_H),
	}
	dst := rl.Rectangle {
		icon_x,
		icon_y,
		f32(DIALOGUE_ICON_DRAW_SIZE),
		f32(DIALOGUE_ICON_DRAW_SIZE),
	}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)

	// Speaker name above the box.
	nx: i32 = box_x + DIALOGUE_BOX_PAD
	ny: i32 = box_y - DIALOGUE_NAME_FONT_SIZE - 3
	rl.DrawText(name, nx + 1, ny + 1, DIALOGUE_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, nx, ny, DIALOGUE_NAME_FONT_SIZE, accent)

	text_x0: i32 =
		box_x + DIALOGUE_BOX_PAD + DIALOGUE_ICON_DRAW_SIZE + DIALOGUE_BOX_PAD
	text_y0: i32 = box_y + DIALOGUE_BOX_PAD
	text_w: i32 = DIALOGUE_BOX_W - (text_x0 - box_x) - DIALOGUE_BOX_PAD
	line_h: i32 = DIALOGUE_TEXT_FONT_SIZE + DIALOGUE_TEXT_LINE_GAP

	draw_dialogue_text(line.text, d.atoms_revealed, text_x0, text_y0, text_w, line_h)
}

@(private = "file")
token_to_hint :: proc(token: string) -> (Input_Hint, bool) {
	switch token {
	case "attack":
		return .Attack, true
	case "dash":
		return .Dash, true
	case "shrink":
		return .Shrink_Bomb, true
	case "slow":
		return .Slow_Time, true
	case "confirm":
		return .Confirm, true
	}
	return .Attack, false
}

@(private = "file")
draw_dialogue_text :: proc(text: string, atoms_revealed: int, x0, y0, w, line_h: i32) {
	font_size: i32 = DIALOGUE_TEXT_FONT_SIZE
	cur_x := x0
	cur_y := y0
	drawn := 0
	space_w := rl.MeasureText(" ", font_size)

	i := 0
	for i < len(text) {
		if drawn >= atoms_revealed {
			break
		}

		ch := text[i]

		if ch == '{' {
			rel_close := strings.index_byte(text[i:], '}')
			if rel_close >= 0 {
				token := text[i + 1:i + rel_close]
				hint, _ := token_to_hint(token)
				token_w := input_hint_width(hint, DIALOGUE_INLINE_HINT_SIZE)
				if cur_x + token_w > x0 + w {
					cur_x = x0
					cur_y += line_h
				}
				icon_y := cur_y + (font_size - DIALOGUE_INLINE_HINT_SIZE) / 2
				_ = draw_input_hint(hint, cur_x, icon_y, DIALOGUE_INLINE_HINT_SIZE)
				cur_x += token_w
				i += rel_close + 1
				drawn += 1
				continue
			}
		}

		// Word-wrap at spaces: peek to the next break and wrap if the upcoming
		// word would overflow.
		if ch == ' ' {
			j := i + 1
			for j < len(text) && text[j] != ' ' && text[j] != '{' {
				j += 1
			}
			word := text[i + 1:j]
			cword := strings.clone_to_cstring(word, context.temp_allocator)
			word_w := rl.MeasureText(cword, font_size)
			if cur_x + space_w + word_w > x0 + w {
				cur_x = x0
				cur_y += line_h
				drawn += 1
				i += 1
				continue
			}
		}

		buf := make([]u8, 2, context.temp_allocator)
		buf[0] = ch
		buf[1] = 0
		cstr := cstring(raw_data(buf))
		// Drop shadow keeps text readable against bright parallax backgrounds.
		rl.DrawText(cstr, cur_x + 1, cur_y + 1, font_size, rl.BLACK)
		rl.DrawText(cstr, cur_x, cur_y, font_size, rl.WHITE)
		cur_x += rl.MeasureText(cstr, font_size)
		i += 1
		drawn += 1
	}

	// Continue prompt once the current line is fully revealed.
	total := line_atom_count(text)
	if atoms_revealed >= total {
		blink := int(rl.GetTime() * 2) % 2 == 0
		if blink {
			tri_x := x0 + w - 8
			tri_y := y0 + line_h * 2 + 2
			rl.DrawTriangle(
				{f32(tri_x), f32(tri_y)},
				{f32(tri_x + 6), f32(tri_y)},
				{f32(tri_x + 3), f32(tri_y + 5)},
				rl.Color{220, 220, 220, 255},
			)
		}
	}
}
