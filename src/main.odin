package game

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

Game_State :: struct {
	render_target:      rl.RenderTexture2D,
	camera:             rl.Camera2D,
	audio:              Audio,
	background:         Background,
	player:             Player,
	enemies:            Enemy_Pool,
	sneaks:             Sneak_Pool,
	boss:               Boss_Pool,
	pillars:            Pillar_Wave,
	healthpacks:        HealthPack_Pool,
	bullets:            Bullet_Pool,
	beams:              Beam_Pool,
	missiles:           Missile_Pool,
	particles:          Particle_Pool,
	window_w:           int,
	window_h:           int,
	scale:              f32,
	offset_x:           f32,
	offset_y:           f32,
	mouse_x:            int,
	mouse_y:            int,
	mouse_down:         bool,
	score:              int,
	level:              int,
	transitioning:      bool,
	transition_t:       f32,
	transition_swapped: bool,
	running:            bool,
	victory:            bool,
	choosing_upgrade:   bool,
	// Up to 3 distinct upgrades sampled from the player's available pool at the
	// end of each level. upgrade_cursor indexes into upgrade_choices, not the
	// Player_Upgrade enum, since the offered set changes between levels.
	upgrade_choices:      [3]Player_Upgrade,
	upgrade_choice_count: int,
	upgrade_cursor:       int,
	paused:             bool,
	pause:              Pause_Menu,
	dialogue:           Dialogue,
	in_menu:            bool,
	main_menu:          Main_Menu,
	pending_action:     Pending_Action,
	mission_title:      Mission_Title,
}

// What the transition fade resolves to at its midpoint. Lets the same fade
// state machine cover both menu->gameplay (Begin) and level->level (Advance).
Pending_Action :: enum {
	None,
	Start_Game,
	Advance_Mission,
}

@(private = "file")
gs: Game_State

init :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "bullethell")
	rl.SetTargetFPS(60)

	load_gamepad_mappings()
	init_input_hints()

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

	gs.level = 1
	init_audio(&gs.audio)
	init_background(&gs.background)
	init_player(&gs.player)
	init_enemies(&gs.enemies)
	init_sneaks(&gs.sneaks)
	init_boss(&gs.boss)
	init_pillars(&gs.pillars)
	init_healthpacks(&gs.healthpacks)
	init_dialogue(&gs.dialogue)

	gs.in_menu = true
	reset_main_menu(&gs.main_menu)

	gs.running = true
}

// Resets per-run gameplay state without reloading textures or shaders, so the
// main menu can hand back into a fresh run. Mirrors what init() used to do
// inline below the texture loads.
@(private = "file")
start_new_game :: proc() {
	gs.level = 1
	gs.score = 0
	gs.victory = false
	gs.transitioning = false
	gs.transition_t = 0
	gs.transition_swapped = false
	gs.choosing_upgrade = false
	gs.upgrade_choice_count = 0
	gs.upgrade_cursor = 0

	reset_player_for_new_game(&gs.player)

	clear_world()
	gs.enemies.level = 1
	gs.enemies.waves_cleared = 0
	gs.enemies.fire_interval = ENEMY_FIRE_INTERVAL
	gs.enemies.boost_applied = false
	gs.enemies.level2_waves_complete = 0
	gs.enemies.level4_waves_complete = 0
	gs.sneaks.level = 1
	gs.boss.boss.active = false
	gs.boss.boss.defeated = false

	spawn_wave(&gs.enemies)
	set_background_level(&gs.background, 1)
	play_gameplay_music(&gs.audio)

	gs.dialogue.intro_done = false
	gs.dialogue.wave2_intro_done = false
	start_level1_intro(&gs.dialogue)
	show_mission_title(&gs.mission_title, gs.level)

	gs.in_menu = false
}

@(private = "file")
return_to_main_menu :: proc() {
	gs.paused = false
	gs.victory = false
	gs.transitioning = false
	gs.transition_t = 0
	gs.transition_swapped = false
	gs.choosing_upgrade = false
	gs.upgrade_choice_count = 0
	gs.dialogue.active = false
	gs.mission_title.active = false
	gs.pending_action = .None
	clear_world()
	stop_rapid_fire_sfx(&gs.audio)
	stop_charging_beam_sfx(&gs.audio)
	stop_golgotha_bullet_hell_sfx(&gs.audio)
	play_gameplay_music(&gs.audio)
	set_background_level(&gs.background, 1)
	gs.in_menu = true
	reset_main_menu(&gs.main_menu)
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

	update_audio(&gs.audio)

	when ODIN_OS != .JS {
		if rl.IsWindowResized() {
			gs.window_w = int(rl.GetScreenWidth())
			gs.window_h = int(rl.GetScreenHeight())
			update_screen_scale()
		}
	}

	dt := rl.GetFrameTime()

	input_track_device()

	// Transition state machine runs above the menu/gameplay split so the same
	// fade can span Begin (menu->gameplay) and Advance (level->level).
	if gs.transitioning {
		gs.transition_t += dt
		if !gs.transition_swapped && gs.transition_t >= TRANSITION_HALF_DUR {
			switch gs.pending_action {
			case .None:
			case .Start_Game:
				start_new_game()
			case .Advance_Mission:
				advance_to_next_mission()
			}
			gs.transition_swapped = true
			gs.pending_action = .None
		}
		if gs.transition_t >= 2 * TRANSITION_HALF_DUR {
			gs.transitioning = false
			gs.transition_t = 0
		}
	}

	if gs.in_menu {
		// Background still scrolls under the menu so the title screen feels alive.
		update_background(&gs.background, dt)
		// Lock menu inputs while a Begin fade is mid-flight.
		if !gs.transitioning {
			begin_game := false
			quit_app := false
			update_main_menu(&gs.main_menu, &begin_game, &quit_app, &gs.audio)
			if begin_game {
				gs.transitioning = true
				gs.transition_t = 0
				gs.transition_swapped = false
				gs.pending_action = .Start_Game
			} else if quit_app {
				gs.running = false
			}
		}
		draw_menu_frame()
		return
	}

	// Pause toggle is handled here (when not paused) and inside update_pause
	// (when paused). Tracking just_opened keeps the same ESC press from both
	// opening and immediately closing the menu on the same frame.
	just_opened_pause := false
	if !gs.paused {
		if input_pause_toggle_pressed() && !gs.victory && !gs.transitioning {
			gs.paused = true
			reset_pause_menu(&gs.pause)
			just_opened_pause = true
		}
	}
	quit_to_menu := false
	if gs.paused && !just_opened_pause {
		update_pause(&gs.pause, &gs.paused, &quit_to_menu, &gs.audio)
	}
	if quit_to_menu {
		return_to_main_menu()
		draw_menu_frame()
		return
	}

	if !gs.paused {
		if gs.boss.boss.defeated && !gs.victory {
			gs.victory = true
			clear_world()
			open_upgrade_choice()
			play_victory_music(&gs.audio)
		}

		// Level 2 has no boss yet; victory triggers once the scripted phase sequence
		// has been cleared LEVEL2_WAVES_TO_VICTORY times. Rewards / level 3 are TBD.
		if gs.level == 2 &&
		   gs.enemies.level2_waves_complete >= LEVEL2_WAVES_TO_VICTORY &&
		   !gs.victory {
			gs.victory = true
			clear_world()
			open_upgrade_choice()
			play_victory_music(&gs.audio)
		}

		// Level 4 mirrors the level-2 wave-count gate; no boss, just the four
		// scripted alternating waves.
		if gs.level == 4 &&
		   gs.enemies.level4_waves_complete >= LEVEL4_WAVES_TO_VICTORY &&
		   !gs.victory {
			gs.victory = true
			clear_world()
			open_upgrade_choice()
			play_victory_music(&gs.audio)
		}

		if gs.victory && gs.choosing_upgrade {
			n := gs.upgrade_choice_count
			step := input_menu_step_x()
			if step != 0 && n > 0 {
				gs.upgrade_cursor = (gs.upgrade_cursor + step + n) % n
			}
			if input_confirm_pressed() && n > 0 {
				gs.player.upgrades += {gs.upgrade_choices[gs.upgrade_cursor]}
				gs.choosing_upgrade = false
			}
		} else if gs.victory &&
		   !gs.transitioning &&
		   gs.level < MAX_LEVEL &&
		   input_confirm_pressed() {
			gs.transitioning = true
			gs.transition_t = 0
			gs.transition_swapped = false
			gs.pending_action = .Advance_Mission
		}

		update_mission_title(&gs.mission_title, dt)

		// Boss-driven world freeze (Morgan inter-phase pause): nothing but the
		// boss ticks — HP refill animates and player input is ignored. Treated
		// the same as victory/transition for slow-time + gameplay gating.
		boss_pausing := boss_phase_pausing(&gs.boss.boss)

		// Slow-time only ticks during gameplay; outside gameplay world_dt = dt so
		// the background scroll and timers run at full speed.
		world_dt := dt
		if !gs.victory && !gs.transitioning && !boss_pausing && !gs.dialogue.active {
			world_dt = update_slow_time(&gs.player, dt)
		}

		// Background keeps scrolling during victory + transition + dialogue so the
		// world looks alive even while gameplay is frozen.
		update_background(&gs.background, world_dt)

		if gs.dialogue.active {
			update_dialogue(&gs.dialogue, dt)
		}

		// Pre-wave hint scenes. Triggered before update_enemies sees the empty
		// pool and spawns the next wave, so wave 2 grunts don't pop in mid-screen
		// while the dialogue is up.
		maybe_trigger_pre_wave_dialogue()

		if !gs.victory && !gs.transitioning && !gs.dialogue.active {
			if boss_pausing {
				update_boss(&gs.boss, &gs.bullets, &gs.sneaks, dt)
			} else {
				if input_shrink_bomb_pressed() {
					deploy_shrink_bomb(&gs.player, &gs.bullets, &gs.particles, &gs.audio)
				}
				update_player(&gs.player, &gs.missiles, &gs.audio, dt)
				update_level2_pacing(&gs.enemies, &gs.sneaks, world_dt)
				update_level4_pacing(&gs.enemies, &gs.pillars, world_dt)
				update_enemies(&gs.enemies, &gs.boss, &gs.bullets, &gs.player, world_dt)
				update_sneaks(&gs.sneaks, &gs.player, &gs.bullets, world_dt)
				update_boss(&gs.boss, &gs.bullets, &gs.sneaks, world_dt)
				update_pillars(&gs.pillars, &gs.bullets, world_dt)
				update_player_attack(
					&gs.player,
					&gs.beams,
					&gs.bullets,
					&gs.enemies,
					&gs.sneaks,
					&gs.boss,
					&gs.pillars,
					&gs.healthpacks,
					&gs.particles,
					&gs.audio,
					&gs.score,
					dt,
				)
				update_beams(&gs.beams, dt)
				collide_beams_enemies(
					&gs.beams,
					&gs.enemies,
					&gs.sneaks,
					&gs.boss,
					&gs.pillars,
					&gs.healthpacks,
					&gs.particles,
					&gs.score,
				)
				update_missiles(
					&gs.missiles,
					&gs.enemies,
					&gs.sneaks,
					&gs.boss,
					&gs.pillars,
					&gs.healthpacks,
					&gs.particles,
					&gs.score,
					dt,
				)
				update_particles(&gs.particles, world_dt)
				update_bullets(&gs.bullets, &gs.enemies, &gs.sneaks, &gs.boss, &gs.pillars, dt, world_dt)
				collide_bullets_player(&gs.bullets, &gs.player, &gs.audio)
				collide_bullets_enemies(
					&gs.bullets,
					&gs.enemies,
					&gs.sneaks,
					&gs.boss,
					&gs.pillars,
					&gs.healthpacks,
					&gs.particles,
					&gs.score,
				)
				update_healthpacks(&gs.healthpacks, &gs.player, world_dt)
			}
		}
	}

	// Golgatha's bullet-hell sfx is a pre-rendered loop tied to boss presence —
	// keep it ticking while she's actively firing, and stop on pause / victory /
	// transition / defeat / Morgan so it never bleeds across screens.
	if gs.boss.boss.active &&
	   gs.boss.boss.kind == .Golgatha &&
	   !gs.paused &&
	   !gs.victory &&
	   !gs.transitioning {
		tick_golgotha_bullet_hell_sfx(&gs.audio)
	} else {
		stop_golgotha_bullet_hell_sfx(&gs.audio)
	}

	rl.BeginTextureMode(gs.render_target)
	rl.ClearBackground(rl.BLACK)
	draw_background(&gs.background)
	rl.BeginMode2D(gs.camera)
	draw_enemies(&gs.enemies)
	draw_sneaks(&gs.sneaks)
	draw_boss(&gs.boss)
	draw_pillars(&gs.pillars)
	draw_player(&gs.player)
	draw_bullets(&gs.bullets)
	draw_healthpacks(&gs.healthpacks)
	draw_particles(&gs.particles)
	draw_beams(&gs.beams)
	draw_missiles(&gs.missiles)
	rl.EndMode2D()
	draw_slow_time_tint(&gs.player)
	draw_player_hud(&gs.player)
	draw_boss_hud(&gs.boss)
	draw_score(gs.score)
	if gs.victory {
		draw_victory(gs.level, gs.score, gs.choosing_upgrade, gs.level < MAX_LEVEL)
		if gs.choosing_upgrade {
			draw_upgrade_choice(
				gs.upgrade_choices[:gs.upgrade_choice_count],
				gs.upgrade_cursor,
			)
		}
	}
	draw_mission_title(&gs.mission_title)
	if gs.dialogue.active {
		draw_dialogue(&gs.dialogue)
	}
	if gs.transitioning {
		draw_transition(gs.transition_t)
	}
	if gs.paused {
		draw_pause(&gs.pause, &gs.audio)
	}
	rl.EndTextureMode()

	present_render_target()
}

@(private = "file")
present_render_target :: proc() {
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
	// Hint icons render directly to the window at native resolution so they
	// dodge the render target's POINT upscale and stay readable.
	flush_input_hints(gs.scale, gs.offset_x, gs.offset_y)
	rl.EndDrawing()
}

@(private = "file")
draw_menu_frame :: proc() {
	rl.BeginTextureMode(gs.render_target)
	rl.ClearBackground(rl.BLACK)
	draw_background(&gs.background)
	draw_main_menu(&gs.main_menu, &gs.audio)
	if gs.transitioning {
		draw_transition(gs.transition_t)
	}
	rl.EndTextureMode()
	present_render_target()
}

shutdown :: proc() {
	unload_enemies(&gs.enemies)
	unload_sneaks(&gs.sneaks)
	unload_boss(&gs.boss)
	unload_pillars(&gs.pillars)
	unload_player(&gs.player)
	unload_background(&gs.background)
	unload_audio(&gs.audio)
	unload_dialogue(&gs.dialogue)
	unload_input_hints()
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

@(private = "file")
maybe_trigger_pre_wave_dialogue :: proc() {
	if gs.dialogue.active || gs.victory || gs.transitioning {
		return
	}
	if gs.level != 1 || gs.dialogue.wave2_intro_done {
		return
	}
	// Wait until wave 1 is fully cleared but wave 2 hasn't started spawning yet.
	if gs.enemies.waves_cleared != 0 {
		return
	}
	for i in 0 ..< ENEMY_COUNT {
		if gs.enemies.enemies[i].active {
			return
		}
	}
	start_level1_wave2_intro(&gs.dialogue)
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
	for i in 0 ..< MAX_MISSILES {
		gs.missiles.missiles[i].active = false
	}
	for i in 0 ..< MAX_PARTICLES {
		gs.particles.particles[i].active = false
	}
	for i in 0 ..< HEALTHPACK_MAX {
		gs.healthpacks.packs[i].active = false
	}
	clear_pillars(&gs.pillars)
	// Beam slot the player was charging into is now inactive; reset attack state.
	gs.player.charging = false
	gs.player.charge_beam_idx = -1
	gs.player.charge = 0
}

draw_score :: proc(score: int) {
	text := fmt.ctprintf("SCORE: %d", score)
	rl.DrawText(text, HP_BAR_MARGIN, HP_BAR_MARGIN, SCORE_FONT_SIZE, rl.WHITE)
}

draw_victory :: proc(level: int, score: int, choosing: bool, has_next: bool) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, VICTORY_OVERLAY_ALPHA})

	// While the upgrade picker is up, the title/score sit higher to leave room
	// for the two upgrade cards beneath them.
	mid_y: i32 = SCREEN_HEIGHT / 2 - VICTORY_TITLE_FONT_SIZE
	if choosing {
		mid_y = UPGRADE_TITLE_Y
	}

	title := fmt.ctprintf("MISSION %d COMPLETE", level)
	title_w := rl.MeasureText(title, VICTORY_TITLE_FONT_SIZE)
	title_x: i32 = (SCREEN_WIDTH - title_w) / 2
	title_y: i32 = mid_y
	rl.DrawText(title, title_x + 2, title_y + 2, VICTORY_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, title_x, title_y, VICTORY_TITLE_FONT_SIZE, rl.WHITE)

	score_text := fmt.ctprintf("SCORE: %d", score)
	score_w := rl.MeasureText(score_text, VICTORY_SCORE_FONT_SIZE)
	score_x: i32 = (SCREEN_WIDTH - score_w) / 2
	score_y: i32 = title_y + VICTORY_TITLE_FONT_SIZE + 12
	rl.DrawText(score_text, score_x + 1, score_y + 1, VICTORY_SCORE_FONT_SIZE, rl.BLACK)
	rl.DrawText(score_text, score_x, score_y, VICTORY_SCORE_FONT_SIZE, rl.YELLOW)

	if choosing || !has_next {
		return
	}

	pre := cstring("PRESS")
	tail := fmt.ctprintf("FOR MISSION %d", level + 1)
	pre_w := rl.MeasureText(pre, VICTORY_PROMPT_FONT_SIZE)
	tail_w := rl.MeasureText(tail, VICTORY_PROMPT_FONT_SIZE)
	icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	total_w := pre_w + HINT_TEXT_GAP + icon_w + HINT_TEXT_GAP + tail_w
	prompt_x: i32 = (SCREEN_WIDTH - total_w) / 2
	prompt_y: i32 = score_y + VICTORY_SCORE_FONT_SIZE + 16
	icon_y := prompt_y + (VICTORY_PROMPT_FONT_SIZE - HINT_ICON_SIZE) / 2
	rl.DrawText(pre, prompt_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(pre, prompt_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
	icon_x := prompt_x + pre_w + HINT_TEXT_GAP
	draw_input_hint(.Confirm, icon_x, icon_y, HINT_ICON_SIZE)
	tail_x := icon_x + icon_w + HINT_TEXT_GAP
	rl.DrawText(tail, tail_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(tail, tail_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
}

draw_upgrade_choice :: proc(choices: []Player_Upgrade, cursor: int) {
	n := i32(len(choices))
	if n == 0 {
		return
	}

	header := cstring("CHOOSE YOUR UPGRADE")
	hw := rl.MeasureText(header, UPGRADE_HEADER_FONT_SIZE)
	hx := (i32(SCREEN_WIDTH) - hw) / 2
	rl.DrawText(header, hx + 1, UPGRADE_HEADER_Y + 1, UPGRADE_HEADER_FONT_SIZE, rl.BLACK)
	rl.DrawText(header, hx, UPGRADE_HEADER_Y, UPGRADE_HEADER_FONT_SIZE, rl.WHITE)

	gap: i32 = UPGRADE_CARD_GAP
	total_w: i32 = UPGRADE_CARD_W * n + gap * (n - 1)
	left_x: i32 = (i32(SCREEN_WIDTH) - total_w) / 2

	for c, i in choices {
		x := left_x + i32(i) * (UPGRADE_CARD_W + gap)
		name, cue, line1, line2, accent := upgrade_card_info(c)
		draw_upgrade_card(
			x,
			UPGRADE_CARDS_Y,
			c,
			name,
			cue,
			line1,
			line2,
			accent,
			cursor == i,
		)
	}

	// "[step icon] PICK    [confirm icon] CONFIRM" — same layout for kb/gp,
	// just different icons.
	pick := cstring("PICK")
	confirm := cstring("CONFIRM")
	step_icon_w := input_hint_width(.Menu_Step_Horizontal, HINT_ICON_SIZE)
	confirm_icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	pick_w := rl.MeasureText(pick, VICTORY_PROMPT_FONT_SIZE)
	confirm_w := rl.MeasureText(confirm, VICTORY_PROMPT_FONT_SIZE)
	section_gap: i32 = 16
	hint_total :=
		step_icon_w +
		HINT_TEXT_GAP +
		pick_w +
		section_gap +
		confirm_icon_w +
		HINT_TEXT_GAP +
		confirm_w
	hint_x: i32 = (i32(SCREEN_WIDTH) - hint_total) / 2
	hint_y: i32 = UPGRADE_CARDS_Y + UPGRADE_CARD_H + 10
	icon_y := hint_y + (VICTORY_PROMPT_FONT_SIZE - HINT_ICON_SIZE) / 2

	cursor := hint_x
	draw_input_hint(.Menu_Step_Horizontal, cursor, icon_y, HINT_ICON_SIZE)
	cursor += step_icon_w + HINT_TEXT_GAP
	rl.DrawText(pick, cursor + 1, hint_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(pick, cursor, hint_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
	cursor += pick_w + section_gap
	draw_input_hint(.Confirm, cursor, icon_y, HINT_ICON_SIZE)
	cursor += confirm_icon_w + HINT_TEXT_GAP
	rl.DrawText(confirm, cursor + 1, hint_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(confirm, cursor, hint_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
}

@(private = "file")
upgrade_card_info :: proc(
	u: Player_Upgrade,
) -> (
	name: cstring,
	cue: cstring,
	line1: cstring,
	line2: cstring,
	accent: rl.Color,
) {
	switch u {
	case .Slow_Time:
		// cue text alone is "HOLD"; draw_upgrade_card appends the slow-time
		// icon (SHIFT / LT) so the prompt matches the player's active device.
		return "SLOW TIME",
			"HOLD",
			"BENDS WORLD TO HALF SPEED",
			"DRAINS STAMINA WHILE HELD",
			rl.Color{80, 180, 255, 255}
	case .Dash_Frenzy:
		return "DASH FRENZY",
			"ON DASH",
			"FIRES 2 HOMING MISSILES (8 DMG)",
			"+2 STAMINA PER DASH",
			rl.Color{200, 110, 255, 255}
	case .Rapid_Fire:
		return "RAPID FIRE",
			"HOLD ATTACK",
			"REPLACES LASER WITH BULLETS",
			"AUTOFIRE STRAIGHT UP",
			rl.Color{255, 80, 80, 255}
	case .Beam_Blast:
		return "BEAM BLAST",
			"HOLD ATTACK",
			"5-WAY LASER SPREAD (20 DEG)",
			"RANGE REDUCED BY 50%",
			rl.Color{255, 200, 80, 255}
	case .Riposte:
		return "RIPOSTE",
			"ON DEFLECT",
			"DEFLECTED BULLETS AUTO-TRACK",
			"THE ENEMY THAT FIRED THEM",
			rl.Color{160, 220, 255, 255}
	case .Lucky_Shot:
		return "LUCKY SHOT",
			"ON DASH",
			"YOU GAIN ONE MORE DASH MISSILE",
			"AT NO EXTRA STAMINA COST",
			rl.Color{255, 220, 120, 255}
	}
	return
}

// Builds the upgrade pool from {all upgrades} - {already owned}, with the
// Rapid_Fire <-> Beam_Blast mutex applied. Samples up to 3 distinct upgrades
// without replacement and switches into the choosing-upgrade state. If the
// pool is empty (all relevant upgrades owned) the picker is skipped entirely.
@(private = "file")
open_upgrade_choice :: proc() {
	pool: [6]Player_Upgrade
	n := 0
	for u in Player_Upgrade {
		if u in gs.player.upgrades {
			continue
		}
		if u == .Rapid_Fire && .Beam_Blast in gs.player.upgrades {
			continue
		}
		if u == .Beam_Blast && .Rapid_Fire in gs.player.upgrades {
			continue
		}
		// Lucky Shot only matters with Dash Frenzy — don't offer it before then.
		if u == .Lucky_Shot && .Dash_Frenzy not_in gs.player.upgrades {
			continue
		}
		pool[n] = u
		n += 1
	}
	if n == 0 {
		gs.choosing_upgrade = false
		gs.upgrade_choice_count = 0
		return
	}
	// Fisher-Yates: only the first `take` slots need to be uniformly random,
	// so partial-shuffle and stop early.
	take := min(len(gs.upgrade_choices), n)
	for i in 0 ..< take {
		j := i + int(rand.uint32() % u32(n - i))
		pool[i], pool[j] = pool[j], pool[i]
	}
	for i in 0 ..< take {
		gs.upgrade_choices[i] = pool[i]
	}
	gs.upgrade_choice_count = take
	gs.upgrade_cursor = 0
	gs.choosing_upgrade = true
}

@(private = "file")
draw_upgrade_card :: proc(
	x, y: i32,
	upgrade: Player_Upgrade,
	name: cstring,
	cue: cstring,
	line1: cstring,
	line2: cstring,
	accent: rl.Color,
	selected: bool,
) {
	bg := rl.Color{12, 12, 20, 230}
	rl.DrawRectangle(x, y, UPGRADE_CARD_W, UPGRADE_CARD_H, bg)

	border := rl.Color{80, 80, 100, 255}
	thickness: i32 = 1
	if selected {
		border = accent
		thickness = 2
	}
	for t: i32 = 0; t < thickness; t += 1 {
		rl.DrawRectangleLines(x - t, y - t, UPGRADE_CARD_W + 2 * t, UPGRADE_CARD_H + 2 * t, border)
	}

	name_w := rl.MeasureText(name, UPGRADE_NAME_FONT_SIZE)
	nx := x + (UPGRADE_CARD_W - name_w) / 2
	ny := y + 8
	rl.DrawText(name, nx + 1, ny + 1, UPGRADE_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, nx, ny, UPGRADE_NAME_FONT_SIZE, accent)

	cue_text_w := rl.MeasureText(cue, UPGRADE_BODY_FONT_SIZE)
	icon_w: i32 = 0
	if upgrade == .Slow_Time {
		icon_w = input_hint_width(.Slow_Time, HINT_ICON_SIZE) + HINT_TEXT_GAP
	}
	cx := x + (UPGRADE_CARD_W - (cue_text_w + icon_w)) / 2
	cy := ny + UPGRADE_NAME_FONT_SIZE + 6
	rl.DrawText(cue, cx, cy, UPGRADE_BODY_FONT_SIZE, rl.Color{200, 200, 200, 255})
	if upgrade == .Slow_Time {
		icon_y := cy + (UPGRADE_BODY_FONT_SIZE - HINT_ICON_SIZE) / 2
		draw_input_hint(.Slow_Time, cx + cue_text_w + HINT_TEXT_GAP, icon_y, HINT_ICON_SIZE)
	}

	l1_w := rl.MeasureText(line1, UPGRADE_BODY_FONT_SIZE)
	l1x := x + (UPGRADE_CARD_W - l1_w) / 2
	l1y := cy + UPGRADE_BODY_FONT_SIZE + 8
	rl.DrawText(line1, l1x, l1y, UPGRADE_BODY_FONT_SIZE, rl.WHITE)

	l2_w := rl.MeasureText(line2, UPGRADE_BODY_FONT_SIZE)
	l2x := x + (UPGRADE_CARD_W - l2_w) / 2
	l2y := l1y + UPGRADE_BODY_FONT_SIZE + 4
	rl.DrawText(line2, l2x, l2y, UPGRADE_BODY_FONT_SIZE, rl.Color{220, 220, 220, 255})
}

advance_to_next_mission :: proc() {
	gs.level += 1
	gs.victory = false
	play_gameplay_music(&gs.audio)
	set_background_level(&gs.background, gs.level)
	clear_world()
	// Boss flag reset so a level-2 boss can later trigger the victory branch again.
	// waves_cleared is intentionally left past BOSS_TRIGGER_WAVE — keeps grunt waves
	// flowing without re-spawning Golgatha.
	gs.boss.boss.defeated = false
	gs.boss.boss.active = false
	gs.sneaks.level = gs.level
	gs.enemies.level = gs.level
	if gs.level == 2 {
		reset_level2_pacing(&gs.enemies, &gs.sneaks)
	}
	if gs.level == 3 {
		spawn_morgan(&gs.boss)
	}
	if gs.level == 4 {
		reset_level4_pacing(&gs.enemies)
	}
	if gs.level == 5 {
		spawn_ancient_guardian(&gs.boss)
	}
	gs.player.hp = PLAYER_MAX_HP
	gs.player.shrink_bombs = SHRINK_BOMBS_PER_LEVEL
	show_mission_title(&gs.mission_title, gs.level)
}

draw_transition :: proc(t: f32) {
	half := f32(TRANSITION_HALF_DUR)
	f: f32
	if t < half {
		f = smoothstep(t / half)
	} else {
		f = 1 - smoothstep((t - half) / half)
	}
	if f < 0 {
		f = 0
	}
	if f > 1 {
		f = 1
	}
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, u8(f * 255)})
}

smoothstep :: proc(t: f32) -> f32 {
	if t <= 0 {
		return 0
	}
	if t >= 1 {
		return 1
	}
	return t * t * (3 - 2 * t)
}

update_screen_scale :: proc() {
	sx := f32(gs.window_w) / f32(SCREEN_WIDTH)
	sy := f32(gs.window_h) / f32(SCREEN_HEIGHT)
	gs.scale = min(sx, sy)
	gs.offset_x = (f32(gs.window_w) - f32(SCREEN_WIDTH) * gs.scale) * 0.5
	gs.offset_y = (f32(gs.window_h) - f32(SCREEN_HEIGHT) * gs.scale) * 0.5
}
