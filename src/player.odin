package game

import "core:math"
import rl "vendor:raylib"

Player_Anim :: enum {
	Idle,
	Move_Down,
	Move_Up,
	Move_Side,
}

// Abilities the player accumulates between missions. The post-mission choice
// screen adds one to the set; gameplay code branches on `in p.upgrades`.
// Rapid_Fire and Beam_Blast both replace the laser, so they cannot coexist —
// the picker filters one out when the other is already owned.
Player_Upgrade :: enum {
	Slow_Time,
	Dash_Frenzy,
	Rapid_Fire,
	Beam_Blast,
	Riposte,
	Lucky_Shot,
}

Player_Upgrade_Set :: bit_set[Player_Upgrade]

Player :: struct {
	pos:                rl.Vector2,
	anim:               Player_Anim,
	facing_left:        bool,
	frame_time:         f32,
	frame:              int,
	hp:                 int,
	stamina:            f32,
	invuln_timer:       f32,
	fire_timer:         f32,
	hold_time:          f32,
	charging:           bool,
	charge:             f32,
	charge_beam_idx:    int,
	dash_timer:         f32,
	dash_cooldown:      f32,
	dash_velocity:      rl.Vector2,
	dash_trail:         [PLAYER_DASH_TRAIL_LEN]rl.Vector2,
	dash_trail_count:   int,
	dash_trail_fade:    f32,
	upgrades:           Player_Upgrade_Set,
	slow_time_active:   bool,
	slow_time_phase:    f32,
	shrink_bombs:       int,
	tex_idle:           rl.Texture2D,
	tex_down:           rl.Texture2D,
	tex_up:             rl.Texture2D,
	tex_side:           rl.Texture2D,
	tex_reticle:        rl.Texture2D,
	flash_shader:       rl.Shader,
}

init_player :: proc(p: ^Player) {
	p.tex_idle = rl.LoadTexture("assets/sprites/player_idle.png")
	p.tex_down = rl.LoadTexture("assets/sprites/player_move_down.png")
	p.tex_up = rl.LoadTexture("assets/sprites/player_move_up.png")
	p.tex_side = rl.LoadTexture("assets/sprites/player_move_side.png")
	p.tex_reticle = rl.LoadTexture("assets/sprites/player_redicle.png")
	rl.SetTextureFilter(p.tex_idle, .POINT)
	rl.SetTextureFilter(p.tex_down, .POINT)
	rl.SetTextureFilter(p.tex_up, .POINT)
	rl.SetTextureFilter(p.tex_side, .POINT)
	rl.SetTextureFilter(p.tex_reticle, .POINT)

	p.flash_shader = load_flash_shader()

	reset_player_for_new_game(p)
}

// Resets transient/gameplay fields without touching textures or shaders, so the
// main menu can hand the same Player back into a fresh run.
reset_player_for_new_game :: proc(p: ^Player) {
	p.pos = {SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2}
	p.anim = .Idle
	p.facing_left = false
	p.frame_time = 0
	p.frame = 0
	p.hp = PLAYER_MAX_HP
	p.stamina = PLAYER_MAX_STAMINA
	p.invuln_timer = 0
	p.fire_timer = 0
	p.hold_time = 0
	p.charging = false
	p.charge = 0
	p.charge_beam_idx = -1
	p.dash_timer = 0
	p.dash_cooldown = 0
	p.dash_velocity = {0, 0}
	p.dash_trail_count = 0
	p.dash_trail_fade = 0
	p.upgrades = {}
	p.slow_time_active = false
	p.slow_time_phase = 0
	p.shrink_bombs = SHRINK_BOMBS_PER_LEVEL
}

deploy_shrink_bomb :: proc(
	p: ^Player,
	bullets: ^Bullet_Pool,
	particles: ^Particle_Pool,
	audio: ^Audio,
) {
	if p.shrink_bombs <= 0 {
		return
	}
	p.shrink_bombs -= 1
	shrink_all_enemy_bullets(bullets)
	pcx := p.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := p.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	spawn_impact_particles(particles, {pcx, pcy}, rl.WHITE, SHRINK_BOMB_BURST_PARTICLES)
	play_shrink_bomb_sfx(audio)
}

// Drains stamina while held and returns the dt that should be applied to
// non-player entities (bullets, enemies, particles, background). Player input
// and the player's own projectiles continue to use the raw dt.
update_slow_time :: proc(p: ^Player, dt: f32) -> (world_dt: f32) {
	p.slow_time_active = false
	if .Slow_Time not_in p.upgrades {
		return dt
	}
	if !input_slow_time_held() {
		return dt
	}
	if p.stamina <= 0 {
		return dt
	}
	p.slow_time_active = true
	// Phase ticks at real time so the cue keeps a steady cadence.
	p.slow_time_phase += SLOW_TIME_PULSE_HZ * math.TAU * dt
	if p.slow_time_phase >= math.TAU {
		p.slow_time_phase -= math.TAU
	}
	p.stamina -= SLOW_TIME_STAMINA_PER_SEC * dt
	if p.stamina < 0 {
		p.stamina = 0
	}
	return dt * SLOW_TIME_FACTOR
}

draw_slow_time_tint :: proc(p: ^Player) {
	if !p.slow_time_active {
		return
	}
	a := f32(SLOW_TIME_TINT_ALPHA_BASE) + math.sin(p.slow_time_phase) * f32(SLOW_TIME_TINT_ALPHA_PULSE)
	if a < 0 {
		a = 0
	}
	if a > 255 {
		a = 255
	}
	rl.DrawRectangle(
		0,
		0,
		SCREEN_WIDTH,
		SCREEN_HEIGHT,
		rl.Color{SLOW_TIME_TINT_R, SLOW_TIME_TINT_G, SLOW_TIME_TINT_B, u8(a)},
	)
}

unload_player :: proc(p: ^Player) {
	rl.UnloadTexture(p.tex_idle)
	rl.UnloadTexture(p.tex_down)
	rl.UnloadTexture(p.tex_up)
	rl.UnloadTexture(p.tex_side)
	rl.UnloadTexture(p.tex_reticle)
	rl.UnloadShader(p.flash_shader)
}

dash_stamina_cost :: proc(p: ^Player) -> f32 {
	if .Dash_Frenzy in p.upgrades {
		return PLAYER_DASH_STAMINA_COST + DASH_FRENZY_EXTRA_STAMINA_COST
	}
	return PLAYER_DASH_STAMINA_COST
}

update_player :: proc(p: ^Player, missiles: ^Missile_Pool, audio: ^Audio, dt: f32) {
	move := input_move()

	if p.invuln_timer > 0 {
		p.invuln_timer -= dt
		if p.invuln_timer < 0 {
			p.invuln_timer = 0
		}
	}

	if p.dash_cooldown > 0 {
		p.dash_cooldown -= dt
		if p.dash_cooldown < 0 {
			p.dash_cooldown = 0
		}
	}
	if p.dash_trail_fade > 0 {
		p.dash_trail_fade -= dt
		if p.dash_trail_fade < 0 {
			p.dash_trail_fade = 0
		}
	}

	if p.stamina < PLAYER_MAX_STAMINA && !p.slow_time_active {
		p.stamina += PLAYER_STAMINA_RECOVER_RATE * dt
		if p.stamina > PLAYER_MAX_STAMINA {
			p.stamina = PLAYER_MAX_STAMINA
		}
	}

	pcx := p.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := p.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	dash_cost := dash_stamina_cost(p)
	if p.dash_timer <= 0 && p.dash_cooldown <= 0 && p.stamina >= dash_cost {
		pressed, dir := input_dash({pcx, pcy}, get_mouse_game_pos())
		if pressed && rl.Vector2Length(dir) > 0.001 {
			p.dash_timer = PLAYER_DASH_DURATION
			p.dash_cooldown = PLAYER_DASH_COOLDOWN
			p.dash_velocity = dir * PLAYER_DASH_SPEED
			p.dash_trail_count = 0
			p.dash_trail_fade = PLAYER_DASH_TRAIL_FADE_TIME
			p.stamina -= dash_cost
			if .Dash_Frenzy in p.upgrades {
				count := DASH_FRENZY_MISSILES_PER_DASH
				if .Lucky_Shot in p.upgrades {
					count += 1
				}
				launch_dash_missiles(missiles, {pcx, pcy}, dir, count)
			}
			play_dash_sfx(audio)
		}
	}

	if p.dash_timer > 0 {
		p.pos += p.dash_velocity * dt
		p.dash_timer -= dt
		if p.dash_timer < 0 {
			p.dash_timer = 0
		}

		head := rl.Vector2 {
			p.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5,
			p.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5,
		}
		if p.dash_trail_count < PLAYER_DASH_TRAIL_LEN {
			p.dash_trail_count += 1
		}
		for i := p.dash_trail_count - 1; i > 0; i -= 1 {
			p.dash_trail[i] = p.dash_trail[i - 1]
		}
		p.dash_trail[0] = head
	} else {
		p.pos += move * PLAYER_SPEED * dt
	}

	draw_w := f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE)
	draw_h := f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE)
	if p.pos.x < 0 {
		p.pos.x = 0
	}
	if p.pos.y < 0 {
		p.pos.y = 0
	}
	if p.pos.x > f32(SCREEN_WIDTH) - draw_w {
		p.pos.x = f32(SCREEN_WIDTH) - draw_w
	}
	if p.pos.y > f32(SCREEN_HEIGHT) - draw_h {
		p.pos.y = f32(SCREEN_HEIGHT) - draw_h
	}

	anim_dir := move
	if p.dash_timer > 0 {
		anim_dir = p.dash_velocity
	}
	prev := p.anim
	if abs(anim_dir.x) < 0.01 && abs(anim_dir.y) < 0.01 {
		p.anim = .Idle
	} else if abs(anim_dir.x) > abs(anim_dir.y) {
		p.anim = .Move_Side
		p.facing_left = anim_dir.x < 0
	} else if anim_dir.y < 0 {
		p.anim = .Move_Up
	} else {
		p.anim = .Move_Down
	}

	if p.anim != prev {
		p.frame = 0
		p.frame_time = 0
	}

	p.frame_time += dt
	frame_dur: f32 = 1.0 / PLAYER_ANIM_FPS
	if p.frame_time >= frame_dur {
		p.frame_time -= frame_dur
		if p.anim == .Idle {
			p.frame = (p.frame + 1) % PLAYER_IDLE_FRAMES
		} else if p.frame < PLAYER_MOVE_FRAMES - 1 {
			p.frame += 1
		}
	}
}

draw_player :: proc(p: ^Player) {
	tex: rl.Texture2D
	flip := false
	switch p.anim {
	case .Idle:
		tex = p.tex_idle
	case .Move_Down:
		tex = p.tex_down
	case .Move_Up:
		tex = p.tex_up
	case .Move_Side:
		tex = p.tex_side
		flip = p.facing_left
	}

	src_w: f32 = PLAYER_FRAME_W
	if flip {
		src_w = -src_w
	}

	src := rl.Rectangle {
		f32(p.frame * PLAYER_FRAME_W),
		0,
		src_w,
		f32(PLAYER_FRAME_H),
	}

	draw_dash_trail(p, tex, src)

	dst := rl.Rectangle {
		p.pos.x,
		p.pos.y,
		f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE),
		f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE),
	}
	flashing := p.invuln_timer > 0 && int(p.invuln_timer * PLAYER_FLASH_HZ) % 2 == 0
	if flashing {
		rl.BeginShaderMode(p.flash_shader)
	}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)
	if flashing {
		rl.EndShaderMode()
	}

	pcx := p.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := p.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	rsrc := rl.Rectangle{0, 0, f32(RETICLE_FRAME_W), f32(RETICLE_FRAME_H)}
	rdst := rl.Rectangle {
		pcx - f32(RETICLE_FRAME_W) * 0.5,
		pcy - RETICLE_DISTANCE - f32(RETICLE_FRAME_H) * 0.5,
		f32(RETICLE_FRAME_W),
		f32(RETICLE_FRAME_H),
	}
	rl.DrawTexturePro(p.tex_reticle, rsrc, rdst, {0, 0}, 0, rl.WHITE)
}

draw_dash_trail :: proc(p: ^Player, tex: rl.Texture2D, src: rl.Rectangle) {
	if p.dash_trail_fade <= 0 || p.dash_trail_count == 0 {
		return
	}
	fade := p.dash_trail_fade / PLAYER_DASH_TRAIL_FADE_TIME
	if fade > 1 {
		fade = 1
	}
	w := f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE)
	h := f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE)
	// Iterate oldest-first so newer (more opaque) afterimages overdraw older ones.
	for k := p.dash_trail_count - 1; k >= 0; k -= 1 {
		ratio := f32(p.dash_trail_count - k) / f32(p.dash_trail_count)
		alpha := ratio * fade
		col := rl.Color{160, 220, 255, u8(255 * alpha * PLAYER_DASH_TRAIL_MAX_ALPHA)}
		dst := rl.Rectangle{p.dash_trail[k].x - w * 0.5, p.dash_trail[k].y - h * 0.5, w, h}
		rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, col)
	}
}

draw_player_hud :: proc(p: ^Player) {
	x: i32 = HP_BAR_MARGIN
	stam_y: i32 = SCREEN_HEIGHT - HP_BAR_MARGIN - HP_BAR_H
	hp_y: i32 = stam_y - STATUS_BAR_GAP - HP_BAR_H

	rl.DrawRectangle(x, hp_y, HP_BAR_W, HP_BAR_H, rl.Color{40, 40, 40, 255})
	hp := p.hp
	if hp < 0 {
		hp = 0
	}
	hp_fill_w := i32(f32(HP_BAR_W) * f32(hp) / f32(PLAYER_MAX_HP))
	if hp_fill_w > 0 {
		rl.DrawRectangle(x, hp_y, hp_fill_w, HP_BAR_H, rl.Color{220, 60, 60, 255})
	}
	rl.DrawRectangleLines(x, hp_y, HP_BAR_W, HP_BAR_H, rl.WHITE)

	rl.DrawRectangle(x, stam_y, HP_BAR_W, HP_BAR_H, rl.Color{40, 40, 40, 255})
	stam := p.stamina
	if stam < 0 {
		stam = 0
	}
	stam_fill_w := i32(f32(HP_BAR_W) * stam / PLAYER_MAX_STAMINA)
	if stam_fill_w > 0 {
		rl.DrawRectangle(x, stam_y, stam_fill_w, HP_BAR_H, rl.Color{80, 180, 240, 255})
	}
	rl.DrawRectangleLines(x, stam_y, HP_BAR_W, HP_BAR_H, rl.WHITE)

	pip_cy := f32(stam_y) + f32(HP_BAR_H) * 0.5
	pip_x := f32(x + HP_BAR_W) + f32(SHRINK_BOMB_HUD_DOT_GAP) + SHRINK_BOMB_HUD_DOT_R
	for i in 0 ..< SHRINK_BOMBS_PER_LEVEL {
		c := rl.Vector2{pip_x, pip_cy}
		if i < p.shrink_bombs {
			rl.DrawCircleV(c, SHRINK_BOMB_HUD_DOT_R, rl.WHITE)
		} else {
			rl.DrawCircleLinesV(c, SHRINK_BOMB_HUD_DOT_R, rl.Color{120, 120, 120, 255})
		}
		pip_x += 2 * SHRINK_BOMB_HUD_DOT_R + f32(SHRINK_BOMB_HUD_DOT_GAP)
	}
}

damage_player :: proc(p: ^Player, audio: ^Audio, amount: int) {
	if p.invuln_timer > 0 {
		return
	}
	p.hp -= amount
	if p.hp < 0 {
		p.hp = 0
	}
	p.invuln_timer = PLAYER_INVULN_TIME
	play_player_damage_sfx(audio)
}

update_player_attack :: proc(
	p: ^Player,
	beams: ^Beam_Pool,
	bullets: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	audio: ^Audio,
	score: ^Score_Stats,
	dt: f32,
) {
	if p.fire_timer > 0 {
		p.fire_timer -= dt
		if p.fire_timer < 0 {
			p.fire_timer = 0
		}
	}

	pcx := p.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := p.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	start := rl.Vector2{pcx, pcy + PLAYER_PROJECTILE_ORIGIN_Y_OFFSET}
	// Charge beam still fires hitscan from start to top-of-screen; only the moving
	// laser bolts use a direction + speed instead of an endpoint.
	end := rl.Vector2{pcx, 0}

	held := input_attack_held()

	// Track continuous hold duration so we can defer charging until the hold threshold.
	if held {
		p.hold_time += dt
	} else {
		p.hold_time = 0
	}

	// Rapid Fire replaces the laser with a single straight-up projectile stream;
	// Beam Blast replaces it with a 5-way fan of bolts. Otherwise fall through
	// to the vanilla single bolt. The charge beam below still runs in all three
	// cases that are not Rapid Fire — it shares the hold-to-fire input.
	if held && p.fire_timer <= 0 {
		if .Rapid_Fire in p.upgrades {
			p.fire_timer = RAPID_FIRE_INTERVAL
			fire_rapid_burst(bullets, start)
		} else if .Beam_Blast in p.upgrades {
			p.fire_timer = LASER_FIRE_INTERVAL
			fire_beam_blast(beams, start)
			play_laser_sfx(audio)
		} else {
			p.fire_timer = LASER_FIRE_INTERVAL
			fire_laser(beams, start)
			play_laser_sfx(audio)
		}
	}

	// Rapid-fire sfx is a pre-rendered loop, not a per-shot trigger — keep it
	// alive while attack is held and stop it the instant the player releases.
	if .Rapid_Fire in p.upgrades {
		if held {
			tick_rapid_fire_sfx(audio)
		} else {
			stop_rapid_fire_sfx(audio)
		}
	}

	// Once the player has held long enough, begin charging. Rapid Fire replaces
	// the entire hold-to-attack mechanic, so the charge beam is unavailable then.
	if held &&
	   .Rapid_Fire not_in p.upgrades &&
	   !p.charging &&
	   p.hold_time >= CHARGE_BEAM_HOLD_DELAY &&
	   p.stamina >= CHARGE_BEAM_FULL_STAMINA_COST {
		idx := start_charging_beam(beams, start, end)
		if idx >= 0 {
			p.charging = true
			p.charge_beam_idx = idx
			p.charge = 0
		}
	}

	if !p.charging {
		return
	}

	b := &beams.beams[p.charge_beam_idx]
	if !b.active || !b.charging {
		// Defensive: slot was clobbered; abort cleanly.
		p.charging = false
		p.charge_beam_idx = -1
		stop_charging_beam_sfx(audio)
		return
	}

	if held {
		p.charge = min(p.charge + dt * CHARGE_BEAM_RATE, 1.0)
		b.charge = p.charge
		b.start = start
		b.end = end
		spawn_gather_particle(particles, start, rl.MAGENTA, p.charge)
		tick_charging_beam_sfx(audio)
	}

	if input_attack_released() {
		release_charge_beam(b)
		fire_charge_beam(b, p.charge, enemies, sneaks, boss, pillars, packs, particles, score)
		p.stamina -= CHARGE_BEAM_FULL_STAMINA_COST * p.charge
		if p.stamina < 0 {
			p.stamina = 0
		}
		p.charging = false
		p.charge_beam_idx = -1
		p.charge = 0
		stop_charging_beam_sfx(audio)
		play_charged_beam_sfx(audio)
	}
}

fire_rapid_burst :: proc(bullets: ^Bullet_Pool, start: rl.Vector2) {
	vel := rl.Vector2{0, -RAPID_FIRE_SPEED}
	spawn_bullet(bullets, start, vel, rl.RED, .Rapid_Fire)
}

// Spawn-only: bolts travel and collide each frame via collide_beams_enemies.
fire_laser :: proc(beams: ^Beam_Pool, origin: rl.Vector2) {
	spawn_laser_bolt(beams, origin, {0, -1}, LASER_DAMAGE)
}

// Fan of BEAM_BLAST_BEAM_COUNT bolts symmetric around straight up. Each bolt
// is its own moving projectile carrying BEAM_BLAST_DAMAGE_PER_BEAM, so a target
// overlapped by all 5 bolts takes 15 dmg per volley, partial overlap scales linearly.
fire_beam_blast :: proc(beams: ^Beam_Pool, origin: rl.Vector2) {
	half := BEAM_BLAST_BEAM_COUNT / 2
	for i in 0 ..< BEAM_BLAST_BEAM_COUNT {
		angle_deg := f32(i - half) * BEAM_BLAST_ANGLE_STEP_DEG
		rad := angle_deg * math.PI / 180
		dir := rl.Vector2{math.sin(rad), -math.cos(rad)}
		spawn_laser_bolt(beams, origin, dir, BEAM_BLAST_DAMAGE_PER_BEAM)
	}
}

fire_charge_beam :: proc(
	b: ^Beam,
	charge: f32,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^Score_Stats,
) {
	damage := CHARGE_BEAM_BASE_DAMAGE + int(f32(CHARGE_BEAM_DAMAGE_BONUS) * charge)
	// Match the outer glow (drawn at thickness * 2 line width, so half-width = thickness)
	// rather than the bright core, otherwise enemies clearly inside the visible beam are missed.
	half_width := b.thickness + CHARGE_BEAM_HIT_PAD
	pcx := b.start.x

	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if !e.active {
			continue
		}
		ec := enemy_center(e)
		if ec.y > b.start.y {
			continue
		}
		if abs(ec.x - pcx) > half_width + enemy_hit_radius(e) {
			continue
		}
		killed := damage_enemy(e, damage)
		spawn_impact_particles(particles, ec, rl.MAGENTA, CHARGE_BEAM_IMPACT_PARTICLES)
		if killed {
			add_kill(score, .Charge)
			try_spawn_sneak(sneaks)
			try_drop_healthpack(packs, ec)
		}
	}

	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if !s.active {
			continue
		}
		sc := sneak_center(s)
		if sc.y > b.start.y {
			continue
		}
		if abs(sc.x - pcx) > half_width + sneak_hit_radius(s) {
			continue
		}
		killed := damage_sneak(s, damage)
		spawn_impact_particles(particles, sc, rl.MAGENTA, CHARGE_BEAM_IMPACT_PARTICLES)
		if killed {
			add_kill(score, .Charge)
			try_spawn_sneak(sneaks)
			try_drop_healthpack(packs, sc)
		}
	}

	if boss.boss.active {
		bc := boss_center(&boss.boss)
		if bc.y <= b.start.y && abs(bc.x - pcx) <= half_width + boss_hit_radius(&boss.boss) {
			if boss_can_take_damage(&boss.boss) {
				killed := damage_boss(&boss.boss, damage)
				spawn_impact_particles(particles, bc, rl.MAGENTA, CHARGE_BEAM_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Boss)
					try_drop_healthpack(packs, bc)
				}
			} else {
				spawn_impact_particles(particles, bc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
		}
	}

	if boss.boss.active && boss.boss.kind == .Ancient_Guardian {
		for i in 0 ..< GUARDIAN_ORB_COUNT {
			o := &boss.boss.orbs[i]
			if !o.active {
				continue
			}
			if o.pos.y > b.start.y {
				continue
			}
			if abs(o.pos.x - pcx) > half_width + GUARDIAN_ORB_HIT_RADIUS {
				continue
			}
			applied, killed := damage_guardian_orb(&boss.boss, i, damage)
			if applied {
				spawn_impact_particles(particles, o.pos, rl.MAGENTA, CHARGE_BEAM_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Guardian_Orb)
				}
			} else {
				spawn_impact_particles(particles, o.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
		}
	}

	for i in 0 ..< PILLAR_COUNT {
		p := &pillars.pillars[i]
		if !p.active {
			continue
		}
		pc := pillar_center(p)
		if pc.y > b.start.y {
			continue
		}
		if abs(pc.x - pcx) > half_width + pillar_hit_radius(p) {
			continue
		}
		applied, killed := damage_pillar(pillars, i, damage)
		if applied {
			spawn_impact_particles(particles, pc, rl.MAGENTA, CHARGE_BEAM_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Pillar)
			}
		} else {
			spawn_impact_particles(particles, pc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
		}
	}

	burst := CHARGE_BEAM_RELEASE_BURST_BASE + int(f32(CHARGE_BEAM_RELEASE_BURST_BONUS) * charge)
	spawn_impact_particles(particles, b.end, rl.MAGENTA, burst)
}
