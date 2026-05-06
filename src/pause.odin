package game

import "core:fmt"
import rl "vendor:raylib"

Pause_Screen :: enum {
	Main,
	Options,
	Controls,
}

Pause_Menu :: struct {
	screen: Pause_Screen,
	cursor: int,
}

reset_pause_menu :: proc(pm: ^Pause_Menu) {
	pm.screen = .Main
	pm.cursor = 0
}

update_pause :: proc(pm: ^Pause_Menu, paused: ^bool, audio: ^Audio) {
	switch pm.screen {
	case .Main:
		// Toggle takes priority on Main so ESC / Start closes the menu.
		if input_pause_toggle_pressed() {
			paused^ = false
			return
		}
		item_count := 4
		step := input_menu_step_y()
		if step != 0 {
			pm.cursor = (pm.cursor + step + item_count) % item_count
		}
		if input_confirm_pressed() {
			switch pm.cursor {
			case 0:
				paused^ = false
			case 1:
				pm.screen = .Options
				pm.cursor = 0
			case 2:
				pm.screen = .Controls
				pm.cursor = 0
			case 3:
				// Quit: placeholder per spec.
			}
		}

	case .Options:
		// On submenus ESC / B steps back to Main rather than unpausing,
		// so check back before toggle.
		if input_menu_back_pressed() {
			pm.screen = .Main
			pm.cursor = 1
			return
		}
		item_count := 3
		step := input_menu_step_y()
		if step != 0 {
			pm.cursor = (pm.cursor + step + item_count) % item_count
		}
		h := input_menu_step_x()
		if h != 0 {
			switch pm.cursor {
			case 0:
				set_music_volume(audio, audio.music_volume + f32(h) * PAUSE_VOLUME_STEP)
			case 1:
				set_sfx_volume(audio, audio.sfx_volume + f32(h) * PAUSE_VOLUME_STEP)
			}
		}
		if input_confirm_pressed() && pm.cursor == 2 {
			pm.screen = .Main
			pm.cursor = 1
		}

	case .Controls:
		if input_menu_back_pressed() || input_confirm_pressed() {
			pm.screen = .Main
			pm.cursor = 2
		}
	}
}

draw_pause :: proc(pm: ^Pause_Menu, audio: ^Audio) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, PAUSE_OVERLAY_ALPHA})

	title := cstring("PAUSED")
	tw := rl.MeasureText(title, PAUSE_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	rl.DrawText(title, tx + 2, PAUSE_TITLE_Y + 2, PAUSE_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, tx, PAUSE_TITLE_Y, PAUSE_TITLE_FONT_SIZE, rl.WHITE)

	switch pm.screen {
	case .Main:
		draw_pause_main(pm.cursor)
	case .Options:
		draw_pause_options(pm.cursor, audio)
	case .Controls:
		draw_pause_controls()
	}
}

@(private = "file")
draw_pause_main :: proc(cursor: int) {
	items := [?]cstring{cstring("RESUME"), cstring("OPTIONS"), cstring("CONTROLS"), cstring("QUIT")}
	y: i32 = PAUSE_MENU_TOP_Y
	for it, i in items {
		draw_menu_label(it, y, cursor == i)
		y += PAUSE_ITEM_FONT_SIZE + PAUSE_ITEM_GAP
	}
}

@(private = "file")
draw_pause_options :: proc(cursor: int, audio: ^Audio) {
	row_h: i32 = PAUSE_ITEM_FONT_SIZE + PAUSE_SLIDER_H + 10
	y: i32 = PAUSE_MENU_TOP_Y
	draw_menu_slider(cstring("MUSIC"), audio.music_volume, y, cursor == 0)
	y += row_h + PAUSE_ITEM_GAP
	draw_menu_slider(cstring("SFX"), audio.sfx_volume, y, cursor == 1)
	y += row_h + PAUSE_ITEM_GAP
	draw_menu_label(cstring("BACK"), y, cursor == 2)
}

@(private = "file")
draw_pause_controls :: proc() {
	on_gamepad := input_last_device() == .Gamepad

	header: cstring = cstring("CONTROLS - KEYBOARD")
	if on_gamepad {
		header = cstring("CONTROLS - GAMEPAD")
	}
	hw := rl.MeasureText(header, PAUSE_ITEM_FONT_SIZE)
	hx := (i32(SCREEN_WIDTH) - hw) / 2
	hy: i32 = PAUSE_MENU_TOP_Y - 30
	rl.DrawText(header, hx + 1, hy + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(header, hx, hy, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)

	y := hy + PAUSE_ITEM_FONT_SIZE + 10
	if on_gamepad {
		draw_control_row(cstring("MOVE"), cstring("LEFT STICK / DPAD"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("ATTACK"), cstring("RT"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("DASH"), cstring("B"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("SLOW TIME"), cstring("LT"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("SHRINK BOMB"), cstring("X"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("PAUSE"), cstring("START"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("CONFIRM"), cstring("A"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("BACK"), cstring("B"), y)
	} else {
		draw_control_row(cstring("MOVE"), cstring("WASD / ARROWS"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("ATTACK"), cstring("MOUSE LEFT"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("DASH"), cstring("SPACE"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("SLOW TIME"), cstring("LEFT SHIFT"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("SHRINK BOMB"), cstring("F"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("PAUSE"), cstring("ESCAPE"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("CONFIRM"), cstring("ENTER"), y)
		y += PAUSE_BODY_LINE_GAP
		draw_control_row(cstring("BACK"), cstring("ESCAPE"), y)
	}

	hint := input_hint("ENTER TO RETURN", "A TO RETURN")
	hint_w := rl.MeasureText(hint, PAUSE_BODY_FONT_SIZE)
	rl.DrawText(
		hint,
		(i32(SCREEN_WIDTH) - hint_w) / 2,
		SCREEN_HEIGHT - 22,
		PAUSE_BODY_FONT_SIZE,
		rl.WHITE,
	)
}

@(private = "file")
draw_control_row :: proc(label, bind: cstring, y: i32) {
	label_x: i32 = SCREEN_WIDTH / 2 - 110
	bind_x: i32 = SCREEN_WIDTH / 2 + 10
	rl.DrawText(label, label_x, y, PAUSE_BODY_FONT_SIZE, rl.WHITE)
	rl.DrawText(bind, bind_x, y, PAUSE_BODY_FONT_SIZE, rl.Color{200, 200, 220, 255})
}

@(private = "file")
draw_menu_label :: proc(text: cstring, y: i32, selected: bool) {
	color := rl.Color{180, 180, 180, 255}
	if selected {
		color = rl.WHITE
	}
	w := rl.MeasureText(text, PAUSE_ITEM_FONT_SIZE)
	x := (i32(SCREEN_WIDTH) - w) / 2
	rl.DrawText(text, x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(text, x, y, PAUSE_ITEM_FONT_SIZE, color)
	if selected {
		rl.DrawText(cstring(">"), x - 14, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
		rl.DrawText(cstring("<"), x + w + 6, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
	}
}

@(private = "file")
draw_menu_slider :: proc(label: cstring, value: f32, y: i32, selected: bool) {
	color := rl.Color{180, 180, 180, 255}
	if selected {
		color = rl.WHITE
	}
	pct := fmt.ctprintf("%d%%", int(value * 100 + 0.5))
	label_w := rl.MeasureText(label, PAUSE_ITEM_FONT_SIZE)
	pct_w := rl.MeasureText(pct, PAUSE_ITEM_FONT_SIZE)
	spacing: i32 = 16
	total_w := label_w + spacing + pct_w
	label_x := (i32(SCREEN_WIDTH) - total_w) / 2
	pct_x := label_x + label_w + spacing
	rl.DrawText(label, label_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(label, label_x, y, PAUSE_ITEM_FONT_SIZE, color)
	rl.DrawText(pct, pct_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(pct, pct_x, y, PAUSE_ITEM_FONT_SIZE, color)

	bar_w: i32 = PAUSE_SLIDER_W
	bar_h: i32 = PAUSE_SLIDER_H
	bar_x := (i32(SCREEN_WIDTH) - bar_w) / 2
	bar_y := y + PAUSE_ITEM_FONT_SIZE + 4
	rl.DrawRectangle(bar_x, bar_y, bar_w, bar_h, rl.Color{40, 40, 60, 255})
	fill_w := i32(f32(bar_w) * value + 0.5)
	fill_color := rl.Color{120, 120, 160, 255}
	if selected {
		fill_color = rl.Color{80, 180, 255, 255}
	}
	rl.DrawRectangle(bar_x, bar_y, fill_w, bar_h, fill_color)
	rl.DrawRectangleLines(bar_x, bar_y, bar_w, bar_h, rl.Color{120, 120, 140, 255})
	if selected {
		rl.DrawText(cstring("<"), bar_x - 14, bar_y - 4, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
		rl.DrawText(cstring(">"), bar_x + bar_w + 6, bar_y - 4, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
	}
}
