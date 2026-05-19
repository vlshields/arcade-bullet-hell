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
	level:              int,
	transitioning:      bool,
	transition_t:       f32,
	transition_swapped: bool,
	running:            bool,
	victory:            bool,
	victory_pending:    bool,
	victory_delay_t:    f32,
	choosing_upgrade:   bool,
	// Up to 3 distinct upgrades sampled from the player's available pool at the
	// end of each level. upgrade_cursor indexes into upgrade_choices, not the
	// Player_Upgrade enum, since the offered set changes between levels.
	upgrade_choices:      [3]Player_Upgrade,
	upgrade_choice_count: int,
	upgrade_cursor:       int,
	// Per-run reroll budget for the upgrade picker. Resets to UPGRADE_REROLLS_PER_RUN
	// on start_new_game; decrements each time the player reshuffles the cards.
	rerolls_remaining:    int,
	paused:             bool,
	pause:              Pause_Menu,
	show_timer:         bool,
	run_time:           f32,
	dialogue:           Dialogue,
	in_menu:            bool,
	main_menu:          Main_Menu,
	pending_action:     Pending_Action,
	mission_title:      Mission_Title,
	// Death state. game_over_t accumulates real seconds since the player's HP
	// hit 0 and drives the title's easing-in animation + the confirm-input gate.
	game_over:          bool,
	game_over_t:        f32,
}

// What the transition fade resolves to at its midpoint. Lets the same fade
// state machine cover both menu->gameplay (Begin) and level->level (Advance).
Pending_Action :: enum {
	None,
	Start_Game,
	Advance_Mission,
	Reroll_Upgrade,
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
	init_bullets(&gs.bullets)
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
	gs.run_time = 0
	gs.victory = false
	gs.victory_pending = false
	gs.victory_delay_t = 0
	gs.transitioning = false
	gs.transition_t = 0
	gs.transition_swapped = false
	gs.choosing_upgrade = false
	gs.upgrade_choice_count = 0
	gs.upgrade_cursor = 0
	gs.rerolls_remaining = UPGRADE_REROLLS_PER_RUN
	gs.game_over = false
	gs.game_over_t = 0

	reset_player_for_new_game(&gs.player)

	clear_world()
	gs.enemies.level = 1
	gs.enemies.waves_cleared = 0
	gs.enemies.fire_interval = ENEMY_FIRE_INTERVAL
	gs.enemies.boost_applied = false
	gs.enemies.level2_waves_complete = 0
	gs.enemies.level4_waves_complete = 0
	gs.sneaks.level = 1
	// Suppress level-1 kill-drop sneaks until the wave-2 intro plays — they'd
	// otherwise be alive and shooting under the dialogue box.
	gs.sneaks.spawn_chance_scale = 0
	gs.boss.boss.active = false
	gs.boss.boss.defeated = false

	spawn_wave(&gs.enemies)
	set_background_level(&gs.background, 1)
	play_track(&gs.audio, gameplay_track_for_level(gs.level))

	gs.dialogue.intro_done = false
	gs.dialogue.wave2_intro_done = false
	gs.dialogue.boss_intro_done = false
	gs.dialogue.l2_intro_done = false
	gs.dialogue.l4_intro_done = false
	gs.dialogue.l4_pillars_intro_done = false
	gs.dialogue.l5_guardian_intro_done = false
	start_level1_intro(&gs.dialogue)
	show_mission_title(&gs.mission_title, gs.level)

	gs.in_menu = false
}

@(private = "file")
return_to_main_menu :: proc() {
	gs.paused = false
	gs.victory = false
	gs.victory_pending = false
	gs.victory_delay_t = 0
	gs.transitioning = false
	gs.transition_t = 0
	gs.transition_swapped = false
	gs.choosing_upgrade = false
	gs.upgrade_choice_count = 0
	gs.game_over = false
	gs.game_over_t = 0
	gs.dialogue.active = false
	gs.mission_title.active = false
	gs.pending_action = .None
	clear_world()
	stop_rapid_fire_sfx(&gs.audio)
	stop_charging_beam_sfx(&gs.audio)
	stop_golgotha_bullet_hell_sfx(&gs.audio)
	stop_morgan_chatter_sfx(&gs.audio)
	play_track(&gs.audio, .Main_Menu)
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
			case .Reroll_Upgrade:
				gs.rerolls_remaining -= 1
				open_upgrade_choice()
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
		if input_pause_toggle_pressed() && !gs.victory && !gs.transitioning && !gs.game_over {
			gs.paused = true
			reset_pause_menu(&gs.pause)
			just_opened_pause = true
		}
	}
	quit_to_menu := false
	if gs.paused && !just_opened_pause {
		update_pause(&gs.pause, &gs.paused, &quit_to_menu, &gs.audio, &gs.show_timer)
	}
	if quit_to_menu {
		return_to_main_menu()
		draw_menu_frame()
		return
	}

	if !gs.paused && !gs.victory && !gs.game_over {
		gs.run_time += dt
	}

	// HP reaching 0 from any damage source freezes gameplay into a death screen.
	// Checked here so the same frame the killing blow lands transitions cleanly,
	// without any further bullet/enemy updates ticking under the overlay.
	if !gs.paused && !gs.game_over && !gs.victory && gs.player.hp <= 0 {
		enter_game_over()
	}

	if !gs.paused && gs.game_over {
		gs.game_over_t += dt
		// Background keeps scrolling under the death overlay so the screen
		// doesn't feel completely frozen.
		update_background(&gs.background, dt)
		if !gs.transitioning &&
		   gs.game_over_t >= GAME_OVER_INPUT_DELAY &&
		   input_confirm_pressed() {
			play_ui_confirm_sfx(&gs.audio)
			return_to_main_menu()
			draw_menu_frame()
			return
		}
	}

	if !gs.paused && !gs.game_over {
		if gs.boss.boss.defeated && !gs.victory && !gs.victory_pending {
			gs.victory_pending = true
			gs.victory_delay_t = VICTORY_DELAY
		}

		// Level 2 has no boss yet; victory triggers once the scripted phase sequence
		// has been cleared LEVEL2_WAVES_TO_VICTORY times. Rewards / level 3 are TBD.
		if gs.level == 2 &&
		   gs.enemies.level2_waves_complete >= LEVEL2_WAVES_TO_VICTORY &&
		   !gs.victory &&
		   !gs.victory_pending {
			gs.victory_pending = true
			gs.victory_delay_t = VICTORY_DELAY
		}

		// Level 4 mirrors the level-2 wave-count gate; no boss, just the four
		// scripted alternating waves.
		if gs.level == 4 &&
		   gs.enemies.level4_waves_complete >= LEVEL4_WAVES_TO_VICTORY &&
		   !gs.victory &&
		   !gs.victory_pending {
			gs.victory_pending = true
			gs.victory_delay_t = VICTORY_DELAY
		}

		// Hold gameplay live for VICTORY_DELAY seconds after the win condition
		// fires so the kill / final-wave clear can register before the upgrade
		// overlay takes the screen.
		if gs.victory_pending && !gs.victory {
			gs.victory_delay_t -= dt
			if gs.victory_delay_t <= 0 {
				gs.victory_pending = false
				gs.victory_delay_t = 0
				gs.victory = true
				clear_world()
				// On the final level, no upgrade picker — go straight to the
				// final victory screen and swap to the victory theme.
				if gs.level >= MAX_LEVEL {
					play_track(&gs.audio, .Final_Victory)
				} else {
					open_upgrade_choice()
				}
			}
		}

		if gs.victory && gs.choosing_upgrade && !gs.transitioning {
			n := gs.upgrade_choice_count
			step := input_menu_step_x()
			if step != 0 && n > 0 {
				gs.upgrade_cursor = (gs.upgrade_cursor + step + n) % n
				play_ui_navigate_sfx(&gs.audio)
			}
			if input_reroll_pressed() && gs.rerolls_remaining > 0 && n > 0 {
				// Decrement + reshuffle land at the fade's midpoint so the old
				// cards fade out, the swap is hidden in black, and the new cards
				// fade in — mirroring the inter-mission transition.
				gs.transitioning = true
				gs.transition_t = 0
				gs.transition_swapped = false
				gs.pending_action = .Reroll_Upgrade
				play_ui_confirm_sfx(&gs.audio)
			}
			if input_confirm_pressed() && n > 0 {
				picked := gs.upgrade_choices[gs.upgrade_cursor]
				gs.player.upgrades += {picked}
				apply_upgrade_stats(&gs.player, picked)
				gs.choosing_upgrade = false
				play_ui_confirm_sfx(&gs.audio)
			}
		} else if gs.victory && !gs.transitioning && input_confirm_pressed() {
			if gs.level < MAX_LEVEL {
				gs.transitioning = true
				gs.transition_t = 0
				gs.transition_swapped = false
				gs.pending_action = .Advance_Mission
				play_ui_confirm_sfx(&gs.audio)
			} else {
				play_ui_confirm_sfx(&gs.audio)
				return_to_main_menu()
				draw_menu_frame()
				return
			}
		}

		update_mission_title(&gs.mission_title, dt)

		// Boss-driven world freeze (Morgan inter-phase pause): nothing but the
		// boss ticks — HP refill animates and player input is ignored. Treated
		// the same as victory/transition for slow-time + gameplay gating.
		boss_pausing := boss_phase_pausing(&gs.boss.boss)

		// Hints flagged pauses_game:false (hint_02, l402, l501, hint_03) overlay
		// live gameplay without freezing the world; modal scenes keep the freeze.
		dialogue_blocking := gs.dialogue.active && gs.dialogue.pauses_game

		// Slow-time only ticks during gameplay; outside gameplay world_dt = dt so
		// the background scroll and timers run at full speed.
		world_dt := dt
		slow_time_audible := false
		if !gs.victory && !gs.transitioning && !boss_pausing && !dialogue_blocking {
			world_dt = update_slow_time(&gs.player, dt)
			slow_time_audible = gs.player.slow_time_active
		}
		set_music_lpf_enabled(&gs.audio, slow_time_audible)

		// Background keeps scrolling during victory + transition + dialogue so the
		// world looks alive even while gameplay is frozen.
		update_background(&gs.background, world_dt)

		if gs.dialogue.active {
			update_dialogue(&gs.dialogue, dt)
		}

		// Restore the level-1 kill-drop sneak chance the moment the wave-2
		// intro is over, so wave 2 onward plays with the original spawn rate.
		if gs.dialogue.wave2_intro_done && !gs.dialogue.active {
			gs.sneaks.spawn_chance_scale = 1
		}

		// Pre-wave hint scenes (wave_id when="before"). Fire before update_enemies
		// sees the empty pool and spawns the next wave, so wave 2 grunts (or the
		// Golgatha boss) don't pop in mid-screen while the dialogue is up.
		maybe_trigger_pre_wave_dialogue()
		maybe_trigger_pre_boss_dialogue()
		maybe_trigger_l4_pillars_dialogue()
		// l501 is wave_id when="during" — fires once the boss is on the field,
		// overlaying live gameplay (non-pausing).
		maybe_trigger_l5_guardian_dialogue()

		// Block kill-drop sneak/cyclops spawns during VICTORY_DELAY so the
		// player finishing off a leftover enemy doesn't seed new spawns that
		// would flash on screen before clear_world fires at end-of-delay.
		gs.sneaks.spawns_blocked = gs.victory_pending

		if !gs.victory && !gs.transitioning && !dialogue_blocking {
			if boss_pausing {
				update_boss(&gs.boss, &gs.bullets, &gs.sneaks, dt)
			} else {
				if input_shrink_bomb_pressed() {
					deploy_shrink_bomb(&gs.player, &gs.bullets, &gs.particles, &gs.audio)
				}
				update_player(&gs.player, &gs.missiles, &gs.audio, dt)
				update_level2_pacing(&gs.enemies, &gs.sneaks, world_dt)
				update_level4_pacing(&gs.enemies, &gs.pillars, world_dt, gs.dialogue.active)
				update_enemies(
					&gs.enemies,
					&gs.boss,
					&gs.bullets,
					&gs.player,
					&gs.audio,
					world_dt,
					gs.dialogue.active,
				)
				update_sneaks(&gs.sneaks, &gs.player, &gs.bullets, &gs.audio, world_dt)
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
					&gs.audio,
				)
				update_missiles(
					&gs.missiles,
					&gs.enemies,
					&gs.sneaks,
					&gs.boss,
					&gs.pillars,
					&gs.healthpacks,
					&gs.particles,
					&gs.audio,
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
					&gs.audio,
				)
				update_healthpacks(&gs.healthpacks, &gs.player, world_dt)
			}

			// Drain the sneak teleport/spawn edge flag once per frame so a
			// burst (kill drops + scheduled teleports) collapses to a single
			// cue instead of layering instances.
			if gs.sneaks.teleport_or_spawn_event {
				play_sneak_teleport_sfx(&gs.audio)
				gs.sneaks.teleport_or_spawn_event = false
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
	   !gs.transitioning &&
	   !gs.game_over {
		if !gs.boss.boss.scream_played {
			play_golgotha_scream_sfx(&gs.audio)
			gs.boss.boss.scream_played = true
		}
		tick_golgotha_bullet_hell_sfx(&gs.audio)
	} else {
		stop_golgotha_bullet_hell_sfx(&gs.audio)
	}

	// Morgan's chatter is intermittent — tick_morgan_chatter_sfx waits out a
	// randomized gap between plays so she mutters rather than looping. Stop on
	// pause / victory / transition / death / inter-phase pause to keep cues
	// aligned with what the player sees.
	morgan_chattering :=
		gs.boss.boss.active &&
		gs.boss.boss.kind == .Morgan &&
		!gs.boss.boss.dying &&
		!boss_phase_pausing(&gs.boss.boss) &&
		!gs.paused &&
		!gs.victory &&
		!gs.transitioning &&
		!gs.game_over
	if morgan_chattering {
		tick_morgan_chatter_sfx(&gs.audio, dt)
	} else {
		stop_morgan_chatter_sfx(&gs.audio)
	}

	// Ancient Guardian audio hooks: layered intro stinger on fight start, plus
	// a random voice cue per orb death (set inside damage_guardian_orb, drained
	// here). Same gate as the Golgatha block so cues don't bleed across pauses.
	if gs.boss.boss.active &&
	   gs.boss.boss.kind == .Ancient_Guardian &&
	   !gs.paused &&
	   !gs.victory &&
	   !gs.transitioning &&
	   !gs.game_over {
		if !gs.boss.boss.intro_played {
			play_guardian_intro_sfx(&gs.audio)
			gs.boss.boss.intro_played = true
		}
		if gs.boss.boss.orb_just_died {
			play_guardian_orb_death_sfx(&gs.audio)
			gs.boss.boss.orb_just_died = false
		}
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
	if gs.show_timer {
		draw_run_timer(gs.run_time)
	}
	if gs.victory {
		draw_victory(gs.level, gs.choosing_upgrade, gs.level < MAX_LEVEL, gs.run_time)
		if gs.choosing_upgrade {
			draw_upgrade_choice(
				gs.upgrade_choices[:gs.upgrade_choice_count],
				gs.upgrade_cursor,
				gs.rerolls_remaining,
			)
		}
	}
	if gs.game_over {
		draw_game_over(gs.game_over_t)
	}
	draw_mission_title(&gs.mission_title)
	if gs.dialogue.active {
		draw_dialogue(&gs.dialogue)
	}
	if gs.transitioning {
		draw_transition(gs.transition_t)
	}
	if gs.paused {
		draw_pause(&gs.pause, &gs.audio, &gs.show_timer)
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
	unload_bullets(&gs.bullets)
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

@(private = "file")
maybe_trigger_pre_boss_dialogue :: proc() {
	if gs.dialogue.active || gs.victory || gs.transitioning {
		return
	}
	if gs.level != 1 || gs.dialogue.boss_intro_done {
		return
	}
	if gs.boss.boss.active || gs.boss.boss.defeated {
		return
	}
	// Mirrors hint_02 wave-2 trigger: fires the frame after the final grunt
	// wave is cleared but before update_enemies bumps waves_cleared and calls
	// spawn_boss. block_next_wave (= gs.dialogue.active) holds the spawn off
	// until the player dismisses the line.
	if gs.enemies.waves_cleared != BOSS_TRIGGER_WAVE - 1 {
		return
	}
	for i in 0 ..< ENEMY_COUNT {
		if gs.enemies.enemies[i].active {
			return
		}
	}
	start_level1_boss_intro(&gs.dialogue)
}

// Fires before the Wave4_Pillars phase actually spawns — the level-4 pacing
// gate (block_next_wave) keeps the pillars off the field until the player
// dismisses the line. Non-pausing so the world keeps breathing under the box.
@(private = "file")
maybe_trigger_l4_pillars_dialogue :: proc() {
	if gs.dialogue.active || gs.victory || gs.transitioning {
		return
	}
	if gs.level != 4 || gs.dialogue.l4_pillars_intro_done {
		return
	}
	if gs.enemies.level4_phase != .Wave4_Pillars {
		return
	}
	if gs.enemies.level4_phase_started {
		return
	}
	start_level4_pillars_intro(&gs.dialogue)
}

@(private = "file")
maybe_trigger_l5_guardian_dialogue :: proc() {
	if gs.dialogue.active || gs.victory || gs.transitioning {
		return
	}
	if gs.level != 5 || gs.dialogue.l5_guardian_intro_done {
		return
	}
	if !gs.boss.boss.active || gs.boss.boss.kind != .Ancient_Guardian {
		return
	}
	start_level5_guardian_intro(&gs.dialogue)
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
	gs.bullets.fire_suppress_timer = 0
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

// Locks into the death overlay state. Stops continuous SFX and music so the
// game-over stinger plays into clean silence, and freezes gameplay updates
// behind the `gs.game_over` gate in update().
@(private = "file")
enter_game_over :: proc() {
	gs.game_over = true
	gs.game_over_t = 0
	gs.dialogue.active = false
	gs.mission_title.active = false
	gs.player.charging = false
	stop_rapid_fire_sfx(&gs.audio)
	stop_charging_beam_sfx(&gs.audio)
	stop_golgotha_bullet_hell_sfx(&gs.audio)
	stop_morgan_chatter_sfx(&gs.audio)
	set_music_lpf_enabled(&gs.audio, false)
	rl.StopMusicStream(gs.audio.music[gs.audio.current_track])
	play_game_over_sfx(&gs.audio)
}

// "GAME OVER" title eases in from above the screen using raylib's elastic-out
// curve — distinct from the smoothstep used by every other fade in the game so
// the death feels punctuated rather than just another transition.
draw_game_over :: proc(t: f32) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, GAME_OVER_OVERLAY_ALPHA})

	anim_t := t
	if anim_t > GAME_OVER_ANIM_DUR {
		anim_t = GAME_OVER_ANIM_DUR
	}
	title_y := rl.EaseElasticOut(
		anim_t,
		GAME_OVER_TITLE_DROP_FROM_Y,
		f32(GAME_OVER_TITLE_Y) - GAME_OVER_TITLE_DROP_FROM_Y,
		GAME_OVER_ANIM_DUR,
	)

	title := cstring("GAME OVER")
	title_w := rl.MeasureText(title, GAME_OVER_TITLE_FONT_SIZE)
	title_x: i32 = (SCREEN_WIDTH - title_w) / 2
	ty := i32(title_y)
	rl.DrawText(title, title_x + 2, ty + 2, GAME_OVER_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, title_x, ty, GAME_OVER_TITLE_FONT_SIZE, rl.Color{220, 60, 60, 255})

	if t < GAME_OVER_INPUT_DELAY {
		return
	}

	pre := cstring("PRESS")
	tail := cstring("TO RETURN TO MAIN MENU")
	pre_w := rl.MeasureText(pre, GAME_OVER_PROMPT_FONT_SIZE)
	tail_w := rl.MeasureText(tail, GAME_OVER_PROMPT_FONT_SIZE)
	icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	total_w := pre_w + HINT_TEXT_GAP + icon_w + HINT_TEXT_GAP + tail_w
	prompt_x: i32 = (SCREEN_WIDTH - total_w) / 2
	prompt_y: i32 = GAME_OVER_PROMPT_Y
	icon_y := prompt_y + (GAME_OVER_PROMPT_FONT_SIZE - HINT_ICON_SIZE) / 2
	rl.DrawText(pre, prompt_x + 1, prompt_y + 1, GAME_OVER_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(pre, prompt_x, prompt_y, GAME_OVER_PROMPT_FONT_SIZE, rl.WHITE)
	icon_x := prompt_x + pre_w + HINT_TEXT_GAP
	draw_input_hint(.Confirm, icon_x, icon_y, HINT_ICON_SIZE)
	tail_x := icon_x + icon_w + HINT_TEXT_GAP
	rl.DrawText(tail, tail_x + 1, prompt_y + 1, GAME_OVER_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(tail, tail_x, prompt_y, GAME_OVER_PROMPT_FONT_SIZE, rl.WHITE)
}

draw_run_timer :: proc(run_time: f32) {
	t := run_time
	if t < 0 {
		t = 0
	}
	total := int(t)
	mins := total / 60
	secs := total % 60
	text := fmt.ctprintf("%02d:%02d", mins, secs)
	w := rl.MeasureText(text, TIMER_FONT_SIZE)
	x: i32 = SCREEN_WIDTH - HP_BAR_MARGIN - w
	rl.DrawText(text, x + 1, HP_BAR_MARGIN + 1, TIMER_FONT_SIZE, rl.BLACK)
	rl.DrawText(text, x, HP_BAR_MARGIN, TIMER_FONT_SIZE, rl.WHITE)
}

draw_victory :: proc(level: int, choosing: bool, has_next: bool, run_time: f32) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, VICTORY_OVERLAY_ALPHA})

	if !has_next {
		draw_final_victory(run_time)
		return
	}

	// While the upgrade picker is up, the title sits higher to leave room for
	// the upgrade cards beneath it.
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

	if choosing {
		return
	}

	pre := cstring("PRESS")
	tail := fmt.ctprintf("FOR MISSION %d", level + 1)
	pre_w := rl.MeasureText(pre, VICTORY_PROMPT_FONT_SIZE)
	tail_w := rl.MeasureText(tail, VICTORY_PROMPT_FONT_SIZE)
	icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	total_w := pre_w + HINT_TEXT_GAP + icon_w + HINT_TEXT_GAP + tail_w
	prompt_x: i32 = (SCREEN_WIDTH - total_w) / 2
	prompt_y: i32 = title_y + VICTORY_TITLE_FONT_SIZE + 16
	icon_y := prompt_y + (VICTORY_PROMPT_FONT_SIZE - HINT_ICON_SIZE) / 2
	rl.DrawText(pre, prompt_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(pre, prompt_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
	icon_x := prompt_x + pre_w + HINT_TEXT_GAP
	draw_input_hint(.Confirm, icon_x, icon_y, HINT_ICON_SIZE)
	tail_x := icon_x + icon_w + HINT_TEXT_GAP
	rl.DrawText(tail, tail_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(tail, tail_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
}

@(private = "file")
draw_final_victory :: proc(run_time: f32) {
	title := cstring("VICTORY")
	title_w := rl.MeasureText(title, VICTORY_TITLE_FONT_SIZE)
	title_x: i32 = (SCREEN_WIDTH - title_w) / 2
	title_y: i32 = FINAL_VICTORY_TITLE_Y
	rl.DrawText(title, title_x + 2, title_y + 2, VICTORY_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, title_x, title_y, VICTORY_TITLE_FONT_SIZE, rl.WHITE)

	t := run_time
	if t < 0 {
		t = 0
	}
	total_secs := int(t)
	mins := total_secs / 60
	secs := total_secs % 60
	time_text := fmt.ctprintf("TIME: %02d:%02d", mins, secs)
	time_w := rl.MeasureText(time_text, VICTORY_TIME_FONT_SIZE)
	time_x: i32 = (SCREEN_WIDTH - time_w) / 2
	time_y: i32 = title_y + VICTORY_TITLE_FONT_SIZE + 12
	rl.DrawText(time_text, time_x + 1, time_y + 1, VICTORY_TIME_FONT_SIZE, rl.BLACK)
	rl.DrawText(time_text, time_x, time_y, VICTORY_TIME_FONT_SIZE, rl.WHITE)

	pre := cstring("PRESS")
	tail := cstring("TO RETURN TO MAIN MENU")
	pre_w := rl.MeasureText(pre, VICTORY_PROMPT_FONT_SIZE)
	tail_w := rl.MeasureText(tail, VICTORY_PROMPT_FONT_SIZE)
	icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	total_w := pre_w + HINT_TEXT_GAP + icon_w + HINT_TEXT_GAP + tail_w
	prompt_x: i32 = (SCREEN_WIDTH - total_w) / 2
	prompt_y: i32 = FINAL_VICTORY_PROMPT_BOTTOM_Y
	icon_y := prompt_y + (VICTORY_PROMPT_FONT_SIZE - HINT_ICON_SIZE) / 2
	rl.DrawText(pre, prompt_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(pre, prompt_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
	icon_x := prompt_x + pre_w + HINT_TEXT_GAP
	draw_input_hint(.Confirm, icon_x, icon_y, HINT_ICON_SIZE)
	tail_x := icon_x + icon_w + HINT_TEXT_GAP
	rl.DrawText(tail, tail_x + 1, prompt_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
	rl.DrawText(tail, tail_x, prompt_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
}

draw_upgrade_choice :: proc(choices: []Player_Upgrade, cursor: int, rerolls_remaining: int) {
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

	// "[step] PICK   [confirm] CONFIRM   [reroll] REROLL" — same layout for
	// kb/gp, just different icons. Reroll segment drops out when spent.
	pick := cstring("PICK")
	confirm := cstring("CONFIRM")
	reroll_text := cstring("REROLL")
	show_reroll := rerolls_remaining > 0
	step_icon_w := input_hint_width(.Menu_Step_Horizontal, HINT_ICON_SIZE)
	confirm_icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	reroll_icon_w := input_hint_width(.Reroll, HINT_ICON_SIZE)
	pick_w := rl.MeasureText(pick, VICTORY_PROMPT_FONT_SIZE)
	confirm_w := rl.MeasureText(confirm, VICTORY_PROMPT_FONT_SIZE)
	reroll_w := rl.MeasureText(reroll_text, VICTORY_PROMPT_FONT_SIZE)
	section_gap: i32 = 16
	hint_total :=
		step_icon_w +
		HINT_TEXT_GAP +
		pick_w +
		section_gap +
		confirm_icon_w +
		HINT_TEXT_GAP +
		confirm_w
	if show_reroll {
		hint_total += section_gap + reroll_icon_w + HINT_TEXT_GAP + reroll_w
	}
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
	if show_reroll {
		cursor += confirm_w + section_gap
		draw_input_hint(.Reroll, cursor, icon_y, HINT_ICON_SIZE)
		cursor += reroll_icon_w + HINT_TEXT_GAP
		rl.DrawText(reroll_text, cursor + 1, hint_y + 1, VICTORY_PROMPT_FONT_SIZE, rl.BLACK)
		rl.DrawText(reroll_text, cursor, hint_y, VICTORY_PROMPT_FONT_SIZE, rl.WHITE)
	}
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
		return "SHRINK TIME",
			"You can shrink spacetime",
			"to half speed, effectively slowing",
			"everything down. Drains stamina.",
			rl.Color{80, 180, 255, 255}
	case .Dash_Frenzy:
		return "DASH FRENZY",
			"Your dash now fires two homing",
			"missles that deal 8 base damage",
			"but cost additional stamina",
			rl.Color{200, 110, 255, 255}
	case .Rapid_Fire:
		return "RAPID FIRE",
			"Your attack becomes a",
			"rapid fire bullet launcher.",
			"Your charged beam deactivates.",
			rl.Color{255, 80, 80, 255}
	case .Beam_Blast:
		return "SHOTGUN",
			"Your attack launches 5",
			"lasers in a spread pattern.",
			"You have less range.",
			rl.Color{255, 200, 80, 255}
	case .Riposte:
		return "RIPOSTE",
			"Bullets deflected by",
			"your dash track the",
			"enemy who fired them.",
			rl.Color{160, 220, 255, 255}
	case .Lucky_Shot:
		return "LUCKY SHOT",
			"Your Dash Frenzy",
			"launches 1 extra homing missle",
			"at no extra stamina cost.",
			rl.Color{255, 220, 120, 255}
	case .Vitality:
		return "VITALITY",
			"Toughens your body",
			"and increases your maximum",
			"health by 25.",
			rl.Color{120, 230, 120, 255}
	case .Endurance:
		return "ENDURANCE",
			"Trains your stamina",
			"and increases your maximum",
			"stamina by 25.",
			rl.Color{255, 240, 140, 255}
	case .Heart_Of_Steel:
		return "HEART OF STEEL",
			"You recover stamina",
			"30% more quickly",
			"",
			rl.Color{210, 220, 235, 255}
	}
	return
}

@(private = "file")
apply_upgrade_stats :: proc(p: ^Player, u: Player_Upgrade) {
	switch u {
	case .Vitality:
		p.max_hp += 25
		p.hp += 25
	case .Endurance:
		p.max_stamina += 25
		p.stamina += 25
	case .Slow_Time, .Dash_Frenzy, .Rapid_Fire, .Beam_Blast, .Riposte, .Lucky_Shot, .Heart_Of_Steel:
	}
}

// Builds the upgrade pool from {all upgrades} - {already owned}, with the
// Rapid_Fire <-> Beam_Blast mutex applied. Samples up to 3 distinct upgrades
// without replacement and switches into the choosing-upgrade state. If the
// pool is empty (all relevant upgrades owned) the picker is skipped entirely.
@(private = "file")
open_upgrade_choice :: proc() {
	pool: [len(Player_Upgrade)]Player_Upgrade
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
	rl.DrawText(cue, cx, cy, UPGRADE_BODY_FONT_SIZE, rl.WHITE)
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
	rl.DrawText(line2, l2x, l2y, UPGRADE_BODY_FONT_SIZE, rl.WHITE)
}

advance_to_next_mission :: proc() {
	gs.level += 1
	gs.victory = false
	gs.victory_pending = false
	gs.victory_delay_t = 0
	// play_track is idempotent: levels 2→3 share Levels_2_3 and won't restart.
	// 4→5 actually swaps streams (Gameplay → Guardian).
	play_track(&gs.audio, gameplay_track_for_level(gs.level))
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
		start_level2_intro(&gs.dialogue)
	}
	if gs.level == 3 {
		spawn_morgan(&gs.boss)
	}
	if gs.level == 4 {
		reset_level4_pacing(&gs.enemies)
		start_level4_intro(&gs.dialogue)
	}
	if gs.level == 5 {
		spawn_ancient_guardian(&gs.boss)
	}
	gs.player.hp = gs.player.max_hp
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
