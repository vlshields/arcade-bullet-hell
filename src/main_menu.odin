package game

import rl "vendor:raylib"

// Top-level menu shown before any gameplay starts (and again after the player
// quits from pause). Uses the level-1 parallax as a live backdrop so the menu
// doesn't feel static. Options/Controls sub-screens reuse the same widgets as
// the pause menu via the shared draw_pause_options / draw_pause_controls procs.

Main_Menu_Screen :: enum {
	Main,
	Options,
	Controls,
}

Main_Menu :: struct {
	screen: Main_Menu_Screen,
	cursor: int,
}

reset_main_menu :: proc(mm: ^Main_Menu) {
	mm.screen = .Main
	mm.cursor = 0
}

// Returns true when the player picked "BEGIN", which the caller turns into a
// fresh-game start. "QUIT" is signaled via quit_app^ for desktop only.
update_main_menu :: proc(
	mm: ^Main_Menu,
	begin_game: ^bool,
	quit_app: ^bool,
	audio: ^Audio,
) {
	switch mm.screen {
	case .Main:
		item_count := 4
		step := input_menu_step_y()
		if step != 0 {
			mm.cursor = (mm.cursor + step + item_count) % item_count
		}
		if input_confirm_pressed() {
			switch mm.cursor {
			case 0:
				begin_game^ = true
			case 1:
				mm.screen = .Options
				mm.cursor = 0
			case 2:
				mm.screen = .Controls
				mm.cursor = 0
			case 3:
				when ODIN_OS != .JS {
					quit_app^ = true
				}
			}
		}

	case .Options:
		if input_menu_back_pressed() {
			mm.screen = .Main
			mm.cursor = 1
			return
		}
		item_count := 3
		step := input_menu_step_y()
		if step != 0 {
			mm.cursor = (mm.cursor + step + item_count) % item_count
		}
		h := input_menu_step_x()
		if h != 0 {
			switch mm.cursor {
			case 0:
				set_music_volume(audio, audio.music_volume + f32(h) * PAUSE_VOLUME_STEP)
			case 1:
				set_sfx_volume(audio, audio.sfx_volume + f32(h) * PAUSE_VOLUME_STEP)
			}
		}
		if input_confirm_pressed() && mm.cursor == 2 {
			mm.screen = .Main
			mm.cursor = 1
		}

	case .Controls:
		if input_menu_back_pressed() || input_confirm_pressed() {
			mm.screen = .Main
			mm.cursor = 2
		}
	}
}

draw_main_menu :: proc(mm: ^Main_Menu, audio: ^Audio) {
	// Slight darken so text reads cleanly over the parallax stars.
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, MAIN_MENU_OVERLAY_ALPHA})

	title := cstring("BULLETHELL")
	tw := rl.MeasureText(title, MAIN_MENU_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	rl.DrawText(title, tx + 3, MAIN_MENU_TITLE_Y + 3, MAIN_MENU_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, tx, MAIN_MENU_TITLE_Y, MAIN_MENU_TITLE_FONT_SIZE, rl.WHITE)

	switch mm.screen {
	case .Main:
		draw_main_menu_items(mm.cursor)
	case .Options:
		draw_pause_options(mm.cursor, audio)
	case .Controls:
		draw_pause_controls()
	}
}

@(private = "file")
draw_main_menu_items :: proc(cursor: int) {
	items := [?]cstring {
		cstring("BEGIN"),
		cstring("OPTIONS"),
		cstring("CONTROLS"),
		cstring("QUIT"),
	}
	y: i32 = MAIN_MENU_ITEMS_TOP_Y
	for it, i in items {
		draw_menu_label(it, y, cursor == i)
		y += PAUSE_ITEM_FONT_SIZE + PAUSE_ITEM_GAP
	}
}
