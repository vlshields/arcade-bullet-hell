package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"
import "core:fmt"

// # region Grunts and WeirdGuys
Enemy_Kind :: enum {
	Grunt,
	WeirdGuy,
}

Grunt_Data :: struct {
	anchor: rl.Vector2,
	angle:  f32,
	radius: f32,
}

WeirdGuy_Data :: struct {
	patrol_min_x: f32,
	patrol_max_x: f32,
	dir:          f32,
	entering:     bool,
}

Enemy :: struct {
	kind:       Enemy_Kind,
	pos:        rl.Vector2,
	frame:      int,
	frame_time: f32,
	fire_timer: f32,
	hp:         int,
	hit_flash:  f32,
	active:     bool,
	data:       union {
		Grunt_Data,
		WeirdGuy_Data,
	},
}

WeirdGuy_Corpse :: struct {
	pos:        rl.Vector2,
	frame:      int,
	frame_time: f32,
	active:     bool,
}

Enemy_Pool :: struct {
	enemies:           [ENEMY_COUNT]Enemy,
	weirdguy_corpses:  [WEIRDGUY_CORPSE_MAX]WeirdGuy_Corpse,
	tex:               rl.Texture2D,
	weirdguy_tex:      rl.Texture2D,
	weirdguy_dies_tex: rl.Texture2D,
	flash_shader:      rl.Shader,
	level:         int,
	waves_cleared: int,
	fire_interval: f32,
	boost_applied: bool,
	// Level-2 pacing state. See level2.odin. Only consulted when level >= 2;
	// level 1 keeps the original waves_cleared / boss-trigger flow.
	level2_phase:           Level2_Phase,
	level2_phase_started:   bool,
	level2_cyc_killed:      int,
	level2_prev_cyc_alive:  int,
	level2_sneak_timer:     f32,
	level2_waves_complete:  int,
	// Level-4 pacing state. See level4.odin.
	level4_phase:           Level4_Phase,
	level4_phase_started:   bool,
	level4_waves_complete:  int,
}

init_enemies :: proc(pool: ^Enemy_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_grunt_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.weirdguy_tex = rl.LoadTexture("assets/sprites/enemy_weirdguy_move.png")
	rl.SetTextureFilter(pool.weirdguy_tex, .POINT)
	pool.weirdguy_dies_tex = rl.LoadTexture("assets/sprites/enemy_weirdguy_dies.png")
	rl.SetTextureFilter(pool.weirdguy_dies_tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.level = 1
	pool.waves_cleared = 0
	pool.fire_interval = ENEMY_FIRE_INTERVAL
	pool.boost_applied = false
	spawn_wave(pool)
}

unload_enemies :: proc(pool: ^Enemy_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadTexture(pool.weirdguy_tex)
	rl.UnloadTexture(pool.weirdguy_dies_tex)
	rl.UnloadShader(pool.flash_shader)
}

// Weird guys leave a brief death animation behind when killed. The corpse pool
// is independent of the enemy slot — the slot is freed immediately so wave
// gating and respawns aren't held up by the visual.
spawn_weirdguy_corpse :: proc(pool: ^Enemy_Pool, pos: rl.Vector2) {
	for i in 0 ..< WEIRDGUY_CORPSE_MAX {
		c := &pool.weirdguy_corpses[i]
		if c.active {
			continue
		}
		c.pos = pos
		c.frame = 0
		c.frame_time = 0
		c.active = true
		return
	}
}

update_weirdguy_corpses :: proc(pool: ^Enemy_Pool, dt: f32) {
	for i in 0 ..< WEIRDGUY_CORPSE_MAX {
		c := &pool.weirdguy_corpses[i]
		if !c.active {
			continue
		}
		c.frame_time += dt
		for c.frame_time >= WEIRDGUY_DEATH_FRAME_DUR {
			c.frame_time -= WEIRDGUY_DEATH_FRAME_DUR
			if c.frame >= WEIRDGUY_DEATH_FRAMES - 1 {
				c.active = false
				break
			}
			c.frame += 1
		}
	}
}

draw_weirdguy_corpses :: proc(pool: ^Enemy_Pool) {
	draw_w := f32(WEIRDGUY_FRAME_W * WEIRDGUY_DRAW_SCALE)
	draw_h := f32(WEIRDGUY_FRAME_H * WEIRDGUY_DRAW_SCALE)
	for i in 0 ..< WEIRDGUY_CORPSE_MAX {
		c := &pool.weirdguy_corpses[i]
		if !c.active {
			continue
		}
		src := rl.Rectangle {
			f32(c.frame * WEIRDGUY_FRAME_W),
			0,
			f32(WEIRDGUY_FRAME_W),
			f32(WEIRDGUY_FRAME_H),
		}
		dst := rl.Rectangle{c.pos.x - draw_w * 0.5, c.pos.y - draw_h * 0.5, draw_w, draw_h}
		rl.DrawTexturePro(pool.weirdguy_dies_tex, src, dst, {0, 0}, 0, rl.WHITE)
	}
}

spawn_wave :: proc(pool: ^Enemy_Pool) {
	for i in 0 ..< ENEMY_COUNT {
		pool.enemies[i].active = false
	}
	if pool.level >= 2 {
		spawn_weirdguy_wave(pool)
	} else {
		spawn_grunt_wave(pool)
	}
}

@(private = "file")
spawn_grunt_wave :: proc(pool: ^Enemy_Pool) {
	for i in 0 ..< GRUNT_WAVE_COUNT {
		anchor := rl.Vector2{SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2}
		angle := f32(i) * math.TAU / f32(GRUNT_WAVE_COUNT)
		radius: f32 = ENEMY_SPAWN_RADIUS
		pool.enemies[i] = Enemy {
			kind       = .Grunt,
			pos        = {anchor.x + math.cos(angle) * radius, anchor.y + math.sin(angle) * radius},
			frame      = 0,
			frame_time = 0,
			fire_timer = rand.float32() * pool.fire_interval,
			hp         = ENEMY_MAX_HP,
			hit_flash  = 0,
			active     = true,
			data       = Grunt_Data{anchor = anchor, angle = angle, radius = radius},
		}
	}
}


spawn_weirdguys_for_phase :: proc(pool: ^Enemy_Pool) {
	for i in 0 ..< ENEMY_COUNT {
		pool.enemies[i].active = false
	}
	spawn_weirdguy_wave(pool)
}

spawn_grunts_for_phase :: proc(pool: ^Enemy_Pool) {
	for i in 0 ..< ENEMY_COUNT {
		pool.enemies[i].active = false
	}
	spawn_grunt_wave(pool)
}

any_grunt_alive :: proc(pool: ^Enemy_Pool) -> bool {
	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if e.active && e.kind == .Grunt {
			return true
		}
	}
	return false
}

any_weirdguy_alive :: proc(pool: ^Enemy_Pool) -> bool {
	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if e.active && e.kind == .WeirdGuy {
			return true
		}
	}
	return false
}

@(private = "file")
spawn_weirdguy_wave :: proc(pool: ^Enemy_Pool) {
	half := f32(WEIRDGUY_PATROL_RANGE) * 0.5
	margin := f32(WEIRDGUY_FRAME_W * WEIRDGUY_DRAW_SCALE) * 0.5
	min_center := margin + half
	max_center := f32(SCREEN_WIDTH) - margin - half
	for i in 0 ..< WEIRDGUY_WAVE_COUNT {
		center_x := min_center + rand.float32() * (max_center - min_center)
		y := WEIRDGUY_Y_MIN + rand.float32() * (WEIRDGUY_Y_MAX - WEIRDGUY_Y_MIN)
		dir: f32
		start_x: f32
		if rand.float32() < 0.5 {
			dir = 1
			start_x = -margin - 1
		} else {
			dir = -1
			start_x = f32(SCREEN_WIDTH) + margin + 1
		}
		pool.enemies[i] = Enemy {
			kind = .WeirdGuy,
			pos = {start_x, y},
			frame = 0,
			frame_time = 0,
			fire_timer = rand.float32() * WEIRDGUY_FIRE_INTERVAL,
			hp = WEIRDGUY_MAX_HP,
			hit_flash = 0,
			active = true,
			data = WeirdGuy_Data {
				patrol_min_x = center_x - half,
				patrol_max_x = center_x + half,
				dir = dir,
				entering = true,
			},
		}
	}
}

damage_enemy :: proc(e: ^Enemy, amount: int) -> (killed: bool) {
	if !e.active {
		return false
	}
	e.hp -= amount
	e.hit_flash = ENEMY_HIT_FLASH_TIME
	if e.hp <= 0 {
		e.hp = 0
		e.active = false
		return true
	}
	return false
}

enemy_center :: proc(e: ^Enemy) -> rl.Vector2 {
	return e.pos
}

enemy_hit_radius :: proc(e: ^Enemy) -> f32 {
	if e.kind == .WeirdGuy {
		return WEIRDGUY_HIT_RADIUS
	}
	return ENEMY_HIT_RADIUS
}

update_enemies :: proc(
	pool: ^Enemy_Pool,
	boss: ^Boss_Pool,
	bullets: ^Bullet_Pool,
	player: ^Player,
	audio: ^Audio,
	dt: f32,
	block_next_wave: bool,
) {
	any_alive := false
	for i in 0 ..< ENEMY_COUNT {
		if pool.enemies[i].active {
			any_alive = true
			break
		}
	}
	// block_next_wave defers the level-1 between-wave hand-off so a non-pausing
	// dialogue can play in the empty arena without wave 2 spawning underneath it.
	if !any_alive && pool.level < 2 && !block_next_wave {
		// Post-defeat: the victory window holds gameplay live for VICTORY_DELAY
		// so the kill registers; without this gate a fresh grunt wave spawns
		// into that window and flashes on screen before clear_world fires.
		if !boss.boss.active && !boss.boss.defeated {
			pool.waves_cleared += 1
			if pool.waves_cleared == BOSS_TRIGGER_WAVE {
				spawn_boss(boss)
			} else {
				if !pool.boost_applied && pool.waves_cleared >= ENEMY_WAVE_BOOST_THRESHOLD {
					pool.fire_interval /= 1.0 + ENEMY_FIRE_FREQ_BOOST
					pool.boost_applied = true
				}
				spawn_wave(pool)
			}
		}
	}

	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	player_center := rl.Vector2{pcx, pcy}

	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if !e.active {
			continue
		}
		if e.hit_flash > 0 {
			e.hit_flash -= dt
			if e.hit_flash < 0 {
				e.hit_flash = 0
			}
		}
		switch e.kind {
		case .Grunt:
			update_grunt_one(e, i, pool.fire_interval, bullets, audio, dt)
		case .WeirdGuy:
			update_weirdguy_one(e, i, player_center, bullets, dt)
		}
	}

	update_weirdguy_corpses(pool, dt)
}

@(private = "file")
update_grunt_one :: proc(e: ^Enemy, index: int, fire_interval: f32, bullets: ^Bullet_Pool, audio: ^Audio, dt: f32) {
	d := &e.data.(Grunt_Data)

	d.angle += ENEMY_ORBIT_SPEED * dt
	if d.angle >= math.TAU {
		d.angle -= math.TAU
	}

	if d.radius > ENEMY_ORBIT_RADIUS {
		d.radius -= ENEMY_APPROACH_SPEED * dt
		if d.radius < ENEMY_ORBIT_RADIUS {
			d.radius = ENEMY_ORBIT_RADIUS
		}
	}

	e.pos = {d.anchor.x + math.cos(d.angle) * d.radius, d.anchor.y + math.sin(d.angle) * d.radius}

	e.frame_time += dt
	frame_dur: f32 = 1.0 / ENEMY_ANIM_FPS
	if e.frame_time >= frame_dur {
		e.frame_time -= frame_dur
		e.frame = (e.frame + 1) % ENEMY_FRAMES
	}

	if d.radius > ENEMY_ORBIT_RADIUS {
		return
	}

	e.fire_timer += dt
	if e.fire_timer >= fire_interval {
		e.fire_timer -= fire_interval
		for b in 0 ..< ENEMY_BULLETS_PER_BURST {
			angle := f32(b) * (math.TAU / f32(ENEMY_BULLETS_PER_BURST))
			vel := rl.Vector2 {
				math.cos(angle) * ENEMY_BULLET_SPEED,
				math.sin(angle) * ENEMY_BULLET_SPEED,
			}
			spawn_bullet(bullets, e.pos, vel, rl.RED, .Enemy, .Enemy, index)
		}
		play_grunt_attack_sfx(audio)
	}
}

@(private = "file")
update_weirdguy_one :: proc(
	e: ^Enemy,
	index: int,
	player_center: rl.Vector2,
	bullets: ^Bullet_Pool,
	dt: f32,
) {
	d := &e.data.(WeirdGuy_Data)

	if d.entering {
		e.pos.x += d.dir * WEIRDGUY_SPEED * dt
		if d.dir > 0 {
			if e.pos.x >= d.patrol_min_x {
				e.pos.x = d.patrol_min_x
				d.entering = false
			}
		} else {
			if e.pos.x <= d.patrol_max_x {
				e.pos.x = d.patrol_max_x
				d.entering = false
			}
		}
		return
	}

	e.pos.x += d.dir * WEIRDGUY_SPEED * dt
	if e.pos.x <= d.patrol_min_x {
		e.pos.x = d.patrol_min_x
		d.dir = 1
	} else if e.pos.x >= d.patrol_max_x {
		e.pos.x = d.patrol_max_x
		d.dir = -1
	}

	color := rl.Color{0xcc, 0xff, 0x66, 0xff}
	e.fire_timer += dt
	for e.fire_timer >= WEIRDGUY_FIRE_INTERVAL {
		e.fire_timer -= WEIRDGUY_FIRE_INTERVAL
		to_player := player_center - e.pos
		if rl.Vector2Length(to_player) < 0.001 {
			to_player = {0, 1}
		}
		angle := math.atan2(to_player.y, to_player.x)
		vel := rl.Vector2 {
			math.cos(angle) * WEIRDGUY_BULLET_SPEED,
			math.sin(angle) * WEIRDGUY_BULLET_SPEED,
		}
		spawn_bullet(bullets, e.pos, vel, color, .Enemy, .Enemy, index)
	}
}

draw_enemies :: proc(pool: ^Enemy_Pool) {
	draw_weirdguy_corpses(pool)
	for i in 0 ..< ENEMY_COUNT {
		e := &pool.enemies[i]
		if !e.active {
			continue
		}
		switch e.kind {
		case .Grunt:
			draw_grunt_one(pool, e)
		case .WeirdGuy:
			draw_weirdguy_one(pool, e)
		}
	}
}

@(private = "file")
draw_grunt_one :: proc(pool: ^Enemy_Pool, e: ^Enemy) {
	draw_w := f32(ENEMY_FRAME_W * ENEMY_DRAW_SCALE)
	draw_h := f32(ENEMY_FRAME_H * ENEMY_DRAW_SCALE)
	src := rl.Rectangle{f32(e.frame * ENEMY_FRAME_W), 0, f32(ENEMY_FRAME_W), f32(ENEMY_FRAME_H)}
	dst := rl.Rectangle{e.pos.x - draw_w * 0.5, e.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := e.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}

@(private = "file")
draw_weirdguy_one :: proc(pool: ^Enemy_Pool, e: ^Enemy) {
	draw_w := f32(WEIRDGUY_FRAME_W * WEIRDGUY_DRAW_SCALE)
	draw_h := f32(WEIRDGUY_FRAME_H * WEIRDGUY_DRAW_SCALE)
	src := rl.Rectangle{0, 0, f32(WEIRDGUY_FRAME_W), f32(WEIRDGUY_FRAME_H)}
	dst := rl.Rectangle{e.pos.x - draw_w * 0.5, e.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := e.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.weirdguy_tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}
// #endregion

// #region Sneaks and Cyclops
Minor_Enemy_Kind :: enum {
	Sneak,
	Cyclops,
}

Sneak_Data :: struct {
	anchor:         rl.Vector2,
	sway_phase:     f32,
	teleport_timer: f32,
}

Cyclops_Data :: struct {
	cross_t:      f32,
	cross_dir:    f32,
	pattern:      int,
	spiral_angle: f32,
	frame:        int,
	frame_time:   f32,
}

Sneak :: struct {
	kind:       Minor_Enemy_Kind,
	pos:        rl.Vector2,
	hp:         int,
	hit_flash:  f32,
	fire_timer: f32,
	active:     bool,
	data:       union {
		Sneak_Data,
		Cyclops_Data,
	},
}

Sneak_Pool :: struct {
	sneaks:       [SNEAK_MAX]Sneak,
	tex:          rl.Texture2D,
	cyclops_tex:  rl.Texture2D,
	flash_shader: rl.Shader,
	level:        int,
	// Mirror of Enemy_Pool.level2_phase, kept in sync so try_spawn_sneak can
	// gate kill-driven minor spawns without needing a back-reference to Enemy_Pool.
	level2_phase: Level2_Phase,
	// Multiplier applied to the level-1 random sneak spawn chance. Set to 0
	// while the wave-2 intro is pending so kill drops don't seed sneaks that
	// would still be alive (and shooting) when the dialogue plays.
	spawn_chance_scale: f32,
	// Hard gate on every try_spawn_sneak path — set during the post-victory
	// VICTORY_DELAY window so leftover enemy kills don't seed new sneaks /
	// cyclops that would flash on screen before clear_world fires.
	spawns_blocked:     bool,
	// Edge flag set whenever a sneak teleports OR a sneak/cyclops spawns.
	// main.odin drains it once per frame and plays sfx_sneak_teleport. Single
	// flag (not counter) so simultaneous events collapse into one cue.
	teleport_or_spawn_event: bool,
}

init_sneaks :: proc(pool: ^Sneak_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_sneak_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.cyclops_tex = rl.LoadTexture("assets/sprites/enemy_cyclops_move.png")
	rl.SetTextureFilter(pool.cyclops_tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.level = 1
	pool.spawn_chance_scale = 1
	for i in 0 ..< SNEAK_MAX {
		pool.sneaks[i].active = false
	}
}

unload_sneaks :: proc(pool: ^Sneak_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadTexture(pool.cyclops_tex)
	rl.UnloadShader(pool.flash_shader)
}

damage_sneak :: proc(s: ^Sneak, amount: int) -> (killed: bool) {
	if !s.active {
		return false
	}
	s.hp -= amount
	s.hit_flash = SNEAK_HIT_FLASH_TIME
	if s.hp <= 0 {
		s.hp = 0
		s.active = false
		return true
	}
	return false
}

sneak_center :: proc(s: ^Sneak) -> rl.Vector2 {
	return s.pos
}

sneak_hit_radius :: proc(s: ^Sneak) -> f32 {
	if s.kind == .Cyclops {
		return CYCLOPS_HIT_RADIUS
	}
	return SNEAK_HIT_RADIUS
}

random_viewport_point :: proc() -> rl.Vector2 {
	margin := f32(SNEAK_SPAWN_MARGIN)
	x := margin + rand.float32() * (f32(SCREEN_WIDTH) - 2 * margin)
	y := margin + rand.float32() * (f32(SCREEN_HEIGHT) - 2 * margin)
	return {x, y}
}

effective_sneak_cap :: proc(pool: ^Sneak_Pool) -> int {
	if pool.level <= 1 {
		return LEVEL1_SNEAK_CAP
	}
	return SNEAK_MAX
}

try_spawn_sneak :: proc(pool: ^Sneak_Pool) {
	if pool.spawns_blocked {
		return
	}
	if pool.level < 2 {
		if rand.float32() < SNEAK_SPAWN_CHANCE * pool.spawn_chance_scale {
			force_spawn_sneak(pool)
		}
		return
	}
	if pool.level == 4 {
		// Level 4 is grunts + weirdguys only — kill drops should not bleed minor
		// enemies into the wave. Prevents stale level2_phase state from leaking.
		return
	}
	switch pool.level2_phase {
	case .Wave1_WG_Only,
	     .Between_1Cyclops,
	     .Between_1Cyc_2Sneaks,
	     .Between_4Sneaks:
		return
	case .Wave2_WG_Sneaks:
		// "Weird guys and sneaks" — only sneaks here, no cyclops.
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		}
	case .Between_3Cyc_Sneaks:
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		}
	case .Free_For_All:
		if rand.float32() < SNEAK_SPAWN_CHANCE {
			force_spawn_sneak(pool)
		} else {
			force_spawn_cyclops(pool)
		}
	}
}

force_spawn_sneak :: proc(pool: ^Sneak_Pool) {
	cap := effective_sneak_cap(pool)
	slot := -1
	for i in 0 ..< cap {
		if !pool.sneaks[i].active {
			slot = i
			break
		}
	}
	if slot < 0 {
		return
	}
	anchor := random_viewport_point()
	pool.sneaks[slot] = Sneak {
		kind = .Sneak,
		pos = anchor,
		hp = SNEAK_MAX_HP,
		hit_flash = 0,
		fire_timer = rand.float32() * SNEAK_BURST_INTERVAL,
		active = true,
		data = Sneak_Data {
			anchor = anchor,
			sway_phase = rand.float32() * math.TAU,
			teleport_timer = SNEAK_TELEPORT_INTERVAL,
		},
	}
	pool.teleport_or_spawn_event = true
}

// Forced cyclops spawn. Bypasses the level guard (caller is responsible for
// gating) but keeps the "only one cyclops alive at a time" rule because two
// cyclops is too much screen real estate for the existing bullet patterns.
force_spawn_cyclops :: proc(pool: ^Sneak_Pool) {
	cap := effective_sneak_cap(pool)
	slot := -1
	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if s.active && s.kind == .Cyclops {
			return
		}
		if !s.active && slot < 0 && i < cap {
			slot = i
		}
	}
	if slot < 0 {
		return
	}
	dir: f32 = rand.float32() < 0.5 ? 1.0 : -1.0
	y := CYCLOPS_Y_MIN + rand.float32() * (CYCLOPS_Y_MAX - CYCLOPS_Y_MIN)
	margin := f32(CYCLOPS_OFFSCREEN_MARGIN)
	start_x: f32 = dir > 0 ? -margin : f32(SCREEN_WIDTH) + margin
	pool.sneaks[slot] = Sneak {
		kind = .Cyclops,
		pos = {start_x, y},
		hp = CYCLOPS_MAX_HP,
		hit_flash = 0,
		fire_timer = 0,
		active = true,
		data = Cyclops_Data {
			cross_t = 0,
			cross_dir = dir,
			pattern = int(rand.uint32() % CYCLOPS_PATTERN_COUNT),
			spiral_angle = rand.float32() * math.TAU,
			frame = 0,
			frame_time = 0,
		},
	}
	pool.teleport_or_spawn_event = true
}

update_sneaks :: proc(pool: ^Sneak_Pool, player: ^Player, bullets: ^Bullet_Pool, audio: ^Audio, dt: f32) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	player_center := rl.Vector2{pcx, pcy}

	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if !s.active {
			continue
		}

		if s.hit_flash > 0 {
			s.hit_flash -= dt
			if s.hit_flash < 0 {
				s.hit_flash = 0
			}
		}

		switch s.kind {
		case .Sneak:
			update_sneak_one(pool, s, i, player_center, bullets, dt)
		case .Cyclops:
			update_cyclops_one(s, i, player_center, bullets, audio, dt)
		}
	}
}

@(private = "file")
update_sneak_one :: proc(pool: ^Sneak_Pool, s: ^Sneak, index: int, player_center: rl.Vector2, bullets: ^Bullet_Pool, dt: f32) {
	d := &s.data.(Sneak_Data)

	d.sway_phase += SNEAK_SWAY_FREQ * math.TAU * dt
	if d.sway_phase >= math.TAU {
		d.sway_phase -= math.TAU
	}
	s.pos.x = d.anchor.x + math.sin(d.sway_phase) * SNEAK_SWAY_AMPLITUDE
	s.pos.y = d.anchor.y

	d.teleport_timer -= dt
	if d.teleport_timer <= 0 {
		d.teleport_timer = SNEAK_TELEPORT_INTERVAL
		d.anchor = random_viewport_point()
		d.sway_phase = rand.float32() * math.TAU
		s.pos = d.anchor
		pool.teleport_or_spawn_event = true
	}

	s.fire_timer += dt
	if s.fire_timer >= SNEAK_BURST_INTERVAL {
		s.fire_timer -= SNEAK_BURST_INTERVAL
		to_player := player_center - s.pos
		if rl.Vector2Length(to_player) < 0.001 {
			to_player = {0, 1}
		}
		base_angle := math.atan2(to_player.y, to_player.x)
		fan_rad := f32(SNEAK_BURST_FAN_DEG) * math.PI / 180.0
		n := f32(SNEAK_BULLETS_PER_BURST)
		color := rl.Color{0x99, 0x33, 0x66, 0xff}
		for b in 0 ..< SNEAK_BULLETS_PER_BURST {
			t := f32(b) / (n - 1) - 0.5
			angle := base_angle + t * fan_rad
			vel := rl.Vector2 {
				math.cos(angle) * SNEAK_BULLET_SPEED,
				math.sin(angle) * SNEAK_BULLET_SPEED,
			}
			spawn_bullet(bullets, s.pos, vel, color, .Enemy, .Sneak, index)
		}
	}
}

@(private = "file")
update_cyclops_one :: proc(
	s: ^Sneak,
	index: int,
	player_center: rl.Vector2,
	bullets: ^Bullet_Pool,
	audio: ^Audio,
	dt: f32,
) {
	d := &s.data.(Cyclops_Data)

	// Animation cycles through all 9 frames of the cyclops sheet.
	d.frame_time += dt
	frame_dur: f32 = 1.0 / CYCLOPS_ANIM_FPS
	if d.frame_time >= frame_dur {
		d.frame_time -= frame_dur
		d.frame = (d.frame + 1) % CYCLOPS_FRAMES
	}

	// Side-to-side pass: cross_t goes 0->1 over CYCLOPS_CROSS_DURATION, then
	// flips direction, picks a new altitude, and rerolls the bullet pattern.
	d.cross_t += dt / CYCLOPS_CROSS_DURATION
	if d.cross_t >= 1.0 {
		d.cross_t = 0
		d.cross_dir = -d.cross_dir
		s.pos.y = CYCLOPS_Y_MIN + rand.float32() * (CYCLOPS_Y_MAX - CYCLOPS_Y_MIN)
		d.pattern = int(rand.uint32() % CYCLOPS_PATTERN_COUNT)
		d.spiral_angle = rand.float32() * math.TAU
		s.fire_timer = 0
	}

	margin := f32(CYCLOPS_OFFSCREEN_MARGIN)
	start_x, end_x: f32
	if d.cross_dir > 0 {
		start_x = -margin
		end_x = f32(SCREEN_WIDTH) + margin
	} else {
		start_x = f32(SCREEN_WIDTH) + margin
		end_x = -margin
	}
	s.pos.x = start_x + (end_x - start_x) * d.cross_t

	color := rl.Color{0xff, 0xcc, 0x99, 0xff}
	s.fire_timer += dt
	fired := false

	switch d.pattern {
	case 0:
		// Aimed fan at the player.
		for s.fire_timer >= CYCLOPS_AIMED_INTERVAL {
			s.fire_timer -= CYCLOPS_AIMED_INTERVAL
			fired = true
			to_player := player_center - s.pos
			if rl.Vector2Length(to_player) < 0.001 {
				to_player = {0, 1}
			}
			base_angle := math.atan2(to_player.y, to_player.x)
			fan_rad := f32(CYCLOPS_AIMED_FAN_DEG) * math.PI / 180.0
			n := f32(CYCLOPS_AIMED_BULLETS)
			for b in 0 ..< CYCLOPS_AIMED_BULLETS {
				t := f32(b) / (n - 1) - 0.5
				angle := base_angle + t * fan_rad
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color, .Enemy, .Sneak, index)
			}
		}
	case 1:
		// Full ring — player must dodge into a gap.
		for s.fire_timer >= CYCLOPS_RING_INTERVAL {
			s.fire_timer -= CYCLOPS_RING_INTERVAL
			fired = true
			step := math.TAU / f32(CYCLOPS_RING_BULLETS)
			for b in 0 ..< CYCLOPS_RING_BULLETS {
				angle := f32(b) * step
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color, .Enemy, .Sneak, index)
			}
		}
	case 2:
		// Rotating opposing arms — continuous spiral hose.
		arm_step := math.TAU / f32(CYCLOPS_SPIRAL_ARMS)
		inc_rad := f32(CYCLOPS_SPIRAL_INC_DEG) * math.PI / 180.0
		for s.fire_timer >= CYCLOPS_SPIRAL_INTERVAL {
			s.fire_timer -= CYCLOPS_SPIRAL_INTERVAL
			fired = true
			for arm in 0 ..< CYCLOPS_SPIRAL_ARMS {
				angle := d.spiral_angle + f32(arm) * arm_step
				vel := rl.Vector2 {
					math.cos(angle) * CYCLOPS_BULLET_SPEED,
					math.sin(angle) * CYCLOPS_BULLET_SPEED,
				}
				spawn_bullet(bullets, s.pos, vel, color, .Enemy, .Sneak, index)
			}
			d.spiral_angle += inc_rad
			if d.spiral_angle >= math.TAU {
				d.spiral_angle -= math.TAU
			}
		}
	}

	if fired {
		play_cyclops_attack_sfx(audio)
	}
}

draw_sneaks :: proc(pool: ^Sneak_Pool) {
	for i in 0 ..< SNEAK_MAX {
		s := &pool.sneaks[i]
		if !s.active {
			continue
		}
		switch s.kind {
		case .Sneak:
			draw_sneak_one(pool, s)
		case .Cyclops:
			draw_cyclops_one(pool, s)
		}
	}
}

@(private = "file")
draw_sneak_one :: proc(pool: ^Sneak_Pool, s: ^Sneak) {
	draw_w := f32(SNEAK_FRAME_W * SNEAK_DRAW_SCALE)
	draw_h := f32(SNEAK_FRAME_H * SNEAK_DRAW_SCALE)
	src := rl.Rectangle{0, 0, f32(SNEAK_FRAME_W), f32(SNEAK_FRAME_H)}
	dst := rl.Rectangle{s.pos.x - draw_w * 0.5, s.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := s.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}

@(private = "file")
draw_cyclops_one :: proc(pool: ^Sneak_Pool, s: ^Sneak) {
	d := &s.data.(Cyclops_Data)
	draw_w := f32(CYCLOPS_FRAME_W * CYCLOPS_DRAW_SCALE)
	draw_h := f32(CYCLOPS_FRAME_H * CYCLOPS_DRAW_SCALE)
	src := rl.Rectangle {
		f32(d.frame * CYCLOPS_FRAME_W),
		0,
		f32(CYCLOPS_FRAME_W),
		f32(CYCLOPS_FRAME_H),
	}
	dst := rl.Rectangle{s.pos.x - draw_w * 0.5, s.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := s.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(pool.cyclops_tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}
}


// #endregion

// #region Enemy Pillars


// Final wave of level 4. Four pillars spawn one per screen corner with a
// random 1..4 number assignment. Numbers are visible for PILLAR_REVEAL_DUR
// seconds, then PILLAR_SHUFFLE_COUNT shuffles smoothly reposition the pillars.
// During Combat only the pillar whose number matches next_kill takes damage;
// out-of-order shots are absorbed without harm. Each pillar fires a continuous
// spiral; spin direction is bound to the corner so diagonally opposite
// pillars always rotate in opposite directions.
//
// Per-corner spin assignment:
//   0 (TL): +1     1 (TR): -1
//   3 (BL): +1     2 (BR): -1
// Diagonals: TL/BR opposite, TR/BL opposite. spin_dir is rebound when a
// shuffle settles so the rule survives reshuffling.

Pillar_Phase :: enum {
	Idle,
	Reveal,
	Shuffle,
	Combat,
}

Pillar :: struct {
	number:     int,
	pos:        rl.Vector2,
	from_pos:   rl.Vector2,
	to_pos:     rl.Vector2,
	hp:         int,
	hit_flash:  f32,
	fire_timer: f32,
	base_angle: f32,
	spin_dir:   f32,
	frame:      int,
	frame_time: f32,
	active:     bool,
}

Pillar_Wave :: struct {
	pillars:       [PILLAR_COUNT]Pillar,
	tex:           rl.Texture2D,
	flash_shader:  rl.Shader,
	phase:         Pillar_Phase,
	phase_t:       f32,
	shuffles_done: int,
	next_kill:     int,
}

init_pillars :: proc(wave: ^Pillar_Wave) {
	wave.tex = rl.LoadTexture("assets/sprites/enemy_pillar.png")
	rl.SetTextureFilter(wave.tex, .POINT)
	wave.flash_shader = load_flash_shader()
	wave.phase = .Idle
}

unload_pillars :: proc(wave: ^Pillar_Wave) {
	rl.UnloadTexture(wave.tex)
	rl.UnloadShader(wave.flash_shader)
}

clear_pillars :: proc(wave: ^Pillar_Wave) {
	for i in 0 ..< PILLAR_COUNT {
		wave.pillars[i].active = false
	}
	wave.phase = .Idle
	wave.phase_t = 0
	wave.shuffles_done = 0
	wave.next_kill = 0
}

spawn_pillar_wave :: proc(wave: ^Pillar_Wave) {
	nums: [PILLAR_COUNT]int = {1, 2, 3, 4}
	for i := PILLAR_COUNT - 1; i > 0; i -= 1 {
		j := int(rand.uint32() % u32(i + 1))
		nums[i], nums[j] = nums[j], nums[i]
	}
	for i in 0 ..< PILLAR_COUNT {
		c := corner_pos(i)
		wave.pillars[i] = Pillar {
			number     = nums[i],
			pos        = c,
			from_pos   = c,
			to_pos     = c,
			hp         = PILLAR_HP,
			spin_dir   = corner_spin(i),
			base_angle = rand.float32() * math.TAU,
			active     = true,
		}
	}
	wave.phase = .Reveal
	wave.phase_t = 0
	wave.shuffles_done = 0
	wave.next_kill = 1
}

update_pillars :: proc(wave: ^Pillar_Wave, bullets: ^Bullet_Pool, dt: f32) {
	if wave.phase == .Idle {
		return
	}

	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		if p.hit_flash > 0 {
			p.hit_flash -= dt
			if p.hit_flash < 0 {
				p.hit_flash = 0
			}
		}
		p.frame_time += dt
		frame_dur: f32 = 1.0 / PILLAR_ANIM_FPS
		if p.frame_time >= frame_dur {
			p.frame_time -= frame_dur
			p.frame = (p.frame + 1) % PILLAR_FRAMES
		}
	}

	wave.phase_t += dt

	switch wave.phase {
	case .Idle:
	// unreachable
	case .Reveal:
		if wave.phase_t >= PILLAR_REVEAL_DUR {
			start_shuffle(wave)
		}
	case .Shuffle:
		progress: f32 = wave.phase_t / PILLAR_SHUFFLE_DUR
		if progress > 1 {
			progress = 1
		}
		eased := smoothstep(progress)
		for i in 0 ..< PILLAR_COUNT {
			p := &wave.pillars[i]
			if !p.active {
				continue
			}
			p.pos.x = p.from_pos.x + (p.to_pos.x - p.from_pos.x) * eased
			p.pos.y = p.from_pos.y + (p.to_pos.y - p.from_pos.y) * eased
		}
		if wave.phase_t >= PILLAR_SHUFFLE_DUR {
			for i in 0 ..< PILLAR_COUNT {
				p := &wave.pillars[i]
				if !p.active {
					continue
				}
				p.pos = p.to_pos
				// Rebind spin_dir to the corner the pillar settled into so the
				// "opposite corners spin opposite" invariant holds post-shuffle.
				p.spin_dir = corner_spin(corner_index_for(p.pos))
			}
			wave.shuffles_done += 1
			if wave.shuffles_done >= PILLAR_SHUFFLE_COUNT {
				wave.phase = .Combat
				wave.phase_t = 0
			} else {
				start_shuffle(wave)
			}
		}
	case .Combat:
		update_pillar_combat(wave, bullets, dt)
	}
}

@(private = "file")
start_shuffle :: proc(wave: ^Pillar_Wave) {
	perm: [PILLAR_COUNT]int = {0, 1, 2, 3}
	// Reshuffle until the permutation moves at least one pillar — pure identity
	// would defeat the visual-tracking rule. 8 attempts is overkill (1/24 per
	// try) but keeps the loop bounded.
	for attempt in 0 ..< 8 {
		_ = attempt
		for i := PILLAR_COUNT - 1; i > 0; i -= 1 {
			j := int(rand.uint32() % u32(i + 1))
			perm[i], perm[j] = perm[j], perm[i]
		}
		identity := true
		for i in 0 ..< PILLAR_COUNT {
			if perm[i] != i {
				identity = false
				break
			}
		}
		if !identity {
			break
		}
	}
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		p.from_pos = p.pos
		p.to_pos = corner_pos(perm[i])
	}
	wave.phase = .Shuffle
	wave.phase_t = 0
}

@(private = "file")
update_pillar_combat :: proc(wave: ^Pillar_Wave, bullets: ^Bullet_Pool, dt: f32) {
	color := rl.Color{255, 220, 100, 255}
	inc_rad: f32 = PILLAR_ANGLE_INC_DEG * math.PI / 180.0
	row_step: f32 = math.TAU / f32(PILLAR_BULLETS_PER_BURST)
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		p.fire_timer += dt
		for p.fire_timer >= PILLAR_FIRE_INTERVAL {
			p.fire_timer -= PILLAR_FIRE_INTERVAL
			for r in 0 ..< PILLAR_BULLETS_PER_BURST {
				ang := p.base_angle + f32(r) * row_step
				vel := rl.Vector2 {
					math.cos(ang) * PILLAR_BULLET_SPEED,
					math.sin(ang) * PILLAR_BULLET_SPEED,
				}
				spawn_bullet(bullets, p.pos, vel, color, .Enemy, .Pillar, i)
			}
			p.base_angle += inc_rad * p.spin_dir
			if p.base_angle >= math.TAU {
				p.base_angle -= math.TAU
			}
			if p.base_angle < 0 {
				p.base_angle += math.TAU
			}
		}
	}
}

// applied = damage actually landed; killed = pillar reached 0 hp this call.
// Out-of-order shots and shots taken outside Combat absorb the projectile
// (callers always treat the projectile as consumed) but apply no damage.
damage_pillar :: proc(wave: ^Pillar_Wave, idx: int, amount: int) -> (applied: bool, killed: bool) {
	if idx < 0 || idx >= PILLAR_COUNT {
		return false, false
	}
	p := &wave.pillars[idx]
	if !p.active {
		return false, false
	}
	if wave.phase != .Combat {
		return false, false
	}
	if p.number != wave.next_kill {
		return false, false
	}
	p.hp -= amount
	p.hit_flash = PILLAR_HIT_FLASH_TIME
	if p.hp <= 0 {
		p.hp = 0
		p.active = false
		wave.next_kill += 1
		return true, true
	}
	return true, false
}

pillar_center :: proc(p: ^Pillar) -> rl.Vector2 {
	return p.pos
}

pillar_hit_radius :: proc(p: ^Pillar) -> f32 {
	return PILLAR_HIT_RADIUS
}

pillar_wave_complete :: proc(wave: ^Pillar_Wave) -> bool {
	if wave.phase != .Combat {
		return false
	}
	for i in 0 ..< PILLAR_COUNT {
		if wave.pillars[i].active {
			return false
		}
	}
	return true
}

@(private = "file")
corner_pos :: proc(idx: int) -> rl.Vector2 {
	switch idx {
	case 0:
		return {PILLAR_CORNER_MARGIN, PILLAR_CORNER_MARGIN}
	case 1:
		return {SCREEN_WIDTH - PILLAR_CORNER_MARGIN, PILLAR_CORNER_MARGIN}
	case 2:
		return {SCREEN_WIDTH - PILLAR_CORNER_MARGIN, SCREEN_HEIGHT - PILLAR_CORNER_MARGIN}
	case 3:
		return {PILLAR_CORNER_MARGIN, SCREEN_HEIGHT - PILLAR_CORNER_MARGIN}
	}
	return {0, 0}
}

@(private = "file")
corner_spin :: proc(idx: int) -> f32 {
	switch idx {
	case 0, 3:
		return 1
	case 1, 2:
		return -1
	}
	return 1
}

@(private = "file")
corner_index_for :: proc(p: rl.Vector2) -> int {
	best := 0
	best_dsq: f32 = 1e9
	for i in 0 ..< PILLAR_COUNT {
		c := corner_pos(i)
		dx := p.x - c.x
		dy := p.y - c.y
		d := dx * dx + dy * dy
		if d < best_dsq {
			best_dsq = d
			best = i
		}
	}
	return best
}

draw_pillars :: proc(wave: ^Pillar_Wave) {
	if wave.phase == .Idle {
		return
	}
	for i in 0 ..< PILLAR_COUNT {
		p := &wave.pillars[i]
		if !p.active {
			continue
		}
		draw_w := f32(PILLAR_FRAME_W * PILLAR_DRAW_SCALE)
		draw_h := f32(PILLAR_FRAME_H * PILLAR_DRAW_SCALE)
		src := rl.Rectangle{f32(p.frame * PILLAR_FRAME_W), 0, f32(PILLAR_FRAME_W), f32(PILLAR_FRAME_H)}
		dst := rl.Rectangle{p.pos.x - draw_w * 0.5, p.pos.y - draw_h * 0.5, draw_w, draw_h}
		flashing := p.hit_flash > 0
		if flashing {
			rl.BeginShaderMode(wave.flash_shader)
		}
		rl.DrawTexturePro(wave.tex, src, dst, {0, 0}, 0, rl.WHITE)
		if flashing {
			rl.EndShaderMode()
		}
	}

	if wave.phase == .Reveal {
		for i in 0 ..< PILLAR_COUNT {
			p := &wave.pillars[i]
			if !p.active {
				continue
			}
			num := fmt.ctprintf("%d", p.number)
			tw := rl.MeasureText(num, PILLAR_NUMBER_FONT_SIZE)
			tx := i32(p.pos.x) - tw / 2
			half_h := i32(PILLAR_FRAME_H * PILLAR_DRAW_SCALE) / 2
			ty: i32
			if p.pos.y < SCREEN_HEIGHT * 0.5 {
				ty = i32(p.pos.y) + half_h + 4
			} else {
				ty = i32(p.pos.y) - half_h - PILLAR_NUMBER_FONT_SIZE - 4
			}
			rl.DrawText(num, tx + 1, ty + 1, PILLAR_NUMBER_FONT_SIZE, rl.BLACK)
			rl.DrawText(num, tx, ty, PILLAR_NUMBER_FONT_SIZE, rl.YELLOW)
		}
	}
}

// #endregion

// #region Bosses: Golgatha and Morgan



Boss_Kind :: enum {
	Golgatha,
	Morgan,
	Ancient_Guardian,
}

// One of GUARDIAN_ORB_COUNT orbs orbiting the Ancient Guardian. Position is
// recomputed each frame from the boss center + shared orbit_phase + this orb's
// fixed angle_offset. Only the orb at boss.vulnerable_orb_idx takes damage;
// shots against any other orb are absorbed (blocked particles, no hp loss).
Guardian_Orb :: struct {
	angle_offset: f32,
	pos:          rl.Vector2,
	spiral_angle: f32,
	spin_dir:     f32,
	fire_timer:   f32,
	hp:           int,
	hit_flash:    f32,
	active:       bool,
}

Boss :: struct {
	pos:               rl.Vector2,
	sway_phase:        f32,
	base_angle:        f32,
	fire_timer:        f32,
	sneak_spawn_timer: f32,
	frame:             int,
	frame_time:        f32,
	hp:                int,
	hit_flash:         f32,
	active:            bool,
	defeated:          bool,
	kind:              Boss_Kind,
	// Morgan-only state. phase counts up 1..3; on phase advance hp resets to
	// MORGAN_PHASE_HP. shield_hp is non-zero only in phase 3; while > 0 it
	// absorbs damage instead of hp. shield_recover_timer counts down from
	// MORGAN_SHIELD_RECOVER_TIME after a break, and the shield refills when it
	// reaches zero. orb_timer is the cadence for the burst-on-EOL energy orbs.
	phase:                int,
	shield_hp:            int,
	shield_recover_timer: f32,
	orb_timer:            f32,
	// Counts down from MORGAN_PHASE_TRANSITION_DUR while the boss is between
	// phases. > 0 means the world is frozen and the HP bar is refilling 0 ->
	// MORGAN_PHASE_HP. Defeat does NOT trigger a transition.
	phase_transition_t: f32,
	// One-shot scream cue: Golgatha plays sfx_golgotha_scream the first frame
	// after spawn. Reset in spawn_boss so a fresh fight re-triggers it.
	scream_played: bool,
	// Ancient Guardian audio hooks. intro_played gates a one-shot stinger on
	// fight start. orb_just_died is a single-frame edge set inside
	// damage_guardian_orb when an orb hits 0; main.odin drains it to play a
	// random voice cue. A bool (not counter) is fine — back-to-back kills in
	// the same frame collapsing into one cue is desirable, not a bug.
	intro_played:   bool,
	orb_just_died:  bool,
	// Death animation flag (Morgan + Golgatha). While dying, normal update is
	// skipped, the boss is invulnerable, and `frame`/`frame_time` advance
	// through the kind-specific death sprite. When the last frame plays out,
	// active flips false and defeated flips true so the existing
	// victory_pending flow kicks in. Ancient Guardian doesn't use this.
	dying: bool,
	// Ancient Guardian state. orbs orbit the boss at orbit_phase rad; only
	// vulnerable_orb_idx takes damage. While any orb is active the boss itself
	// is invulnerable. When all 6 orbs die, in_window flips true for
	// GUARDIAN_WINDOW_DURATION seconds; when the timer expires (or all orbs
	// would otherwise be down), orbs respawn and the cycle restarts.
	orbs:                [GUARDIAN_ORB_COUNT]Guardian_Orb,
	orbit_phase:         f32,
	vulnerable_orb_idx:  int,
	vulnerable_timer:    f32,
	window_timer:        f32,
	in_window:           bool,
}

// True while Morgan is between phases. Main loop uses this to freeze the
// player + bullets so the only thing ticking is the boss itself, which is
// running the transition timer + HP refill.
boss_phase_pausing :: proc(b: ^Boss) -> bool {
	return b.kind == .Morgan && b.phase_transition_t > 0
}

Boss_Pool :: struct {
	boss:               Boss,
	tex:                rl.Texture2D,
	golgatha_death_tex: rl.Texture2D,
	morgan_idle_tex:    rl.Texture2D,
	morgan_death_tex:   rl.Texture2D,
	guardian_tex:       rl.Texture2D,
	flash_shader:       rl.Shader,
}

init_boss :: proc(pool: ^Boss_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_boss1_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.golgatha_death_tex = rl.LoadTexture("assets/sprites/Boss_Golgotha_Dies.png")
	rl.SetTextureFilter(pool.golgatha_death_tex, .POINT)
	pool.morgan_idle_tex = rl.LoadTexture("assets/sprites/boss_morgan_idle.png")
	rl.SetTextureFilter(pool.morgan_idle_tex, .POINT)
	pool.morgan_death_tex = rl.LoadTexture("assets/sprites/boss_morgan_dies.png")
	rl.SetTextureFilter(pool.morgan_death_tex, .POINT)
	pool.guardian_tex = rl.LoadTexture("assets/sprites/final_boss_ancient_guardian.png")
	rl.SetTextureFilter(pool.guardian_tex, .POINT)
	pool.flash_shader = load_flash_shader()
	pool.boss.active = false
}

unload_boss :: proc(pool: ^Boss_Pool) {
	rl.UnloadTexture(pool.tex)
	rl.UnloadTexture(pool.golgatha_death_tex)
	rl.UnloadTexture(pool.morgan_idle_tex)
	rl.UnloadTexture(pool.morgan_death_tex)
	rl.UnloadTexture(pool.guardian_tex)
	rl.UnloadShader(pool.flash_shader)
}

boss_hit_radius :: proc(b: ^Boss) -> f32 {
	if b.kind == .Morgan {
		return MORGAN_HIT_RADIUS
	}
	if b.kind == .Ancient_Guardian {
		return GUARDIAN_HIT_RADIUS
	}
	return BOSS_HIT_RADIUS
}

// True only when the player's projectiles can land hp on the boss body.
// Ancient Guardian is invulnerable until all six orbs are down and the 12s
// damage window is open; everyone else is always damageable while alive.
boss_can_take_damage :: proc(b: ^Boss) -> bool {
	if !b.active {
		return false
	}
	if b.dying {
		return false
	}
	if b.kind == .Ancient_Guardian {
		return b.in_window
	}
	return true
}

spawn_boss :: proc(pool: ^Boss_Pool) {
	pool.boss = Boss {
		pos               = {BOSS_SPAWN_X, BOSS_SPAWN_Y},
		sway_phase        = 0,
		base_angle        = 0,
		fire_timer        = 0,
		sneak_spawn_timer = BOSS_SNEAK_SPAWN_INTERVAL,
		frame             = 0,
		frame_time        = 0,
		hp                = BOSS_MAX_HP,
		hit_flash         = 0,
		active            = true,
		kind              = .Golgatha,
	}
}

spawn_morgan :: proc(pool: ^Boss_Pool) {
	pool.boss = Boss {
		pos        = {MORGAN_SPAWN_X, MORGAN_SPAWN_Y},
		hp         = MORGAN_PHASE_HP,
		active     = true,
		kind       = .Morgan,
		phase      = 1,
		orb_timer  = MORGAN_ORB_INTERVAL,
	}
}

spawn_ancient_guardian :: proc(pool: ^Boss_Pool) {
	pool.boss = Boss {
		pos                = {GUARDIAN_SPAWN_X, GUARDIAN_SPAWN_Y},
		hp                 = GUARDIAN_TOTAL_HP,
		active             = true,
		kind               = .Ancient_Guardian,
		vulnerable_orb_idx = -1,
	}
	spawn_guardian_orbs(&pool.boss)
}

// Resets all six orbs to full hp and re-randomizes which one is vulnerable.
// Called both on initial spawn and on each respawn at the end of the damage
// window. Spin direction alternates so the screen reads as opposing spirals
// rather than one synchronized swirl.
spawn_guardian_orbs :: proc(b: ^Boss) {
	for i in 0 ..< GUARDIAN_ORB_COUNT {
		spin: f32 = 1
		if i % 2 == 1 {
			spin = -1
		}
		b.orbs[i] = Guardian_Orb {
			angle_offset = f32(i) * math.TAU / f32(GUARDIAN_ORB_COUNT),
			spiral_angle = rand.float32() * math.TAU,
			spin_dir     = spin,
			fire_timer   = rand.float32() * GUARDIAN_ORB_FIRE_INTERVAL,
			hp           = GUARDIAN_ORB_HP,
			active       = true,
		}
	}
	b.in_window = false
	b.window_timer = 0
	b.vulnerable_orb_idx = pick_random_alive_orb(b, -1)
	b.vulnerable_timer = GUARDIAN_ORB_VULNERABLE_TIME
}

// Picks a random active orb other than `avoid`. Returns -1 if none are alive.
// Used to seed the initial vulnerable orb (avoid = -1) and to rotate the
// vulnerability without picking the same one back-to-back.
@(private = "file")
pick_random_alive_orb :: proc(b: ^Boss, avoid: int) -> int {
	candidates: [GUARDIAN_ORB_COUNT]int
	n := 0
	for i in 0 ..< GUARDIAN_ORB_COUNT {
		if !b.orbs[i].active {
			continue
		}
		if i == avoid {
			continue
		}
		candidates[n] = i
		n += 1
	}
	if n == 0 {
		// All other orbs are dead; fall back to the only one alive (which may
		// be `avoid`) so the player still has a target.
		for i in 0 ..< GUARDIAN_ORB_COUNT {
			if b.orbs[i].active {
				return i
			}
		}
		return -1
	}
	return candidates[int(rand.uint32() % u32(n))]
}

guardian_orbs_alive :: proc(b: ^Boss) -> int {
	n := 0
	for i in 0 ..< GUARDIAN_ORB_COUNT {
		if b.orbs[i].active {
			n += 1
		}
	}
	return n
}

// Damages the orb at `idx` if it is the currently-vulnerable one. Returns
// (applied, killed) the same way damage_pillar does so callers can pick
// between impact particles and the "bullet absorbed but no damage" feedback.
damage_guardian_orb :: proc(b: ^Boss, idx: int, amount: int) -> (applied: bool, killed: bool) {
	if b.kind != .Ancient_Guardian {
		return false, false
	}
	if idx < 0 || idx >= GUARDIAN_ORB_COUNT {
		return false, false
	}
	o := &b.orbs[idx]
	if !o.active {
		return false, false
	}
	if b.vulnerable_orb_idx != idx {
		return false, false
	}
	o.hp -= amount
	o.hit_flash = GUARDIAN_HIT_FLASH_TIME
	if o.hp <= 0 {
		o.hp = 0
		o.active = false
		b.orb_just_died = true
		// Pick a new vulnerable orb among the remaining; if none are alive
		// flip into the damage window. The window timer drives both the boss
		// damageable state and the orb respawn at its expiry.
		alive := guardian_orbs_alive(b)
		if alive == 0 {
			b.vulnerable_orb_idx = -1
			b.in_window = true
			b.window_timer = GUARDIAN_WINDOW_DURATION
		} else {
			b.vulnerable_orb_idx = pick_random_alive_orb(b, idx)
			b.vulnerable_timer = GUARDIAN_ORB_VULNERABLE_TIME
		}
		return true, true
	}
	return true, false
}

boss_center :: proc(b: ^Boss) -> rl.Vector2 {
	return b.pos
}

damage_boss :: proc(b: ^Boss, amount: int) -> (killed: bool) {
	if !b.active {
		return false
	}
	if b.kind == .Ancient_Guardian {
		// Body soaks damage only inside the 12s window. While orbs are active
		// the body doesn't even flash so the player has a clear "can't hurt me
		// yet" read; orbs flash on their own when shot.
		if !b.in_window {
			return false
		}
		b.hit_flash = BOSS_HIT_FLASH_TIME
		b.hp -= amount
		if b.hp <= 0 {
			b.hp = 0
			b.active = false
			b.defeated = true
			return true
		}
		return false
	}
	b.hit_flash = BOSS_HIT_FLASH_TIME
	if b.kind == .Morgan {
		// Phase-3 shield soaks all damage until it breaks; remaining damage does
		// NOT carry over to hp (gives the shield a real defensive role).
		if b.phase == 3 && b.shield_hp > 0 {
			b.shield_hp -= amount
			if b.shield_hp <= 0 {
				b.shield_hp = 0
				b.shield_recover_timer = MORGAN_SHIELD_RECOVER_TIME
			}
			return false
		}
		b.hp -= amount
		if b.hp <= 0 {
			b.hp = 0
			if b.phase >= 3 {
				// Enter the death animation. active stays true so update_boss
				// keeps ticking; defeated flips when the last death frame plays.
				b.dying = true
				b.frame = 0
				b.frame_time = 0
				b.hit_flash = 0
				return true
			}
			// Enter the inter-phase pause. The HP bar is left at 0 and the
			// transition timer drives both the refill animation and the
			// gameplay freeze (see boss_phase_pausing). Phase index increments
			// now so phase-specific spawns (shield, sneaks, etc.) line up.
			b.phase += 1
			b.fire_timer = 0
			b.base_angle = 0
			b.orb_timer = MORGAN_ORB_INTERVAL
			b.sneak_spawn_timer = MORGAN_P2_SNEAK_INTERVAL
			b.phase_transition_t = MORGAN_PHASE_TRANSITION_DUR
			if b.phase == 3 {
				b.shield_hp = MORGAN_SHIELD_HP
				b.shield_recover_timer = 0
			}
		}
		return false
	}
	b.hp -= amount
	if b.hp <= 0 {
		b.hp = 0
		// Golgatha enters the death animation; defeated flips when the last
		// death frame plays out (see tick_golgatha_death).
		b.dying = true
		b.frame = 0
		b.frame_time = 0
		b.hit_flash = 0
		return true
	}
	return false
}

update_boss :: proc(pool: ^Boss_Pool, bullets: ^Bullet_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	b := &pool.boss
	if !b.active {
		return
	}

	if b.dying {
		if b.kind == .Morgan {
			tick_morgan_death(b, dt)
		} else if b.kind == .Golgatha {
			tick_golgatha_death(b, dt)
		}
		return
	}

	if b.hit_flash > 0 {
		b.hit_flash -= dt
		if b.hit_flash < 0 {
			b.hit_flash = 0
		}
	}

	if b.kind == .Morgan {
		update_morgan(b, bullets, sneaks, dt)
		return
	}

	if b.kind == .Ancient_Guardian {
		update_ancient_guardian(b, bullets, dt)
		return
	}

	b.sway_phase += BOSS_SWAY_FREQ * math.TAU * dt
	if b.sway_phase >= math.TAU {
		b.sway_phase -= math.TAU
	}
	// Gerono lemniscate (figure-8 lying on its side): sin*cos = sin(2t)/2 puts the
	// vertical drift at twice the horizontal cadence so the boss cuts a smooth ∞
	// instead of sliding flat across the screen.
	sx := math.sin(b.sway_phase)
	cx := math.cos(b.sway_phase)
	b.pos.x = BOSS_SPAWN_X + sx * BOSS_SWAY_AMPLITUDE
	b.pos.y = BOSS_SPAWN_Y + sx * cx * BOSS_SWAY_AMPLITUDE * BOSS_FIGURE8_Y_RATIO

	b.frame_time += dt
	frame_dur: f32 = 1.0 / BOSS_ANIM_FPS
	if b.frame_time >= frame_dur {
		b.frame_time -= frame_dur
		b.frame = (b.frame + 1) % BOSS_FRAMES
	}

	// Continuous spiral: every BOSS_FIRE_INTERVAL, emit BOSS_BULLET_ROWS evenly
	// spaced bullets around base_angle, then rotate base_angle by the increment.
	// Mirrors ~/bhport defaults: 6 rows, 5° per burst, ~2 frame cadence.
	b.fire_timer += dt
	row_step: f32 = math.TAU / f32(BOSS_BULLET_ROWS)
	inc_rad: f32 = f32(BOSS_ANGLE_INCREMENT_DEG) * math.PI / 180.0
	color := rl.Color{0xff, 0xcc, 0xcc, 0xff}
	for b.fire_timer >= BOSS_FIRE_INTERVAL {
		b.fire_timer -= BOSS_FIRE_INTERVAL
		for r in 0 ..< BOSS_BULLET_ROWS {
			ang := b.base_angle + f32(r) * row_step
			vel := rl.Vector2 {
				math.cos(ang) * BOSS_BULLET_SPEED,
				math.sin(ang) * BOSS_BULLET_SPEED,
			}
			spawn_bullet(bullets, b.pos, vel, color, .Enemy, .Boss, 0)
		}
		b.base_angle += inc_rad
		if b.base_angle >= math.TAU {
			b.base_angle -= math.TAU
		}
	}

	b.sneak_spawn_timer -= dt
	if b.sneak_spawn_timer <= 0 {
		b.sneak_spawn_timer = BOSS_SNEAK_SPAWN_INTERVAL
		try_spawn_sneak(sneaks)
	}
}

draw_boss_hud :: proc(pool: ^Boss_Pool) {
	b := &pool.boss
	if !b.active {
		return
	}

	bar_x: i32 = (SCREEN_WIDTH - BOSS_HUD_BAR_W) / 2
	bar_y: i32 = BOSS_HUD_BAR_Y

	rl.DrawRectangle(bar_x - 2, bar_y - 2, BOSS_HUD_BAR_W + 4, BOSS_HUD_BAR_H + 4, rl.BLACK)
	rl.DrawRectangle(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.Color{40, 10, 10, 255})

	hp := b.hp
	if hp < 0 {
		hp = 0
	}
	max_hp := BOSS_MAX_HP
	if b.kind == .Morgan {
		max_hp = MORGAN_PHASE_HP
	}
	if b.kind == .Ancient_Guardian {
		max_hp = GUARDIAN_TOTAL_HP
	}
	fill_w := i32(f32(BOSS_HUD_BAR_W) * f32(hp) / f32(max_hp))
	if fill_w > 0 {
		rl.DrawRectangle(bar_x, bar_y, fill_w, BOSS_HUD_BAR_H, rl.Color{220, 40, 60, 255})
		rl.DrawRectangle(bar_x, bar_y, fill_w, 2, rl.Color{255, 120, 130, 255})
	}
	rl.DrawRectangleLines(bar_x, bar_y, BOSS_HUD_BAR_W, BOSS_HUD_BAR_H, rl.WHITE)

	name: cstring = BOSS_NAME
	if b.kind == .Morgan {
		name = MORGAN_NAME
	}
	if b.kind == .Ancient_Guardian {
		name = GUARDIAN_NAME
	}
	text_w := rl.MeasureText(name, BOSS_NAME_FONT_SIZE)
	name_x := (i32(SCREEN_WIDTH) - text_w) / 2
	rl.DrawText(name, name_x + 1, BOSS_HUD_NAME_Y + 1, BOSS_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, name_x, BOSS_HUD_NAME_Y, BOSS_NAME_FONT_SIZE, rl.WHITE)

	// Phase-3 shield bar sits right below the HP bar, narrower so it reads as a
	// distinct sub-stat. Stays drawn (empty) while recovering so the player can
	// anticipate the comeback. The phase count itself is not displayed — players
	// learn there are more phases by watching the HP bar refill.
	if b.kind == .Morgan && b.phase == 3 {
		sh_w: i32 = BOSS_HUD_BAR_W * 2 / 3
		sh_h: i32 = 4
		sh_x := (SCREEN_WIDTH - sh_w) / 2
		sh_y := bar_y + BOSS_HUD_BAR_H + 3
		rl.DrawRectangle(sh_x - 1, sh_y - 1, sh_w + 2, sh_h + 2, rl.BLACK)
		rl.DrawRectangle(sh_x, sh_y, sh_w, sh_h, rl.Color{20, 30, 50, 255})
		shield_fill := i32(f32(sh_w) * f32(b.shield_hp) / f32(MORGAN_SHIELD_HP))
		if shield_fill > 0 {
			rl.DrawRectangle(sh_x, sh_y, shield_fill, sh_h, rl.Color{120, 200, 255, 255})
		}
		rl.DrawRectangleLines(sh_x, sh_y, sh_w, sh_h, rl.Color{200, 230, 255, 255})
	}

	// Compound orb-pool bar. Only the highlighted orb takes damage at any
	// moment, but partial damage to non-killed orbs persists across vulnerability
	// rotations — without this bar that progress is invisible and the fight
	// feels static. Refills on the periodic orb respawn, which is the cue.
	if b.kind == .Ancient_Guardian {
		orb_hp_total: int
		for i in 0 ..< GUARDIAN_ORB_COUNT {
			orb_hp_total += b.orbs[i].hp
		}
		max_orb_hp := GUARDIAN_ORB_COUNT * GUARDIAN_ORB_HP
		sh_w: i32 = BOSS_HUD_BAR_W * 2 / 3
		sh_h: i32 = 4
		sh_x := (SCREEN_WIDTH - sh_w) / 2
		sh_y := bar_y + BOSS_HUD_BAR_H + 3
		rl.DrawRectangle(sh_x - 1, sh_y - 1, sh_w + 2, sh_h + 2, rl.BLACK)
		rl.DrawRectangle(sh_x, sh_y, sh_w, sh_h, rl.Color{20, 30, 50, 255})
		orb_fill := i32(f32(sh_w) * f32(orb_hp_total) / f32(max_orb_hp))
		if orb_fill > 0 {
			rl.DrawRectangle(sh_x, sh_y, orb_fill, sh_h, rl.Color{120, 200, 255, 255})
		}
		rl.DrawRectangleLines(sh_x, sh_y, sh_w, sh_h, rl.Color{200, 230, 255, 255})
	}
}

draw_boss :: proc(pool: ^Boss_Pool) {
	b := &pool.boss
	if !b.active {
		return
	}

	tex := pool.tex
	frame_w := i32(BOSS_FRAME_W)
	frame_h := i32(BOSS_FRAME_H)
	scale: f32 = BOSS_DRAW_SCALE
	if b.kind == .Golgatha && b.dying {
		tex = pool.golgatha_death_tex
	}
	if b.kind == .Morgan {
		tex = pool.morgan_idle_tex
		if b.dying {
			tex = pool.morgan_death_tex
		}
		frame_w = MORGAN_FRAME_W
		frame_h = MORGAN_FRAME_H
		scale = MORGAN_DRAW_SCALE
	}
	if b.kind == .Ancient_Guardian {
		tex = pool.guardian_tex
		frame_w = GUARDIAN_FRAME_W
		frame_h = GUARDIAN_FRAME_H
		scale = GUARDIAN_DRAW_SCALE
	}
	draw_w := f32(frame_w) * scale
	draw_h := f32(frame_h) * scale
	src := rl.Rectangle{f32(i32(b.frame) * frame_w), 0, f32(frame_w), f32(frame_h)}
	dst := rl.Rectangle{b.pos.x - draw_w * 0.5, b.pos.y - draw_h * 0.5, draw_w, draw_h}
	flashing := b.hit_flash > 0
	if flashing {
		rl.BeginShaderMode(pool.flash_shader)
	}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}

	// Phase-3 shield: pulsing ring around Morgan while shield_hp > 0. Drawn after
	// the body so it sits on top.
	if b.kind == .Morgan && b.phase == 3 && b.shield_hp > 0 {
		pulse := 0.5 + 0.5 * math.sin(f32(rl.GetTime()) * 4.0)
		ring_r := MORGAN_HIT_RADIUS + 4 + pulse * 2
		alpha := u8(120 + pulse * 80)
		rl.DrawCircleLinesV(b.pos, ring_r, rl.Color{120, 200, 255, alpha})
		rl.DrawCircleLinesV(b.pos, ring_r - 1, rl.Color{200, 230, 255, alpha / 2})
	}

	if b.kind == .Ancient_Guardian {
		draw_guardian_orbs(b)
	}
}

@(private = "file")
draw_guardian_orbs :: proc(b: ^Boss) {
	t := f32(rl.GetTime())
	for i in 0 ..< GUARDIAN_ORB_COUNT {
		o := &b.orbs[i]
		if !o.active {
			continue
		}
		core: rl.Color
		mid:  rl.Color
		glow: rl.Color
		if i == b.vulnerable_orb_idx {
			pulse := 0.5 + 0.5 * math.sin(t * 6.0)
			a_glow := u8(70 + pulse * 80)
			a_mid := u8(180 + pulse * 60)
			core = rl.Color{255, 250, 220, 255}
			mid = rl.Color{255, 220, 100, a_mid}
			glow = rl.Color{255, 180, 60, a_glow}
		} else {
			core = rl.Color{220, 200, 255, 235}
			mid = rl.Color{160, 100, 220, 200}
			glow = rl.Color{90, 50, 160, 110}
		}
		flashing := o.hit_flash > 0
		if flashing {
			core = rl.WHITE
			mid = rl.WHITE
			glow = rl.Color{255, 255, 255, 180}
		}
		rl.DrawCircleV(o.pos, GUARDIAN_ORB_RADIUS * 1.5, glow)
		rl.DrawCircleV(o.pos, GUARDIAN_ORB_RADIUS, mid)
		rl.DrawCircleV(o.pos, GUARDIAN_ORB_RADIUS * 0.45, core)
		rl.DrawCircleLinesV(o.pos, GUARDIAN_ORB_RADIUS, rl.Color{255, 255, 255, 200})
	}
}

@(private = "file")
tick_morgan_death :: proc(b: ^Boss, dt: f32) {
	b.frame_time += dt
	for b.frame_time >= MORGAN_DEATH_FRAME_DUR {
		b.frame_time -= MORGAN_DEATH_FRAME_DUR
		if b.frame >= MORGAN_DEATH_FRAMES - 1 {
			b.active = false
			b.defeated = true
			return
		}
		b.frame += 1
	}
}

@(private = "file")
tick_golgatha_death :: proc(b: ^Boss, dt: f32) {
	b.frame_time += dt
	for b.frame_time >= BOSS_DEATH_FRAME_DUR {
		b.frame_time -= BOSS_DEATH_FRAME_DUR
		if b.frame >= BOSS_DEATH_FRAMES - 1 {
			b.active = false
			b.defeated = true
			return
		}
		b.frame += 1
	}
}

@(private = "file")
update_morgan :: proc(b: ^Boss, bullets: ^Bullet_Pool, sneaks: ^Sneak_Pool, dt: f32) {
	// Inter-phase pause: only refill the HP bar; skip movement, spiral, orbs,
	// sneak summons, animation. The world is frozen by the main loop.
	if b.phase_transition_t > 0 {
		b.phase_transition_t -= dt
		if b.phase_transition_t <= 0 {
			b.phase_transition_t = 0
			b.hp = MORGAN_PHASE_HP
		} else {
			progress := 1 - b.phase_transition_t / MORGAN_PHASE_TRANSITION_DUR
			b.hp = int(f32(MORGAN_PHASE_HP) * progress)
		}
		return
	}

	sway_amp, sway_freq, fire_int, angle_inc_deg, bullet_speed: f32
	rows: int
	switch b.phase {
	case 1:
		sway_amp, sway_freq = MORGAN_P1_SWAY_AMP, MORGAN_P1_SWAY_FREQ
		fire_int, rows = MORGAN_P1_FIRE_INTERVAL, MORGAN_P1_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P1_ANGLE_INC_DEG, MORGAN_P1_BULLET_SPEED
	case 2:
		sway_amp, sway_freq = MORGAN_P2_SWAY_AMP, MORGAN_P2_SWAY_FREQ
		fire_int, rows = MORGAN_P2_FIRE_INTERVAL, MORGAN_P2_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P2_ANGLE_INC_DEG, MORGAN_P2_BULLET_SPEED
	case:
		sway_amp, sway_freq = MORGAN_P3_SWAY_AMP, MORGAN_P3_SWAY_FREQ
		fire_int, rows = MORGAN_P3_FIRE_INTERVAL, MORGAN_P3_ROWS
		angle_inc_deg, bullet_speed = MORGAN_P3_ANGLE_INC_DEG, MORGAN_P3_BULLET_SPEED
	}

	b.sway_phase += sway_freq * math.TAU * dt
	if b.sway_phase >= math.TAU {
		b.sway_phase -= math.TAU
	}
	sx := math.sin(b.sway_phase)
	cx := math.cos(b.sway_phase)
	b.pos.x = MORGAN_SPAWN_X + sx * sway_amp
	b.pos.y = MORGAN_SPAWN_Y + sx * cx * sway_amp * BOSS_FIGURE8_Y_RATIO

	b.frame_time += dt
	frame_dur: f32 = 1.0 / MORGAN_ANIM_FPS
	if b.frame_time >= frame_dur {
		b.frame_time -= frame_dur
		b.frame = (b.frame + 1) % MORGAN_IDLE_FRAMES
	}

	color := rl.Color{200, 140, 255, 255}
	row_step: f32 = math.TAU / f32(rows)
	inc_rad: f32 = angle_inc_deg * math.PI / 180.0
	b.fire_timer += dt
	for b.fire_timer >= fire_int {
		b.fire_timer -= fire_int
		for r in 0 ..< rows {
			ang := b.base_angle + f32(r) * row_step
			vel := rl.Vector2{math.cos(ang) * bullet_speed, math.sin(ang) * bullet_speed}
			spawn_bullet(bullets, b.pos, vel, color, .Enemy, .Boss, 0)
		}
		b.base_angle += inc_rad
		if b.base_angle >= math.TAU {
			b.base_angle -= math.TAU
		}
	}

	// Energy orbs: aimed straight down with a small lateral wobble.
	b.orb_timer -= dt
	if b.orb_timer <= 0 {
		b.orb_timer = MORGAN_ORB_INTERVAL
		wobble := math.sin(b.sway_phase) * 0.3
		ang: f32 = math.PI / 2 + wobble
		vel := rl.Vector2{math.cos(ang) * MORGAN_ORB_SPEED, math.sin(ang) * MORGAN_ORB_SPEED}
		spawn_energy_orb(bullets, b.pos, vel)
	}

	if b.phase == 2 {
		b.sneak_spawn_timer -= dt
		if b.sneak_spawn_timer <= 0 {
			b.sneak_spawn_timer = MORGAN_P2_SNEAK_INTERVAL
			force_spawn_sneak(sneaks)
		}
	}

	if b.phase == 3 && b.shield_hp <= 0 && b.shield_recover_timer > 0 {
		b.shield_recover_timer -= dt
		if b.shield_recover_timer <= 0 {
			b.shield_recover_timer = 0
			b.shield_hp = MORGAN_SHIELD_HP
		}
	}
}

@(private = "file")
update_ancient_guardian :: proc(b: ^Boss, bullets: ^Bullet_Pool, dt: f32) {
	b.sway_phase += GUARDIAN_SWAY_FREQ * math.TAU * dt
	if b.sway_phase >= math.TAU {
		b.sway_phase -= math.TAU
	}
	sx := math.sin(b.sway_phase)
	cx := math.cos(b.sway_phase)
	b.pos.x = GUARDIAN_SPAWN_X + sx * GUARDIAN_SWAY_AMP
	b.pos.y = GUARDIAN_SPAWN_Y + sx * cx * GUARDIAN_SWAY_AMP * BOSS_FIGURE8_Y_RATIO

	b.frame_time += dt
	frame_dur: f32 = 1.0 / GUARDIAN_ANIM_FPS
	if b.frame_time >= frame_dur {
		b.frame_time -= frame_dur
		b.frame = (b.frame + 1) % GUARDIAN_FRAMES
	}

	if b.in_window {
		// Damage window: the boss is exposed for GUARDIAN_WINDOW_DURATION.
		// When the timer expires, all orbs respawn at full hp and the cycle
		// restarts. The boss's current hp persists across cycles. The body
		// also lays down its own ring attack while exposed — the orbs are
		// gone, so this fills the bullet-density vacuum.
		b.window_timer -= dt
		if b.window_timer <= 0 {
			b.window_timer = 0
			spawn_guardian_orbs(b)
			b.fire_timer = 0
		} else {
			b.fire_timer += dt
			ring_color := rl.Color{255, 200, 100, 255}
			step := math.TAU / f32(GUARDIAN_RING_BULLETS)
			for b.fire_timer >= GUARDIAN_FIRE_INTERVAL {
				b.fire_timer -= GUARDIAN_FIRE_INTERVAL
				for r in 0 ..< GUARDIAN_RING_BULLETS {
					ang := f32(r) * step
					vel := rl.Vector2 {
						math.cos(ang) * GUARDIAN_BULLET_SPEED,
						math.sin(ang) * GUARDIAN_BULLET_SPEED,
					}
					spawn_bullet(bullets, b.pos, vel, ring_color, .Enemy, .Boss, 0)
				}
			}
		}
		return
	}

	b.orbit_phase += GUARDIAN_ORB_ORBIT_SPEED * dt
	if b.orbit_phase >= math.TAU {
		b.orbit_phase -= math.TAU
	}

	// Vulnerability rotation: if the player doesn't kill the highlighted orb
	// before the timer expires, pick a different alive orb and reset the
	// timer. Damage already dealt to non-killed orbs is preserved.
	b.vulnerable_timer -= dt
	if b.vulnerable_timer <= 0 {
		b.vulnerable_timer = GUARDIAN_ORB_VULNERABLE_TIME
		b.vulnerable_orb_idx = pick_random_alive_orb(b, b.vulnerable_orb_idx)
	}

	row_step: f32 = math.TAU / f32(GUARDIAN_ORB_BULLETS_PER_BURST)
	inc_rad: f32 = f32(GUARDIAN_ORB_ANGLE_INC_DEG) * math.PI / 180.0
	non_vuln_color := rl.Color{160, 100, 220, 255}
	vuln_color := rl.Color{255, 220, 100, 255}

	for i in 0 ..< GUARDIAN_ORB_COUNT {
		o := &b.orbs[i]
		if !o.active {
			continue
		}

		angle := b.orbit_phase + o.angle_offset
		o.pos = {
			b.pos.x + math.cos(angle) * GUARDIAN_ORB_ORBIT_RADIUS,
			b.pos.y + math.sin(angle) * GUARDIAN_ORB_ORBIT_RADIUS,
		}

		if o.hit_flash > 0 {
			o.hit_flash -= dt
			if o.hit_flash < 0 {
				o.hit_flash = 0
			}
		}

		color := non_vuln_color
		if i == b.vulnerable_orb_idx {
			color = vuln_color
		}

		o.fire_timer += dt
		for o.fire_timer >= GUARDIAN_ORB_FIRE_INTERVAL {
			o.fire_timer -= GUARDIAN_ORB_FIRE_INTERVAL
			for r in 0 ..< GUARDIAN_ORB_BULLETS_PER_BURST {
				ang := o.spiral_angle + f32(r) * row_step
				vel := rl.Vector2 {
					math.cos(ang) * GUARDIAN_ORB_BULLET_SPEED,
					math.sin(ang) * GUARDIAN_ORB_BULLET_SPEED,
				}
				spawn_bullet(bullets, o.pos, vel, color, .Enemy, .Guardian_Orb, i)
			}
			o.spiral_angle += inc_rad * o.spin_dir
			if o.spiral_angle >= math.TAU {
				o.spiral_angle -= math.TAU
			}
			if o.spiral_angle < 0 {
				o.spiral_angle += math.TAU
			}
		}
	}
}

// #endregion

