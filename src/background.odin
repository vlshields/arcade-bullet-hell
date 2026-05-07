package game

import "core:fmt"
import rl "vendor:raylib"

Background :: struct {
	textures:    [BG_LAYERS]rl.Texture2D,
	offsets:     [BG_LAYERS]f32,
	speeds:      [BG_LAYERS]f32,
	// Level 3+ swaps the parallax stack for a single static image with a wave-shader
	// distortion. shader_mode tracks that swap; seconds drives the shader's animation.
	wave:        Wave_Shader,
	seconds:     f32,
	shader_mode: bool,
}

init_background :: proc(bg: ^Background) {
	bg.speeds = {10, 25, 60}
	bg.wave = load_wave_shader()
	load_bg_textures(bg, 1)
}

unload_background :: proc(bg: ^Background) {
	unload_wave_shader(&bg.wave)
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(bg.textures[i])
	}
}

set_background_level :: proc(bg: ^Background, level: int) {
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(bg.textures[i])
		bg.textures[i] = {}
		bg.offsets[i] = 0
	}
	bg.shader_mode = level >= 3
	bg.seconds = 0
	load_bg_textures(bg, level)
}

@(private = "file")
bg_path :: proc(level: int, i: int) -> cstring {
	if level <= 1 {
		return fmt.ctprintf("assets/parallaxbg%d.png", i)
	}
	if level >= 3 {
		return "assets/level3_bg.png"
	}
	return fmt.ctprintf("assets/level%d_parallaxbg%d.png", level, i)
}

// The bg0 file may be a stacked atlas of all BG_LAYERS frames (one per
// SCREEN_HEIGHT row), in which case bg1/bg2 files are ignored. Level 3+
// uses a single non-scrolling image and ignores the layer machinery entirely.
@(private = "file")
load_bg_textures :: proc(bg: ^Background, level: int) {
	if bg.shader_mode {
		bg.textures[0] = rl.LoadTexture(bg_path(level, 0))
		rl.SetTextureFilter(bg.textures[0], .POINT)
		return
	}

	img := rl.LoadImage(bg_path(level, 0))
	defer rl.UnloadImage(img)

	if img.height >= SCREEN_HEIGHT * BG_LAYERS {
		for i in 0 ..< BG_LAYERS {
			rec := rl.Rectangle{0, f32(i * SCREEN_HEIGHT), f32(img.width), f32(SCREEN_HEIGHT)}
			slice := rl.ImageFromImage(img, rec)
			bg.textures[i] = rl.LoadTextureFromImage(slice)
			rl.UnloadImage(slice)
			rl.SetTextureFilter(bg.textures[i], .POINT)
		}
		return
	}

	bg.textures[0] = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(bg.textures[0], .POINT)
	for i in 1 ..< BG_LAYERS {
		bg.textures[i] = rl.LoadTexture(bg_path(level, i))
		rl.SetTextureFilter(bg.textures[i], .POINT)
	}
}

update_background :: proc(bg: ^Background, dt: f32) {
	if bg.shader_mode {
		bg.seconds += dt
		return
	}
	for i in 0 ..< BG_LAYERS {
		h := f32(bg.textures[i].height)
		bg.offsets[i] += bg.speeds[i] * dt
		for bg.offsets[i] >= h {
			bg.offsets[i] -= h
		}
	}
}

draw_background :: proc(bg: ^Background) {
	if bg.shader_mode {
		tex := bg.textures[0]
		if tex.id == 0 {
			return
		}
		set_wave_seconds(&bg.wave, bg.seconds)
		rl.BeginShaderMode(bg.wave.shader)
		rl.DrawTexture(tex, 0, 0, rl.WHITE)
		rl.EndShaderMode()
		return
	}
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
