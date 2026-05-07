package game

// Level 4 pacing state machine.
//
//   Wave1_Grunts   level-1 grunt wave (faster fire interval — see LEVEL4_GRUNT_FIRE_INTERVAL)
//   Wave2_WG       level-2 weirdguy wave
//   Wave3_Grunts   level-1 grunt wave (faster fire)
//   Wave4_Pillars  finale: 4 corner pillars with the kill-order puzzle (see pillar.odin)
//
// Each phase advances when its wave is fully cleared. After Wave4_Pillars
// clears, level4_waves_complete reaches LEVEL4_WAVES_TO_VICTORY and main.odin
// triggers the victory screen.

Level4_Phase :: enum {
	Wave1_Grunts,
	Wave2_WG,
	Wave3_Grunts,
	Wave4_Pillars,
}

reset_level4_pacing :: proc(enemies: ^Enemy_Pool) {
	enemies.level4_phase = .Wave1_Grunts
	enemies.level4_phase_started = false
	enemies.level4_waves_complete = 0
	enemies.fire_interval = LEVEL4_GRUNT_FIRE_INTERVAL
}

update_level4_pacing :: proc(enemies: ^Enemy_Pool, pillars: ^Pillar_Wave, dt: f32) {
	if enemies.level != 4 {
		return
	}

	if !enemies.level4_phase_started {
		on_enter_phase_l4(enemies, pillars)
		enemies.level4_phase_started = true
	}

	if phase_complete_l4(enemies, pillars) {
		advance_phase_l4(enemies)
	}
}

@(private = "file")
on_enter_phase_l4 :: proc(enemies: ^Enemy_Pool, pillars: ^Pillar_Wave) {
	switch enemies.level4_phase {
	case .Wave1_Grunts, .Wave3_Grunts:
		spawn_grunts_for_phase(enemies)
	case .Wave2_WG:
		spawn_weirdguys_for_phase(enemies)
	case .Wave4_Pillars:
		spawn_pillar_wave(pillars)
	}
}

@(private = "file")
phase_complete_l4 :: proc(enemies: ^Enemy_Pool, pillars: ^Pillar_Wave) -> bool {
	switch enemies.level4_phase {
	case .Wave1_Grunts, .Wave3_Grunts:
		return !any_grunt_alive(enemies)
	case .Wave2_WG:
		return !any_weirdguy_alive(enemies)
	case .Wave4_Pillars:
		return pillar_wave_complete(pillars)
	}
	return false
}

@(private = "file")
advance_phase_l4 :: proc(enemies: ^Enemy_Pool) {
	next: Level4_Phase
	switch enemies.level4_phase {
	case .Wave1_Grunts:
		next = .Wave2_WG
	case .Wave2_WG:
		next = .Wave3_Grunts
	case .Wave3_Grunts:
		next = .Wave4_Pillars
	case .Wave4_Pillars:
		// Terminal phase loops to itself; main.odin watches level4_waves_complete
		// and triggers victory before update_level4_pacing runs again.
		next = .Wave4_Pillars
	}
	enemies.level4_phase = next
	enemies.level4_phase_started = false
	enemies.level4_waves_complete += 1
}
