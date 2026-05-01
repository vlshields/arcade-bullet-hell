package game

import rl "vendor:raylib"

Background :: struct {
	textures: [BG_LAYERS]rl.Texture2D,
	offsets:  [BG_LAYERS]f32,
	speeds:   [BG_LAYERS]f32,
}

init_background :: proc(bg: ^Background) {
	bg.textures[0] = rl.LoadTexture("assets/parallaxbg0.png")
	bg.textures[1] = rl.LoadTexture("assets/parallaxbg1.png")
	bg.textures[2] = rl.LoadTexture("assets/parallaxbg2.png")
	for i in 0 ..< BG_LAYERS {
		rl.SetTextureFilter(bg.textures[i], .POINT)
	}
	bg.speeds = {10, 25, 60}
}

unload_background :: proc(bg: ^Background) {
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(bg.textures[i])
	}
}

update_background :: proc(bg: ^Background, dt: f32) {
	for i in 0 ..< BG_LAYERS {
		h := f32(bg.textures[i].height)
		bg.offsets[i] += bg.speeds[i] * dt
		for bg.offsets[i] >= h {
			bg.offsets[i] -= h
		}
	}
}

draw_background :: proc(bg: ^Background) {
	for i in 0 ..< BG_LAYERS {
		tex := bg.textures[i]
		if tex.height <= 0 {
			continue
		}
		h := f32(tex.height)
		y := bg.offsets[i] - h
		for cy := y; cy < f32(SCREEN_HEIGHT); cy += h {
			rl.DrawTexture(tex, 0, i32(cy), rl.WHITE)
		}
	}
}
