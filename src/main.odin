package game

import "core:fmt"
import rl "vendor:raylib"

Game_State :: struct {
	render_target: rl.RenderTexture2D,
	camera:        rl.Camera2D,
	background:    Background,
	player:        Player,
	enemies:       Enemy_Pool,
	sneaks:        Sneak_Pool,
	boss:          Boss_Pool,
	healthpacks:   HealthPack_Pool,
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
	score:         int,
	running:       bool,
	victory:       bool,
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
	init_sneaks(&gs.sneaks)
	init_boss(&gs.boss)
	init_healthpacks(&gs.healthpacks)

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

	if gs.boss.boss.defeated && !gs.victory {
		gs.victory = true
		clear_world()
	}

	if !gs.victory {
		update_background(&gs.background, dt)
		update_player(&gs.player, dt)
		update_enemies(&gs.enemies, &gs.boss, &gs.bullets, dt)
		update_sneaks(&gs.sneaks, &gs.player, &gs.bullets, dt)
		update_boss(&gs.boss, &gs.bullets, &gs.sneaks, dt)
		update_player_attack(
			&gs.player,
			&gs.beams,
			&gs.enemies,
			&gs.sneaks,
			&gs.boss,
			&gs.healthpacks,
			&gs.particles,
			&gs.score,
			dt,
		)
		update_beams(&gs.beams, dt)
		update_particles(&gs.particles, dt)
		update_bullets(&gs.bullets, &gs.enemies, &gs.sneaks, &gs.boss, dt)
		collide_bullets_player(&gs.bullets, &gs.player)
		collide_bullets_enemies(
			&gs.bullets,
			&gs.enemies,
			&gs.sneaks,
			&gs.boss,
			&gs.healthpacks,
			&gs.particles,
			&gs.score,
		)
		update_healthpacks(&gs.healthpacks, &gs.player, dt)
	}

	rl.BeginTextureMode(gs.render_target)
	rl.ClearBackground(rl.BLACK)
	draw_background(&gs.background)
	rl.BeginMode2D(gs.camera)
	draw_enemies(&gs.enemies)
	draw_sneaks(&gs.sneaks)
	draw_boss(&gs.boss)
	draw_player(&gs.player)
	draw_bullets(&gs.bullets)
	draw_healthpacks(&gs.healthpacks)
	draw_particles(&gs.particles)
	draw_beams(&gs.beams)
	rl.EndMode2D()
	draw_player_hud(&gs.player)
	draw_boss_hud(&gs.boss)
	draw_score(gs.score)
	if gs.victory {
		draw_victory(gs.score)
	}
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
	unload_sneaks(&gs.sneaks)
	unload_boss(&gs.boss)
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

clear_world :: proc() {
	for i in 0 ..< ENEMY_COUNT {
		gs.enemies.enemies[i].active = false
	}
	for i in 0 ..< SNEAK_MAX {
		gs.sneaks.sneaks[i].active = false
	}
	for i in 0 ..< MAX_BULLETS {
		gs.bullets.bullets[i].active = false
	}
	for i in 0 ..< MAX_BEAMS {
		gs.beams.beams[i].active = false
	}
	for i in 0 ..< MAX_PARTICLES {
		gs.particles.particles[i].active = false
	}
	for i in 0 ..< HEALTHPACK_MAX {
		gs.healthpacks.packs[i].active = false
	}
	// Beam slot the player was charging into is now inactive; reset attack state.
	gs.player.charging = false
	gs.player.charge_beam_idx = -1
	gs.player.charge = 0
}

draw_score :: proc(score: int) {
	text := fmt.ctprintf("SCORE: %d", score)
	rl.DrawText(text, HP_BAR_MARGIN, HP_BAR_MARGIN, SCORE_FONT_SIZE, rl.WHITE)
}

draw_victory :: proc(score: int) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, VICTORY_OVERLAY_ALPHA})

	title: cstring = VICTORY_TITLE
	title_w := rl.MeasureText(title, VICTORY_TITLE_FONT_SIZE)
	title_x: i32 = (SCREEN_WIDTH - title_w) / 2
	title_y: i32 = SCREEN_HEIGHT / 2 - VICTORY_TITLE_FONT_SIZE
	rl.DrawText(title, title_x + 2, title_y + 2, VICTORY_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, title_x, title_y, VICTORY_TITLE_FONT_SIZE, rl.WHITE)

	score_text := fmt.ctprintf("FINAL SCORE: %d", score)
	score_w := rl.MeasureText(score_text, VICTORY_SCORE_FONT_SIZE)
	score_x: i32 = (SCREEN_WIDTH - score_w) / 2
	score_y: i32 = title_y + VICTORY_TITLE_FONT_SIZE + 12
	rl.DrawText(score_text, score_x + 1, score_y + 1, VICTORY_SCORE_FONT_SIZE, rl.BLACK)
	rl.DrawText(score_text, score_x, score_y, VICTORY_SCORE_FONT_SIZE, rl.YELLOW)
}

update_screen_scale :: proc() {
	sx := f32(gs.window_w) / f32(SCREEN_WIDTH)
	sy := f32(gs.window_h) / f32(SCREEN_HEIGHT)
	gs.scale = min(sx, sy)
	gs.offset_x = (f32(gs.window_w) - f32(SCREEN_WIDTH) * gs.scale) * 0.5
	gs.offset_y = (f32(gs.window_h) - f32(SCREEN_HEIGHT) * gs.scale) * 0.5
}
