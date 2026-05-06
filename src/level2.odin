package game

// Level 2 pacing state machine.
//
//   Wave1_WG_Only         weird-guy wave, no minor enemies
//   Between_1Cyclops      1 cyclops, no weirdguys
//   Between_1Cyc_2Sneaks  1 cyclops + 2 sneaks
//   Wave2_WG_Sneaks       weirdguys + kill-driven sneak drops (no cyclops)
//   Between_4Sneaks       4 sneaks, nothing else
//   Between_3Cyc_Sneaks   3 cyclops sequentially while sneaks stream
//   Free_For_All          original level-2 mix; loops indefinitely
//
// Each "between" beat exists to give the player a clearer breather/setpiece
// after a wave instead of the prior wall-to-wall weirdguy spam. The Free_For_All
// terminal phase preserves the original endless-wave behavior so runs don't
// just stop after the scripted sequence.

Level2_Phase :: enum {
	Wave1_WG_Only,
	Between_1Cyclops,
	Between_1Cyc_2Sneaks,
	Wave2_WG_Sneaks,
	Between_4Sneaks,
	Between_3Cyc_Sneaks,
	Free_For_All,
}

reset_level2_pacing :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool) {
	enemies.level2_phase = .Wave1_WG_Only
	enemies.level2_phase_started = false
	enemies.level2_cyc_killed = 0
	enemies.level2_prev_cyc_alive = 0
	enemies.level2_sneak_timer = 0
	enemies.level2_waves_complete = 0
	sneaks.level2_phase = enemies.level2_phase
}

update_level2_pacing :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	if enemies.level < 2 {
		return
	}

	if !enemies.level2_phase_started {
		on_enter_phase(enemies, sneaks)
		enemies.level2_phase_started = true
	}

	tick_phase(enemies, sneaks, dt)

	if phase_complete(enemies, sneaks) {
		advance_phase(enemies, sneaks)
	}
}

@(private = "file")
on_enter_phase :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool) {
	switch enemies.level2_phase {
	case .Wave1_WG_Only:
		spawn_weirdguys_for_phase(enemies)
	case .Between_1Cyclops:
		force_spawn_cyclops(sneaks)
	case .Between_1Cyc_2Sneaks:
		force_spawn_cyclops(sneaks)
		for i in 0 ..< LEVEL2_BETWEEN_1CYC2SN_SNEAK_COUNT {
			_ = i
			force_spawn_sneak(sneaks)
		}
	case .Wave2_WG_Sneaks:
		spawn_weirdguys_for_phase(enemies)
	case .Between_4Sneaks:
		for i in 0 ..< LEVEL2_BETWEEN_4SNEAKS_COUNT {
			_ = i
			force_spawn_sneak(sneaks)
		}
	case .Between_3Cyc_Sneaks:
		// Reset the kill counter for this gauntlet, then spawn the first cyclops.
		// Subsequent cyclops are minted in tick_phase as the previous one dies.
		enemies.level2_cyc_killed = 0
		enemies.level2_prev_cyc_alive = 0
		enemies.level2_sneak_timer = LEVEL2_BETWEEN_3CYC_SNEAK_INTERVAL
		force_spawn_cyclops(sneaks)
	case .Free_For_All:
		// Endless: spawn the first weirdguy wave; subsequent waves come from the
		// "no weirdguys alive → respawn" rule below in tick_phase.
		spawn_weirdguys_for_phase(enemies)
	}
}

@(private = "file")
tick_phase :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	#partial switch enemies.level2_phase {
	case .Between_3Cyc_Sneaks:
		// Detect cyclops-just-died edge to mint the next cyclops up to the target.
		cur := count_cyclops_alive(sneaks)
		if enemies.level2_prev_cyc_alive > 0 && cur == 0 {
			enemies.level2_cyc_killed += 1
			if enemies.level2_cyc_killed < LEVEL2_BETWEEN_3CYC_TARGET {
				force_spawn_cyclops(sneaks)
			}
		}
		enemies.level2_prev_cyc_alive = count_cyclops_alive(sneaks)

		enemies.level2_sneak_timer -= dt
		if enemies.level2_sneak_timer <= 0 {
			enemies.level2_sneak_timer = LEVEL2_BETWEEN_3CYC_SNEAK_INTERVAL
			force_spawn_sneak(sneaks)
		}
	case .Free_For_All:
		// Endless weirdguy waves: respawn whenever the field is clear.
		if !any_weirdguy_alive(enemies) {
			spawn_weirdguys_for_phase(enemies)
		}
	}
}

@(private = "file")
phase_complete :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool) -> bool {
	switch enemies.level2_phase {
	case .Wave1_WG_Only:
		return !any_weirdguy_alive(enemies)
	case .Between_1Cyclops:
		return count_cyclops_alive(sneaks) == 0
	case .Between_1Cyc_2Sneaks:
		return count_cyclops_alive(sneaks) == 0 && count_sneaks_alive(sneaks) == 0
	case .Wave2_WG_Sneaks:
		// Wave clears when all weirdguys are gone; trailing sneaks carry over
		// into the breather rather than blocking the transition.
		return !any_weirdguy_alive(enemies)
	case .Between_4Sneaks:
		return count_sneaks_alive(sneaks) == 0 && count_cyclops_alive(sneaks) == 0
	case .Between_3Cyc_Sneaks:
		return enemies.level2_cyc_killed >= LEVEL2_BETWEEN_3CYC_TARGET &&
			count_cyclops_alive(sneaks) == 0
	case .Free_For_All:
		return false
	}
	return false
}

@(private = "file")
advance_phase :: proc(enemies: ^Enemy_Pool, sneaks: ^Sneak_Pool) {
	next: Level2_Phase
	switch enemies.level2_phase {
	case .Wave1_WG_Only:
		next = .Between_1Cyclops
	case .Between_1Cyclops:
		next = .Between_1Cyc_2Sneaks
	case .Between_1Cyc_2Sneaks:
		next = .Wave2_WG_Sneaks
	case .Wave2_WG_Sneaks:
		next = .Between_4Sneaks
	case .Between_4Sneaks:
		next = .Between_3Cyc_Sneaks
	case .Between_3Cyc_Sneaks:
		next = .Free_For_All
	case .Free_For_All:
		next = .Free_For_All
	}
	enemies.level2_phase = next
	enemies.level2_phase_started = false
	enemies.level2_waves_complete += 1
	sneaks.level2_phase = next
}

@(private = "file")
any_weirdguy_alive :: proc(enemies: ^Enemy_Pool) -> bool {
	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if e.active && e.kind == .WeirdGuy {
			return true
		}
	}
	return false
}

@(private = "file")
count_cyclops_alive :: proc(sneaks: ^Sneak_Pool) -> int {
	n := 0
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if s.active && s.kind == .Cyclops {
			n += 1
		}
	}
	return n
}

@(private = "file")
count_sneaks_alive :: proc(sneaks: ^Sneak_Pool) -> int {
	n := 0
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if s.active && s.kind == .Sneak {
			n += 1
		}
	}
	return n
}
