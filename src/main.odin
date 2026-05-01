package game

import rl "vendor:raylib"

Game_State :: struct {
	render_target: rl.RenderTexture2D,
	camera:        rl.Camera2D,
	background:    Background,
	player:        Player,
	enemies:       Enemy_Pool,
	bullets:       Bullet_Pool,
	beams:         Beam_Pool,
	particles:     Particle_Pool,
	window_w:      int,
	window_h:      int,
	scale:         f32,
	offset_x:      f32,
	offset_y:      f32,
	mouse_x:       int,
	mouse_y:       int,
	mouse_down:    bool,
	running:       bool,
}

@(private = "file")
gs: Game_State

init :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "bullethell")
	rl.SetTargetFPS(60)

	gs.render_target = rl.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	rl.SetTextureFilter(gs.render_target.texture, .POINT)

	gs.camera = rl.Camera2D {
		offset   = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		target   = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2},
		rotation = 0,
		zoom     = 1,
	}

	gs.window_w = int(rl.GetScreenWidth())
	gs.window_h = int(rl.GetScreenHeight())
	update_screen_scale()

	init_background(&gs.background)
	init_player(&gs.player)
	init_enemies(&gs.enemies)

	gs.running = true
}

should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		if rl.WindowShouldClose() {
			return false
		}
	}
	return gs.running
}

update :: proc() {
	free_all(context.temp_allocator)

	when ODIN_OS != .JS {
		if rl.IsWindowResized() {
			gs.window_w = int(rl.GetScreenWidth())
			gs.window_h = int(rl.GetScreenHeight())
			update_screen_scale()
		}
	}

	dt := rl.GetFrameTime()
	update_background(&gs.background, dt)
	update_player(&gs.player, dt)
	update_enemies(&gs.enemies, &gs.player, &gs.bullets, dt)
	update_player_attack(&gs.player, &gs.beams, &gs.enemies, &gs.particles, dt)
	update_beams(&gs.beams, dt)
	update_particles(&gs.particles, dt)
	update_bullets(&gs.bullets, dt)
	collide_bullets_player(&gs.bullets, &gs.player)

	rl.BeginTextureMode(gs.render_target)
	rl.ClearBackground(rl.BLACK)
	draw_background(&gs.background)
	rl.BeginMode2D(gs.camera)
	draw_enemies(&gs.enemies)
	draw_player(&gs.player)
	draw_bullets(&gs.bullets)
	draw_particles(&gs.particles)
	draw_beams(&gs.beams)
	rl.EndMode2D()
	draw_player_hud(&gs.player)
	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	src := rl.Rectangle{0, 0, f32(SCREEN_WIDTH), -f32(SCREEN_HEIGHT)}
	dst := rl.Rectangle {
		gs.offset_x,
		gs.offset_y,
		f32(SCREEN_WIDTH) * gs.scale,
		f32(SCREEN_HEIGHT) * gs.scale,
	}
	rl.DrawTexturePro(gs.render_target.texture, src, dst, {0, 0}, 0, rl.WHITE)
	rl.EndDrawing()
}

shutdown :: proc() {
	unload_enemies(&gs.enemies)
	unload_player(&gs.player)
	unload_background(&gs.background)
	rl.UnloadRenderTexture(gs.render_target)
	rl.CloseWindow()
}

parent_window_size_changed :: proc(w, h: int) {
	gs.window_w = w
	gs.window_h = h
	when ODIN_OS == .JS {
		rl.SetWindowSize(i32(w), i32(h))
	}
	update_screen_scale()
}

set_web_mouse_pos :: proc(x, y: int) {
	gs.mouse_x = x
	gs.mouse_y = y
}

set_web_mouse_down :: proc(down: bool) {
	gs.mouse_down = down
}

get_mouse_game_pos :: proc() -> rl.Vector2 {
	wx, wy: f32
	when ODIN_OS == .JS {
		wx = f32(gs.mouse_x)
		wy = f32(gs.mouse_y)
	} else {
		m := rl.GetMousePosition()
		wx = m.x
		wy = m.y
	}
	if gs.scale <= 0 {
		return {0, 0}
	}
	return rl.Vector2{(wx - gs.offset_x) / gs.scale, (wy - gs.offset_y) / gs.scale}
}

update_screen_scale :: proc() {
	sx := f32(gs.window_w) / f32(SCREEN_WIDTH)
	sy := f32(gs.window_h) / f32(SCREEN_HEIGHT)
	gs.scale = min(sx, sy)
	gs.offset_x = (f32(gs.window_w) - f32(SCREEN_WIDTH) * gs.scale) * 0.5
	gs.offset_y = (f32(gs.window_h) - f32(SCREEN_HEIGHT) * gs.scale) * 0.5
}
