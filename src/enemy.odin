package game

import "core:math"
import "core:math/rand"
import rl "vendor:raylib"

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

Enemy_Pool :: struct {
	enemies:       [ENEMY_COUNT]Enemy,
	tex:           rl.Texture2D,
	weirdguy_tex:  rl.Texture2D,
	flash_shader:  rl.Shader,
	level:         int,
	waves_cleared: int,
	fire_interval: f32,
	boost_applied: bool,
}

init_enemies :: proc(pool: ^Enemy_Pool) {
	pool.tex = rl.LoadTexture("assets/sprites/enemy_grunt_move.png")
	rl.SetTextureFilter(pool.tex, .POINT)
	pool.weirdguy_tex = rl.LoadTexture("assets/sprites/enemy_weirdguy_move.png")
	rl.SetTextureFilter(pool.weirdguy_tex, .POINT)
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
	rl.UnloadShader(pool.flash_shader)
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

@(private = "file")
spawn_weirdguy_wave :: proc(pool: ^Enemy_Pool) {
	half := f32(WEIRDGUY_PATROL_RANGE) * 0.5
	margin := f32(WEIRDGUY_FRAME_W * WEIRDGUY_DRAW_SCALE) * 0.5
	min_center := margin + half
	max_center := f32(SCREEN_WIDTH) - margin - half
	for i in 0 ..< WEIRDGUY_WAVE_COUNT {
		center_x := min_center + rand.float32() * (max_center - min_center)
		y := WEIRDGUY_Y_MIN + rand.float32() * (WEIRDGUY_Y_MAX - WEIRDGUY_Y_MIN)
		dir: f32 = rand.float32() < 0.5 ? 1.0 : -1.0
		start_x := center_x + (rand.float32() * 2 - 1) * half
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
	dt: f32,
) {
	any_alive := false
	for i in 0 ..< ENEMY_COUNT {
		if pool.enemies[i].active {
			any_alive = true
			break
		}
	}
	if !any_alive {
		// Suppress respawns while Golgatha is on the field; sneaks still flow.
		if !boss.boss.active {
			pool.waves_cleared += 1
			if pool.waves_cleared == BOSS_TRIGGER_WAVE && pool.level < 2 {
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
			update_grunt_one(e, pool.fire_interval, bullets, dt)
		case .WeirdGuy:
			update_weirdguy_one(e, player_center, bullets, dt)
		}
	}
}

@(private = "file")
update_grunt_one :: proc(e: ^Enemy, fire_interval: f32, bullets: ^Bullet_Pool, dt: f32) {
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
			spawn_bullet(bullets, e.pos, vel)
		}
	}
}

@(private = "file")
update_weirdguy_one :: proc(
	e: ^Enemy,
	player_center: rl.Vector2,
	bullets: ^Bullet_Pool,
	dt: f32,
) {
	d := &e.data.(WeirdGuy_Data)

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
		spawn_bullet(bullets, e.pos, vel, color)
	}
}

draw_enemies :: proc(pool: ^Enemy_Pool) {
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
