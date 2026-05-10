package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

// #region Beams
Beam_Type :: enum {
	Laser,
	Charge,
}

// `.Laser` is a moving projectile-style bolt: `start` is the tail, `end` is the
// tip, both advance by `vel * dt` each frame. `damage` is per-target and the
// bolt deactivates on first hit. `.Charge` stays hitscan: `start`/`end` define
// a static fat beam, damage is applied once on release, and the visual fades
// out over `max_life`.
Beam :: struct {
	type:      Beam_Type,
	start:     rl.Vector2,
	end:       rl.Vector2,
	vel:       rl.Vector2, // .Laser only
	damage:    int, // .Laser only
	lifetime:  f32,
	max_life:  f32,
	charging:  bool, // .Charge only
	charge:    f32, // .Charge only
	thickness: f32, // .Charge only (laser uses LASER_THICKNESS)
	active:    bool,
}

Beam_Pool :: struct {
	beams: [MAX_BEAMS]Beam,
}

// Closest-point-on-segment distance vs radius. Used by laser-bolt collision so
// a single test handles vertical vanilla bolts and angled Beam Blast bolts.
beam_segment_hits :: proc(start, end, c: rl.Vector2, r: f32) -> bool {
	seg := end - start
	seg_len_sq := rl.Vector2DotProduct(seg, seg)
	if seg_len_sq < 0.001 {
		return rl.Vector2Distance(start, c) <= r
	}
	t := rl.Vector2DotProduct(c - start, seg) / seg_len_sq
	if t < 0 {
		t = 0
	}
	if t > 1 {
		t = 1
	}
	closest := rl.Vector2{start.x + seg.x * t, start.y + seg.y * t}
	return rl.Vector2Distance(closest, c) <= r
}

spawn_laser_bolt :: proc(pool: ^Beam_Pool, origin, dir: rl.Vector2, damage: int) {
	vel := dir * LASER_BOLT_SPEED
	end := origin
	start := origin - dir * LASER_BOLT_LENGTH
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				type     = .Laser,
				start    = start,
				end      = end,
				vel      = vel,
				damage   = damage,
				lifetime = 0,
				max_life = LASER_LIFETIME,
				active   = true,
			}
			return
		}
	}
}

start_charging_beam :: proc(pool: ^Beam_Pool, start, end: rl.Vector2) -> int {
	for i in 0 ..< MAX_BEAMS {
		if !pool.beams[i].active {
			pool.beams[i] = Beam {
				type      = .Charge,
				start     = start,
				end       = end,
				lifetime  = 0,
				max_life  = 999, // won't expire while charging
				charging  = true,
				charge    = 0,
				thickness = 2,
				active    = true,
			}
			return i
		}
	}
	return -1
}

release_charge_beam :: proc(b: ^Beam) {
	b.charging = false
	b.lifetime = 0
	b.max_life = CHARGE_BEAM_LIFETIME_BASE + b.charge * CHARGE_BEAM_LIFETIME_BONUS
	b.thickness = CHARGE_BEAM_THICKNESS_BASE + b.charge * CHARGE_BEAM_THICKNESS_BONUS
}

cancel_charge_beam :: proc(b: ^Beam) {
	b.active = false
	b.charging = false
}

update_beams :: proc(pool: ^Beam_Pool, dt: f32) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		if b.charging {
			continue
		}
		b.lifetime += dt
		if b.lifetime >= b.max_life {
			b.active = false
			continue
		}
		if b.type == .Laser {
			b.start += b.vel * dt
			b.end += b.vel * dt
			// Off-screen safety: once both endpoints are clearly outside the
			// playfield in the same direction, drop the bolt early.
			margin: f32 = LASER_BOLT_LENGTH
			if (b.start.y < -margin && b.end.y < -margin) ||
			   (b.start.y > SCREEN_HEIGHT + margin && b.end.y > SCREEN_HEIGHT + margin) ||
			   (b.start.x < -margin && b.end.x < -margin) ||
			   (b.start.x > SCREEN_WIDTH + margin && b.end.x > SCREEN_WIDTH + margin) {
				b.active = false
			}
		}
	}
}

// Per-frame collision pass for moving laser bolts. A bolt deactivates on its
// first contact (no piercing). Charge beams are NOT processed here — they
// damage at release time inside fire_charge_beam.
collide_beams_enemies :: proc(
	pool: ^Beam_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^Score_Stats,
) {
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active || b.type != .Laser {
			continue
		}
		hit := false
		for ei in 0 ..< ENEMY_COUNT {
			e := &enemies.enemies[ei]
			if !e.active {
				continue
			}
			ec := enemy_center(e)
			if !beam_segment_hits(b.start, b.end, ec, enemy_hit_radius(e)) {
				continue
			}
			killed := damage_enemy(e, b.damage)
			spawn_impact_particles(particles, ec, rl.RED, LASER_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Laser)
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, ec)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		for si in 0 ..< SNEAK_MAX {
			s := &sneaks.sneaks[si]
			if !s.active {
				continue
			}
			sc := sneak_center(s)
			if !beam_segment_hits(b.start, b.end, sc, sneak_hit_radius(s)) {
				continue
			}
			killed := damage_sneak(s, b.damage)
			spawn_impact_particles(particles, sc, rl.RED, LASER_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Laser)
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, sc)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		for pi in 0 ..< PILLAR_COUNT {
			p := &pillars.pillars[pi]
			if !p.active {
				continue
			}
			pc := pillar_center(p)
			if !beam_segment_hits(b.start, b.end, pc, pillar_hit_radius(p)) {
				continue
			}
			applied, killed := damage_pillar(pillars, pi, b.damage)
			if applied {
				spawn_impact_particles(particles, pc, rl.RED, LASER_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Pillar)
				}
			} else {
				spawn_impact_particles(particles, pc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
			hit = true
			break
		}
		if hit {
			b.active = false
			continue
		}
		if boss.boss.active {
			bc := boss_center(&boss.boss)
			if beam_segment_hits(b.start, b.end, bc, boss_hit_radius(&boss.boss)) {
				if boss_can_take_damage(&boss.boss) {
					killed := damage_boss(&boss.boss, b.damage)
					spawn_impact_particles(particles, bc, rl.RED, LASER_IMPACT_PARTICLES)
					if killed {
						add_kill(score, .Boss)
						try_drop_healthpack(packs, bc)
					}
				} else {
					spawn_impact_particles(particles, bc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
				}
				b.active = false
				continue
			}
		}
		if boss.boss.active && boss.boss.kind == .Ancient_Guardian {
			for oi in 0 ..< GUARDIAN_ORB_COUNT {
				o := &boss.boss.orbs[oi]
				if !o.active {
					continue
				}
				if !beam_segment_hits(b.start, b.end, o.pos, GUARDIAN_ORB_HIT_RADIUS) {
					continue
				}
				applied, killed := damage_guardian_orb(&boss.boss, oi, b.damage)
				if applied {
					spawn_impact_particles(particles, o.pos, rl.RED, LASER_IMPACT_PARTICLES)
					if killed {
						add_kill(score, .Guardian_Orb)
					}
				} else {
					spawn_impact_particles(particles, o.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
				}
				b.active = false
				break
			}
		}
	}
}

draw_beams :: proc(pool: ^Beam_Pool) {
	t := f32(rl.GetTime())
	for i in 0 ..< MAX_BEAMS {
		b := &pool.beams[i]
		if !b.active {
			continue
		}
		switch b.type {
		case .Laser:
			draw_laser_beam(b)
		case .Charge:
			if b.charging {
				draw_charging_beam(b, t)
			} else {
				draw_charge_beam(b)
			}
		}
	}
}

draw_laser_beam :: proc(b: ^Beam) {
	// Bolt stays full-bright while alive; it usually exits via hit or off-screen
	// long before max_life. The tip carries a soft glow halo for projectile feel.
	glow := rl.RED
	glow.a = 60
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * LASER_GLOW_MULT, glow)

	mid := rl.Color{255, 120, 120, 220}
	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS * 2, mid)

	rl.DrawLineEx(b.start, b.end, LASER_THICKNESS, rl.WHITE)

	tip_glow := rl.Color{255, 200, 200, 140}
	rl.DrawCircleV(b.end, LASER_THICKNESS * LASER_GLOW_MULT * 0.6, tip_glow)
}

draw_charging_beam :: proc(b: ^Beam, t: f32) {
	// Visuals fade in with charge so quick taps stay laser-only.
	pulse: f32 = 0.8 + math.sin(t * 15) * 0.2
	ring_radius: f32 = 10 + b.charge * 30

	for ring in 0 ..< 3 {
		ring_color := rl.MAGENTA
		ring_color.a = u8((1 - f32(ring) * 0.3) * 150 * pulse * b.charge)
		rl.DrawCircleLines(
			i32(b.start.x),
			i32(b.start.y),
			ring_radius + f32(ring) * 5,
			ring_color,
		)
	}

	target_color := rl.MAGENTA
	target_color.a = u8(b.charge * 150)
	rl.DrawLineEx(b.start, b.end, 1 + b.charge * 3, target_color)
}

draw_charge_beam :: proc(b: ^Beam) {
	alpha := 1.0 - (b.lifetime / b.max_life)
	thickness := b.thickness

	// Multi-layer glow
	for layer in 0 ..< 5 {
		layer_t := f32(layer) / 5.0
		glow := rl.MAGENTA
		glow.a = u8(alpha * (50 - layer_t * 40))
		rl.DrawLineEx(b.start, b.end, thickness * (2 - layer_t), glow)
	}

	// Electric fringes
	dir := b.end - b.start
	length := rl.Vector2Length(dir)
	if length > 0.001 {
		dir /= length
		perp := rl.Vector2{-dir.y, dir.x}
		for i in 0 ..< CHARGE_BEAM_FRINGE_COUNT {
			f_t := f32(i) / f32(CHARGE_BEAM_FRINGE_COUNT)
			base := b.start + dir * length * f_t
			if rand.int31() % 3 == 0 {
				offset := (rand.float32() - 0.5) * thickness * 3
				fringe_end := base + perp * offset
				fringe_color := rl.MAGENTA
				fringe_color.a = u8(alpha * 150)
				rl.DrawLineEx(base, fringe_end, 2, fringe_color)
			}
		}
	}

	// Bright core
	core := rl.WHITE
	core.a = u8(alpha * 255)
	rl.DrawLineEx(b.start, b.end, thickness * 0.3, core)
}
// #endregion

// #region Bullets

// Bullets are pooled and tagged. Enemy bullets damage the player; Reflected
// bullets are former-enemy bullets the player turned by dashing through them
// and now home toward enemies; Rapid_Fire bullets are spawned by the player's
// Rapid Fire upgrade — they fly straight up at constant velocity and use the
// laser color palette.
Bullet_Kind :: enum {
	Enemy,
	Reflected,
	Rapid_Fire,
}

// Tracks the entity that fired the bullet so the Riposte upgrade can home
// reflected bullets back at it. .None means the bullet has no recoverable
// source (player-side projectiles or burst children).
Bullet_Source :: enum {
	None,
	Enemy,
	Sneak,
	Boss,
	Pillar,
	Guardian_Orb,
}

Bullet :: struct {
	pos:       rl.Vector2,
	vel:       rl.Vector2,
	life:      f32,
	color:     rl.Color,
	kind:      Bullet_Kind,
	active:    bool,
	// Shrink-bomb state. Only set on Enemy bullets caught in a bomb. Ramps 0->1
	// over SHRINK_BOMB_DURATION; while shrinking, hit radius and visuals scale by
	// (1 - shrink_t), and the bullet deactivates once shrink_t hits 1.
	shrinking: bool,
	shrink_t:  f32,
	// Morgan's energy-orb projectile: oversized .Enemy bullet that bursts into a
	// MORGAN_ORB_BURST_COUNT-bullet ring on EOL. Visual + collision radius differ
	// from the regular bullet path; collision hit-radius queried via bullet_hit_radius.
	is_burst_orb: bool,
	// Source entity that fired this bullet; used by Riposte to home a reflected
	// bullet back at its original shooter.
	source_kind:  Bullet_Source,
	source_index: int,
	// Set on reflection when the player owns Riposte. While true, the reflected
	// bullet homes specifically at source_kind/source_index instead of the
	// nearest-enemy fallback. Cleared if the source dies, so the bullet then
	// re-acquires the nearest target.
	lock_source:  bool,
}

Bullet_Pool :: struct {
	bullets:     [MAX_BULLETS]Bullet,
	glow_shader: rl.Shader,
	glow_tex:    rl.Texture2D,
}

init_bullets :: proc(pool: ^Bullet_Pool) {
	pool.glow_shader = load_glow_shader()
	pool.glow_tex = load_glow_texture()
}

unload_bullets :: proc(pool: ^Bullet_Pool) {
	rl.UnloadTexture(pool.glow_tex)
	rl.UnloadShader(pool.glow_shader)
}

spawn_bullet :: proc(
	pool: ^Bullet_Pool,
	pos, vel: rl.Vector2,
	color: rl.Color = rl.RED,
	kind: Bullet_Kind = .Enemy,
	source_kind: Bullet_Source = .None,
	source_index: int = 0,
) {
	life: f32 = BULLET_LIFE
	if kind == .Rapid_Fire {
		life = RAPID_FIRE_LIFE
	}
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos          = pos,
				vel          = vel,
				life         = life,
				color        = color,
				kind         = kind,
				active       = true,
				source_kind  = source_kind,
				source_index = source_index,
			}
			return
		}
	}
}

spawn_energy_orb :: proc(pool: ^Bullet_Pool, pos, vel: rl.Vector2) {
	for i in 0 ..< MAX_BULLETS {
		if !pool.bullets[i].active {
			pool.bullets[i] = Bullet {
				pos          = pos,
				vel          = vel,
				life         = MORGAN_ORB_LIFE,
				color        = rl.Color{160, 80, 255, 255},
				kind         = .Enemy,
				active       = true,
				is_burst_orb = true,
				source_kind  = .Boss,
				source_index = 0,
			}
			return
		}
	}
}

bullet_hit_radius :: proc(b: ^Bullet) -> f32 {
	if b.is_burst_orb {
		return MORGAN_ORB_HIT_RADIUS
	}
	return BULLET_RADIUS
}

@(private = "file")
lookup_source_center :: proc(
	kind: Bullet_Source,
	index: int,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
) -> (
	pos: rl.Vector2,
	alive: bool,
) {
	switch kind {
	case .None:
		return
	case .Enemy:
		if index < 0 || index >= ENEMY_COUNT {
			return
		}
		e := &enemies.enemies[index]
		if !e.active {
			return
		}
		return enemy_center(e), true
	case .Sneak:
		if index < 0 || index >= SNEAK_MAX {
			return
		}
		s := &sneaks.sneaks[index]
		if !s.active {
			return
		}
		return sneak_center(s), true
	case .Boss:
		if !boss.boss.active {
			return
		}
		return boss_center(&boss.boss), true
	case .Pillar:
		if index < 0 || index >= PILLAR_COUNT {
			return
		}
		p := &pillars.pillars[index]
		if !p.active {
			return
		}
		return pillar_center(p), true
	case .Guardian_Orb:
		if !boss.boss.active || boss.boss.kind != .Ancient_Guardian {
			return
		}
		if index < 0 || index >= GUARDIAN_ORB_COUNT {
			return
		}
		o := &boss.boss.orbs[index]
		if !o.active {
			return
		}
		return o.pos, true
	}
	return
}

@(private = "file")
detonate_orb :: proc(pool: ^Bullet_Pool, pos: rl.Vector2) {
	step := math.TAU / f32(MORGAN_ORB_BURST_COUNT)
	color := rl.Color{200, 140, 255, 255}
	for i in 0 ..< MORGAN_ORB_BURST_COUNT {
		ang := f32(i) * step
		vel := rl.Vector2{math.cos(ang) * MORGAN_ORB_BURST_SPEED, math.sin(ang) * MORGAN_ORB_BURST_SPEED}
		spawn_bullet(pool, pos, vel, color, .Enemy, .Boss, 0)
	}
}

update_bullets :: proc(
	pool: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	dt: f32,
	world_dt: f32,
) {
	steer_k := f32(1) - math.exp(-REFLECT_HOMING_RATE * dt)
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
		}
		// Only Reflected bullets home; Rapid_Fire flies straight by design.
		if b.kind == .Reflected {
			target: rl.Vector2
			found := false
			// Riposte: lock onto the original shooter while it's still alive.
			// If the source has died since deflection, drop the lock and let the
			// nearest-target fallback take over.
			if b.lock_source {
				src_pos, alive := lookup_source_center(b.source_kind, b.source_index, enemies, sneaks, boss, pillars)
				if alive {
					target = src_pos
					found = true
				} else {
					b.lock_source = false
				}
			}
			if !found {
				best_d_sq := f32(1e18)
				for ei in 0 ..< ENEMY_COUNT {
					e := &enemies.enemies[ei]
					if !e.active {
						continue
					}
					ec := enemy_center(e)
					dx := ec.x - b.pos.x
					dy := ec.y - b.pos.y
					d_sq := dx * dx + dy * dy
					if d_sq < best_d_sq {
						best_d_sq = d_sq
						target = ec
						found = true
					}
				}
				for si in 0 ..< SNEAK_MAX {
					s := &sneaks.sneaks[si]
					if !s.active {
						continue
					}
					sc := sneak_center(s)
					dx := sc.x - b.pos.x
					dy := sc.y - b.pos.y
					d_sq := dx * dx + dy * dy
					if d_sq < best_d_sq {
						best_d_sq = d_sq
						target = sc
						found = true
					}
				}
				if boss.boss.active {
					bc := boss_center(&boss.boss)
					dx := bc.x - b.pos.x
					dy := bc.y - b.pos.y
					d_sq := dx * dx + dy * dy
					if d_sq < best_d_sq {
						best_d_sq = d_sq
						target = bc
						found = true
					}
				}
			}
			if found {
				speed := rl.Vector2Length(b.vel)
				if speed > 0.001 {
					to_t := rl.Vector2Normalize(target - b.pos)
					if b.lock_source {
						// Riposte: snap directly to the source so the dash direction
						// doesn't matter — the bullet immediately tracks the shooter.
						b.vel = to_t * speed
					} else {
						target_vel := to_t * speed
						new_vel := b.vel * (1 - steer_k) + target_vel * steer_k
						nlen := rl.Vector2Length(new_vel)
						if nlen > 0.001 {
							b.vel = new_vel * (speed / nlen)
						}
					}
				}
			}
		}
		// Player-side projectiles ignore slow-time so the player's offense stays
		// crisp regardless of the world tempo.
		use_dt := b.kind == .Enemy ? world_dt : dt
		b.pos += b.vel * use_dt
		b.life -= use_dt
		if b.life <= 0 {
			if b.is_burst_orb && b.kind == .Enemy && !b.shrinking {
				detonate_orb(pool, b.pos)
			}
			b.active = false
			continue
		}
		if b.shrinking {
			b.shrink_t += use_dt / SHRINK_BOMB_DURATION
			if b.shrink_t >= 1 {
				b.active = false
			}
		}
	}
}

// Flags every active enemy bullet for the shrink animation. They keep moving
// and drawing while shrinking, but their hit radius collapses to 0 immediately
// since collide_bullets_player skips any shrinking bullet.
shrink_all_enemy_bullets :: proc(pool: ^Bullet_Pool) {
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind != .Enemy || b.shrinking {
			continue
		}
		b.shrinking = true
		b.shrink_t = 0
	}
}

collide_bullets_player :: proc(pool: ^Bullet_Pool, player: ^Player, audio: ^Audio) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	reflected_any := false
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind != .Enemy || b.shrinking {
			continue
		}
		r := f32(PLAYER_HIT_RADIUS) + bullet_hit_radius(b)
		r_sq := r * r
		dx := b.pos.x - pcx
		dy := b.pos.y - pcy
		if dx * dx + dy * dy > r_sq {
			continue
		}
		if player.dash_timer > 0 {
			b.kind = .Reflected
			b.vel = -b.vel
			if .Riposte in player.upgrades {
				b.lock_source = true
			}
			reflected_any = true
			continue
		}
		b.active = false
		damage_player(player, audio, PLAYER_HIT_DAMAGE)
		if player.invuln_timer > 0 {
			break
		}
	}
	if reflected_any {
		play_reflect_sfx(audio)
	}
}

collide_bullets_enemies :: proc(
	pool: ^Bullet_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^Score_Stats,
) {
	r_boss := boss_hit_radius(&boss.boss) + BULLET_RADIUS
	r_boss_sq := r_boss * r_boss
	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active || b.kind == .Enemy {
			continue
		}
		damage := REFLECT_DAMAGE
		impact_color := rl.Color{160, 220, 255, 255}
		score_kind := Score_Kind.Reflect
		if b.kind == .Rapid_Fire {
			damage = RAPID_FIRE_DAMAGE
			impact_color = rl.Color{255, 80, 80, 255}
			score_kind = .Rapid_Fire
		}
		hit := false
		for ei in 0 ..< ENEMY_COUNT {
			e := &enemies.enemies[ei]
			if !e.active {
				continue
			}
			ec := enemy_center(e)
			r := enemy_hit_radius(e) + BULLET_RADIUS
			dx := b.pos.x - ec.x
			dy := b.pos.y - ec.y
			if dx * dx + dy * dy <= r * r {
				killed := damage_enemy(e, damage)
				spawn_impact_particles(particles, ec, impact_color, REFLECT_IMPACT_PARTICLES)
				b.active = false
				if killed {
					add_kill(score, score_kind)
					try_spawn_sneak(sneaks)
					try_drop_healthpack(packs, ec)
				}
				hit = true
				break
			}
		}
		if hit {
			continue
		}
		for si in 0 ..< SNEAK_MAX {
			s := &sneaks.sneaks[si]
			if !s.active {
				continue
			}
			sc := sneak_center(s)
			r := sneak_hit_radius(s) + BULLET_RADIUS
			dx := b.pos.x - sc.x
			dy := b.pos.y - sc.y
			if dx * dx + dy * dy <= r * r {
				killed := damage_sneak(s, damage)
				spawn_impact_particles(particles, sc, impact_color, REFLECT_IMPACT_PARTICLES)
				b.active = false
				if killed {
					add_kill(score, score_kind)
					try_spawn_sneak(sneaks)
					try_drop_healthpack(packs, sc)
				}
				hit = true
				break
			}
		}
		if hit {
			continue
		}
		for pi in 0 ..< PILLAR_COUNT {
			p := &pillars.pillars[pi]
			if !p.active {
				continue
			}
			pc := pillar_center(p)
			r := pillar_hit_radius(p) + BULLET_RADIUS
			dx := b.pos.x - pc.x
			dy := b.pos.y - pc.y
			if dx * dx + dy * dy > r * r {
				continue
			}
			applied, killed := damage_pillar(pillars, pi, damage)
			if applied {
				spawn_impact_particles(particles, pc, impact_color, REFLECT_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Pillar)
				}
			} else {
				spawn_impact_particles(particles, pc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
			b.active = false
			hit = true
			break
		}
		if hit {
			continue
		}
		if boss.boss.active {
			bc := boss_center(&boss.boss)
			dx := b.pos.x - bc.x
			dy := b.pos.y - bc.y
			if dx * dx + dy * dy <= r_boss_sq {
				if boss_can_take_damage(&boss.boss) {
					killed := damage_boss(&boss.boss, damage)
					spawn_impact_particles(particles, bc, impact_color, REFLECT_IMPACT_PARTICLES)
					if killed {
						add_kill(score, .Boss)
						try_drop_healthpack(packs, bc)
					}
				} else {
					spawn_impact_particles(particles, bc, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
				}
				b.active = false
				continue
			}
		}
		if boss.boss.active && boss.boss.kind == .Ancient_Guardian {
			for oi in 0 ..< GUARDIAN_ORB_COUNT {
				o := &boss.boss.orbs[oi]
				if !o.active {
					continue
				}
				r: f32 = GUARDIAN_ORB_HIT_RADIUS + BULLET_RADIUS
				dx := b.pos.x - o.pos.x
				dy := b.pos.y - o.pos.y
				if dx * dx + dy * dy > r * r {
					continue
				}
				applied, killed := damage_guardian_orb(&boss.boss, oi, damage)
				if applied {
					spawn_impact_particles(particles, o.pos, impact_color, REFLECT_IMPACT_PARTICLES)
					if killed {
						add_kill(score, .Guardian_Orb)
					}
				} else {
					spawn_impact_particles(particles, o.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
				}
				b.active = false
				break
			}
		}
	}
}

// All bullets render through the glow shader as additive textured quads. The
// shader does the actual visual work — radial falloff, hot core, halo tint —
// so the only per-bullet decisions here are quad radius and color. Additive
// blending lets dense bullet patterns bloom into each other instead of reading
// as a flat collage of dots.
draw_bullets :: proc(pool: ^Bullet_Pool) {
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()
	rl.BeginShaderMode(pool.glow_shader)
	defer rl.EndShaderMode()

	for i in 0 ..< MAX_BULLETS {
		b := &pool.bullets[i]
		if !b.active {
			continue
		}
		radius: f32
		color: rl.Color
		switch b.kind {
		case .Enemy:
			scale := f32(1)
			if b.shrinking {
				scale = 1 - b.shrink_t
				if scale < 0 {
					scale = 0
				}
			}
			base := f32(BULLET_RADIUS)
			if b.is_burst_orb {
				base = MORGAN_ORB_DRAW_RADIUS
			}
			radius = base * BULLET_GLOW_MULT * scale
			color = b.color
		case .Reflected:
			radius = BULLET_RADIUS * BULLET_GLOW_MULT
			color = rl.Color{160, 220, 255, 255}
		case .Rapid_Fire:
			radius = RAPID_FIRE_RADIUS * RAPID_FIRE_GLOW_MULT
			color = rl.Color{255, 80, 80, 255}
		}
		if radius <= 0 {
			continue
		}
		draw_glow_quad(pool, b.pos, radius, color)
	}
}

@(private = "file")
draw_glow_quad :: proc(pool: ^Bullet_Pool, pos: rl.Vector2, radius: f32, color: rl.Color) {
	src := rl.Rectangle{0, 0, 1, 1}
	dst := rl.Rectangle{pos.x - radius, pos.y - radius, radius * 2, radius * 2}
	rl.DrawTexturePro(pool.glow_tex, src, dst, {0, 0}, 0, color)
}

// #endregion

// #region Missles


// Homing missile spawned by the Dash Frenzy upgrade. Projectiles are not
// sprites — the body is a stack of additive purple circles and the trail is a
// ring buffer of past positions, also drawn as fading purple glow circles.

Missile :: struct {
	pos:           rl.Vector2,
	vel:           rl.Vector2,
	life:          f32,
	blind_time:    f32, // grace before homing kicks in so the launch fan is visible
	trail:         [MISSILE_TRAIL_LEN]rl.Vector2,
	trail_count:   int,
	trail_sample:  f32,
	active:        bool,
}

Missile_Pool :: struct {
	missiles: [MAX_MISSILES]Missile,
}

launch_dash_missiles :: proc(
	pool: ^Missile_Pool,
	origin: rl.Vector2,
	dash_dir: rl.Vector2,
	count: int,
) {
	if count <= 0 {
		return
	}
	dir := dash_dir
	if rl.Vector2Length(dir) < 0.001 {
		dir = {0, -1}
	}
	dir = rl.Vector2Normalize(dir)
	base_angle := math.atan2(dir.y, dir.x)

	fan_rad := f32(DASH_FRENZY_LAUNCH_FAN_DEG) * math.PI / 180.0
	half_fan := fan_rad * 0.5

	for i in 0 ..< count {
		t: f32 = 0
		if count > 1 {
			t = f32(i) / f32(count - 1)
		}
		// Spread evenly across the fan, centered on the dash direction.
		angle := base_angle - half_fan + t * fan_rad
		vel := rl.Vector2{math.cos(angle) * MISSILE_SPEED, math.sin(angle) * MISSILE_SPEED}
		spawn_missile(pool, origin, vel)
	}
}

@(private = "file")
spawn_missile :: proc(pool: ^Missile_Pool, pos, vel: rl.Vector2) {
	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if m.active {
			continue
		}
		m^ = Missile {
			pos          = pos,
			vel          = vel,
			life         = MISSILE_LIFE,
			blind_time   = MISSILE_INITIAL_BLIND_TIME,
			trail_count  = 0,
			trail_sample = 0,
			active       = true,
		}
		return
	}
}

update_missiles :: proc(
	pool: ^Missile_Pool,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^Score_Stats,
	dt: f32,
) {
	steer_k := f32(1) - math.exp(-MISSILE_TURN_RATE * dt)

	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if !m.active {
			continue
		}

		if m.blind_time > 0 {
			m.blind_time -= dt
			if m.blind_time < 0 {
				m.blind_time = 0
			}
		} else {
			target, found := nearest_target(m.pos, enemies, sneaks, boss, pillars)
			if found {
				speed := rl.Vector2Length(m.vel)
				if speed > 0.001 {
					to_t := rl.Vector2Normalize(target - m.pos)
					target_vel := to_t * speed
					new_vel := m.vel * (1 - steer_k) + target_vel * steer_k
					nlen := rl.Vector2Length(new_vel)
					if nlen > 0.001 {
						// Renormalize to keep the cruise speed constant.
						m.vel = new_vel * (speed / nlen)
					}
				}
			}
		}

		m.pos += m.vel * dt
		m.life -= dt

		// Sample trail at fixed cadence rather than every frame so the spacing
		// is independent of framerate and the trail looks consistent.
		m.trail_sample += dt
		for m.trail_sample >= MISSILE_TRAIL_SAMPLE_INTERVAL {
			m.trail_sample -= MISSILE_TRAIL_SAMPLE_INTERVAL
			push_trail_sample(m, m.pos)
		}

		// Despawn if off-screen by a comfortable margin or out of life.
		if m.life <= 0 ||
		   m.pos.x < -32 ||
		   m.pos.y < -32 ||
		   m.pos.x > f32(SCREEN_WIDTH) + 32 ||
		   m.pos.y > f32(SCREEN_HEIGHT) + 32 {
			m.active = false
			continue
		}

		// Collision: first hit detonates the missile.
		if try_hit_missile(m, enemies, sneaks, boss, pillars, packs, particles, score) {
			m.active = false
		}
	}
}

@(private = "file")
push_trail_sample :: proc(m: ^Missile, p: rl.Vector2) {
	if m.trail_count < MISSILE_TRAIL_LEN {
		m.trail_count += 1
	}
	for i := m.trail_count - 1; i > 0; i -= 1 {
		m.trail[i] = m.trail[i - 1]
	}
	m.trail[0] = p
}

@(private = "file")
nearest_target :: proc(
	from: rl.Vector2,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
) -> (
	target: rl.Vector2,
	found: bool,
) {
	best_d_sq := f32(1e18)
	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if !e.active {
			continue
		}
		ec := enemy_center(e)
		dx := ec.x - from.x
		dy := ec.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = ec
			found = true
		}
	}
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if !s.active {
			continue
		}
		sc := sneak_center(s)
		dx := sc.x - from.x
		dy := sc.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = sc
			found = true
		}
	}
	if boss.boss.active {
		bc := boss_center(&boss.boss)
		dx := bc.x - from.x
		dy := bc.y - from.y
		d_sq := dx * dx + dy * dy
		if d_sq < best_d_sq {
			best_d_sq = d_sq
			target = bc
			found = true
		}
	}
	// Guardian orbs are valid homing targets — invulnerable orbs absorb the
	// missile, but homing toward them is consistent with the rest of the
	// "any visible threat is a target" rule.
	if boss.boss.active && boss.boss.kind == .Ancient_Guardian {
		for i in 0 ..< GUARDIAN_ORB_COUNT {
			o := &boss.boss.orbs[i]
			if !o.active {
				continue
			}
			dx := o.pos.x - from.x
			dy := o.pos.y - from.y
			d_sq := dx * dx + dy * dy
			if d_sq < best_d_sq {
				best_d_sq = d_sq
				target = o.pos
				found = true
			}
		}
	}
	// Pillars are valid homing targets like any other enemy — wrong-order locks
	// just waste the missile on a blocked impact, which is the cost of firing
	// without aiming. The kill-order puzzle stays intact.
	if pillars.phase == .Combat {
		for i in 0 ..< PILLAR_COUNT {
			p := &pillars.pillars[i]
			if !p.active {
				continue
			}
			pc := pillar_center(p)
			dx := pc.x - from.x
			dy := pc.y - from.y
			d_sq := dx * dx + dy * dy
			if d_sq < best_d_sq {
				best_d_sq = d_sq
				target = pc
				found = true
			}
		}
	}
	return
}

@(private = "file")
try_hit_missile :: proc(
	m: ^Missile,
	enemies: ^Enemy_Pool,
	sneaks: ^Sneak_Pool,
	boss: ^Boss_Pool,
	pillars: ^Pillar_Wave,
	packs: ^HealthPack_Pool,
	particles: ^Particle_Pool,
	score: ^Score_Stats,
) -> bool {
	for i in 0 ..< ENEMY_COUNT {
		e := &enemies.enemies[i]
		if !e.active {
			continue
		}
		ec := enemy_center(e)
		r := enemy_hit_radius(e) + MISSILE_HIT_RADIUS
		dx := m.pos.x - ec.x
		dy := m.pos.y - ec.y
		if dx * dx + dy * dy <= r * r {
			killed := damage_enemy(e, MISSILE_DAMAGE)
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Missile)
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, ec)
			}
			return true
		}
	}
	for i in 0 ..< SNEAK_MAX {
		s := &sneaks.sneaks[i]
		if !s.active {
			continue
		}
		sc := sneak_center(s)
		r := sneak_hit_radius(s) + MISSILE_HIT_RADIUS
		dx := m.pos.x - sc.x
		dy := m.pos.y - sc.y
		if dx * dx + dy * dy <= r * r {
			killed := damage_sneak(s, MISSILE_DAMAGE)
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Missile)
				try_spawn_sneak(sneaks)
				try_drop_healthpack(packs, sc)
			}
			return true
		}
	}
	if boss.boss.active {
		bc := boss_center(&boss.boss)
		r := boss_hit_radius(&boss.boss) + MISSILE_HIT_RADIUS
		dx := m.pos.x - bc.x
		dy := m.pos.y - bc.y
		if dx * dx + dy * dy <= r * r {
			if boss_can_take_damage(&boss.boss) {
				killed := damage_boss(&boss.boss, MISSILE_DAMAGE)
				spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Boss)
					try_drop_healthpack(packs, bc)
				}
			} else {
				spawn_impact_particles(particles, m.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
			return true
		}
	}
	if boss.boss.active && boss.boss.kind == .Ancient_Guardian {
		for i in 0 ..< GUARDIAN_ORB_COUNT {
			o := &boss.boss.orbs[i]
			if !o.active {
				continue
			}
			r: f32 = GUARDIAN_ORB_HIT_RADIUS + MISSILE_HIT_RADIUS
			dx := m.pos.x - o.pos.x
			dy := m.pos.y - o.pos.y
			if dx * dx + dy * dy > r * r {
				continue
			}
			applied, killed := damage_guardian_orb(&boss.boss, i, MISSILE_DAMAGE)
			if applied {
				spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
				if killed {
					add_kill(score, .Guardian_Orb)
				}
			} else {
				spawn_impact_particles(particles, m.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
			}
			return true
		}
	}
	for i in 0 ..< PILLAR_COUNT {
		p := &pillars.pillars[i]
		if !p.active {
			continue
		}
		pc := pillar_center(p)
		r := pillar_hit_radius(p) + MISSILE_HIT_RADIUS
		dx := m.pos.x - pc.x
		dy := m.pos.y - pc.y
		if dx * dx + dy * dy > r * r {
			continue
		}
		applied, killed := damage_pillar(pillars, i, MISSILE_DAMAGE)
		if applied {
			spawn_impact_particles(particles, m.pos, rl.MAGENTA, MISSILE_IMPACT_PARTICLES)
			if killed {
				add_kill(score, .Pillar)
			}
		} else {
			spawn_impact_particles(particles, m.pos, rl.WHITE, PILLAR_BLOCKED_PARTICLES)
		}
		return true
	}
	return false
}

draw_missiles :: proc(pool: ^Missile_Pool) {
	rl.BeginBlendMode(.ADDITIVE)
	defer rl.EndBlendMode()

	for i in 0 ..< MAX_MISSILES {
		m := &pool.missiles[i]
		if !m.active {
			continue
		}
		draw_missile_trail(m)
		draw_missile_body(m)
	}
}

@(private = "file")
draw_missile_body :: proc(m: ^Missile) {
	// Layered concentric circles produce the soft purple glow. Outer layers are
	// dimmer and wider; the inner core is a hot near-white pixel.
	for layer in 0 ..< MISSILE_GLOW_LAYERS {
		t := f32(layer) / f32(MISSILE_GLOW_LAYERS - 1)
		radius := f32(MISSILE_BODY_RADIUS) * (1.0 + t * 3.5)
		// Outer glow: deep purple. Inner: hotter magenta-white.
		r := u8(180 + (1.0 - t) * 60)
		g := u8(60 + (1.0 - t) * 140)
		b := u8(220 + (1.0 - t) * 30)
		a := u8(40 + (1.0 - t) * 160)
		rl.DrawCircleV(m.pos, radius, rl.Color{r, g, b, a})
	}
	// Bright white-ish core for the lit-fuse impression.
	rl.DrawCircleV(m.pos, MISSILE_BODY_RADIUS * 0.6, rl.Color{255, 230, 255, 255})
}

@(private = "file")
draw_missile_trail :: proc(m: ^Missile) {
	if m.trail_count == 0 {
		return
	}
	// Iterate oldest-first so newer (more opaque) glow nodes overdraw older ones,
	// matching the dash trail convention elsewhere in the codebase.
	for k := m.trail_count - 1; k >= 0; k -= 1 {
		ratio := 1.0 - f32(k) / f32(MISSILE_TRAIL_LEN)
		if ratio <= 0 {
			continue
		}
		base_radius := f32(MISSILE_TRAIL_NODE_RADIUS) * ratio
		for layer in 0 ..< MISSILE_GLOW_LAYERS {
			lt := f32(layer) / f32(MISSILE_GLOW_LAYERS - 1)
			radius := base_radius * (1.0 + lt * 3.0)
			r := u8(160 + (1.0 - lt) * 60)
			g := u8(40 + (1.0 - lt) * 100)
			b := u8(200 + (1.0 - lt) * 40)
			alpha := f32(30 + (1.0 - lt) * 120) * ratio
			rl.DrawCircleV(m.trail[k], radius, rl.Color{r, g, b, u8(alpha)})
		}
	}
}

// #endregion

