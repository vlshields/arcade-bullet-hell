package game

import rl "vendor:raylib"

// Stage-card title shown for a few seconds when a mission begins. Two-tier:
// big "MISSION I" stack atop a smaller subtitle. Faded with smoothstep so it
// blends with the menu->gameplay transition fade rather than popping in.

Mission_Title :: struct {
	active:   bool,
	timer:    f32,
	title:    cstring,
	subtitle: cstring,
}

show_mission_title :: proc(mt: ^Mission_Title, level: int) {
	title, sub, ok := mission_strings(level)
	if !ok {
		mt.active = false
		return
	}
	mt.title = title
	mt.subtitle = sub
	mt.timer = 0
	mt.active = true
}

@(private = "file")
mission_strings :: proc(level: int) -> (title: cstring, sub: cstring, ok: bool) {
	switch level {
	case 1:
		return cstring("MISSION I"), cstring("RAID GOLGATHA'S HEADQUARTERS"), true
	}
	return "", "", false
}

update_mission_title :: proc(mt: ^Mission_Title, dt: f32) {
	if !mt.active {
		return
	}
	mt.timer += dt
	total := f32(MISSION_TITLE_FADE_IN + MISSION_TITLE_HOLD + MISSION_TITLE_FADE_OUT)
	if mt.timer >= total {
		mt.active = false
	}
}

draw_mission_title :: proc(mt: ^Mission_Title) {
	if !mt.active {
		return
	}
	a := mission_title_alpha(mt.timer)
	if a == 0 {
		return
	}

	tw := rl.MeasureText(mt.title, MISSION_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	ty: i32 = MISSION_TITLE_Y
	rl.DrawText(mt.title, tx + 2, ty + 2, MISSION_TITLE_FONT_SIZE, rl.Color{0, 0, 0, a})
	rl.DrawText(mt.title, tx, ty, MISSION_TITLE_FONT_SIZE, rl.Color{255, 220, 80, a})

	sw := rl.MeasureText(mt.subtitle, MISSION_SUBTITLE_FONT_SIZE)
	sx := (i32(SCREEN_WIDTH) - sw) / 2
	sy: i32 = ty + MISSION_TITLE_FONT_SIZE + MISSION_SUBTITLE_GAP
	rl.DrawText(mt.subtitle, sx + 1, sy + 1, MISSION_SUBTITLE_FONT_SIZE, rl.Color{0, 0, 0, a})
	rl.DrawText(mt.subtitle, sx, sy, MISSION_SUBTITLE_FONT_SIZE, rl.Color{220, 220, 240, a})
}

@(private = "file")
mission_title_alpha :: proc(t: f32) -> u8 {
	fade_in := f32(MISSION_TITLE_FADE_IN)
	hold := f32(MISSION_TITLE_HOLD)
	fade_out := f32(MISSION_TITLE_FADE_OUT)
	a: f32
	switch {
	case t < fade_in:
		a = smoothstep(t / fade_in)
	case t < fade_in + hold:
		a = 1
	case t < fade_in + hold + fade_out:
		a = 1 - smoothstep((t - fade_in - hold) / fade_out)
	case:
		a = 0
	}
	if a < 0 {
		a = 0
	}
	if a > 1 {
		a = 1
	}
	return u8(a * 255)
}
