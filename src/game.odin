package game

import "core:c"
import "core:math"
import rl "vendor:raylib"
import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:math/rand"
import "core:strings"


// #region Audio

// One stream per track. Mapping:
//   Main_Menu       — main_menu.ogg, the menu/options/controls screens
//   Gameplay        — themesong2, levels 1 and 4
//   Levels_2_3      — themesong3, levels 2 and 3
//   Guardian        — themesong4, level 5 boss fight
//   Final_Victory   — themesong1, only the post-final-boss screen
Music_Track :: enum {
	Main_Menu,
	Gameplay,
	Levels_2_3,
	Guardian,
	Final_Victory,
}

MUSIC_TRACK_PATHS := [Music_Track]cstring {
	.Main_Menu     = "assets/audio/soundtrack/main_menu.ogg",
	.Gameplay      = "assets/audio/soundtrack/themesong2.ogg",
	.Levels_2_3    = "assets/audio/soundtrack/themesong3_lvl2-lvl3.ogg",
	.Guardian      = "assets/audio/soundtrack/themesong4_guardian.ogg",
	.Final_Victory = "assets/audio/soundtrack/themesong1.ogg",
}

Audio :: struct {
	music_volume:             f32,
	sfx_volume:               f32,
	music:                    [Music_Track]rl.Music,
	current_track:            Music_Track,
	sfx_charged_beam:         rl.Sound,
	sfx_charging_beam:        rl.Sound,
	sfx_cyclops_attack:       rl.Sound,
	sfx_dash:                 rl.Sound,
	sfx_enemy_dies:           rl.Sound,
	sfx_enemy_takes_damage:   rl.Sound,
	sfx_golgotha_bullet_hell: rl.Sound,
	sfx_golgotha_scream:      rl.Sound,
	sfx_grunts_attack:        rl.Sound,
	sfx_guardian_1:           rl.Sound,
	sfx_guardian_2:           rl.Sound,
	sfx_guardian_3:           rl.Sound,
	sfx_laser:                rl.Sound,
	sfx_morgan_chatter:       rl.Sound,
	morgan_chatter_timer:     f32,
	sfx_rapid_fire:           rl.Sound,
	sfx_reflects_bullet:      rl.Sound,
	sfx_shrink_bullets:       rl.Sound,
	sfx_sneak_teleport:       rl.Sound,
	sfx_takes_damage:         rl.Sound,
	sfx_weird_guys_die:       rl.Sound,
}

init_audio :: proc(a: ^Audio) {
	rl.InitAudioDevice()
	a.music_volume = MUSIC_VOLUME
	a.sfx_volume = SFX_VOLUME

	for t in Music_Track {
		a.music[t] = rl.LoadMusicStream(MUSIC_TRACK_PATHS[t])
		a.music[t].looping = true
		rl.SetMusicVolume(a.music[t], a.music_volume)
	}
	a.current_track = .Main_Menu
	rl.PlayMusicStream(a.music[a.current_track])

	a.sfx_charged_beam = rl.LoadSound("assets/audio/sfx/player_charged_beam.wav")
	a.sfx_charging_beam = rl.LoadSound("assets/audio/sfx/player_charging_beam.wav")
	a.sfx_cyclops_attack = rl.LoadSound("assets/audio/sfx/cyclops_attack.wav")
	a.sfx_dash = rl.LoadSound("assets/audio/sfx/player_dash.wav")
	a.sfx_enemy_dies = rl.LoadSound("assets/audio/sfx/enemies_die_grunts_sneaks_cyclops_pillars_bosses.wav")
	a.sfx_enemy_takes_damage = rl.LoadSound("assets/audio/sfx/enemies_take_damage.wav")
	a.sfx_golgotha_bullet_hell = rl.LoadSound("assets/audio/golgotha_bullet_hell.wav")
	a.sfx_golgotha_scream = rl.LoadSound("assets/audio/sfx/golgotha_scream.wav")
	a.sfx_grunts_attack = rl.LoadSound("assets/audio/sfx/grunts_attack.wav")
	a.sfx_guardian_1 = rl.LoadSound("assets/audio/sfx/guardian_sound1.wav")
	a.sfx_guardian_2 = rl.LoadSound("assets/audio/sfx/guardian_sound2.wav")
	a.sfx_guardian_3 = rl.LoadSound("assets/audio/sfx/guardian_sound3.wav")
	a.sfx_laser = rl.LoadSound("assets/audio/sfx/player_laser.wav")
	a.sfx_morgan_chatter = rl.LoadSound("assets/audio/sfx/morgan_chatter.wav")
	a.sfx_rapid_fire = rl.LoadSound("assets/audio/sfx/player_rapid_fire.wav")
	a.sfx_reflects_bullet = rl.LoadSound("assets/audio/sfx/player_reflects_bullet.wav")
	a.sfx_shrink_bullets = rl.LoadSound("assets/audio/sfx/player_shrink_bullets.wav")
	a.sfx_sneak_teleport = rl.LoadSound("assets/audio/sfx/sneaks_teleport_or_spawn.wav")
	a.sfx_takes_damage = rl.LoadSound("assets/audio/sfx/player_takes_damage.wav")
	a.sfx_weird_guys_die = rl.LoadSound("assets/audio/sfx/weird_guys_die.wav")

	apply_sfx_volume(a)
}

update_audio :: proc(a: ^Audio) {
	rl.UpdateMusicStream(a.music[a.current_track])
}

// Idempotent track swap — safe to call every frame.
play_track :: proc(a: ^Audio, t: Music_Track) {
	if a.current_track == t {
		return
	}
	was_lpf := lpf_attached
	if was_lpf {
		rl.DetachAudioStreamProcessor(a.music[a.current_track].stream, audio_lpf)
		lpf_attached = false
	}
	rl.StopMusicStream(a.music[a.current_track])
	rl.PlayMusicStream(a.music[t])
	a.current_track = t
	if was_lpf {
		lpf_state = {0, 0}
		rl.AttachAudioStreamProcessor(a.music[t].stream, audio_lpf)
		lpf_attached = true
	}
}

// One-pole RC low-pass per channel, attached to the music stream while Slow
// Time is held to muffle the soundtrack as a sensory cue. Modeled on raylib's
// stream-effects example: stereo float32 interleaved buffer. Runs on raylib's
// audio thread, so it must be `proc "c"` (no implicit context).
@(private = "file")
lpf_state := [2]f32{0, 0}

@(private = "file")
lpf_attached: bool

@(private = "file")
audio_lpf :: proc "c" (buffer: rawptr, frames: c.uint) {
	cutoff :: SLOW_TIME_LPF_CUTOFF_HZ / 44100.0
	k :: cutoff / (cutoff + 0.1591549431) // 1/(2*pi); RC filter formula
	data := ([^]f32)(buffer)
	for i: c.uint = 0; i < frames * 2; i += 2 {
		l := data[i]
		r := data[i + 1]
		lpf_state[0] += k * (l - lpf_state[0])
		lpf_state[1] += k * (r - lpf_state[1])
		data[i] = lpf_state[0]
		data[i + 1] = lpf_state[1]
	}
}

// Idempotent: safe to call every frame with the current Slow Time state.
set_music_lpf_enabled :: proc(a: ^Audio, enabled: bool) {
	if enabled == lpf_attached {
		return
	}
	if enabled {
		// Reset accumulator so the filter doesn't pop from a stale tail.
		lpf_state = {0, 0}
		rl.AttachAudioStreamProcessor(a.music[a.current_track].stream, audio_lpf)
	} else {
		rl.DetachAudioStreamProcessor(a.music[a.current_track].stream, audio_lpf)
	}
	lpf_attached = enabled
}

// Picks the right gameplay track for a level. Used at level entry and on
// returns to menu / new-game starts.
gameplay_track_for_level :: proc(level: int) -> Music_Track {
	switch level {
	case 2, 3:
		return .Levels_2_3
	case 5:
		return .Guardian
	}
	return .Gameplay
}

unload_audio :: proc(a: ^Audio) {
	if lpf_attached {
		rl.DetachAudioStreamProcessor(a.music[a.current_track].stream, audio_lpf)
		lpf_attached = false
	}
	for t in Music_Track {
		rl.StopMusicStream(a.music[t])
		rl.UnloadMusicStream(a.music[t])
	}
	rl.UnloadSound(a.sfx_charged_beam)
	rl.UnloadSound(a.sfx_charging_beam)
	rl.UnloadSound(a.sfx_cyclops_attack)
	rl.UnloadSound(a.sfx_dash)
	rl.UnloadSound(a.sfx_enemy_dies)
	rl.UnloadSound(a.sfx_enemy_takes_damage)
	rl.UnloadSound(a.sfx_golgotha_bullet_hell)
	rl.UnloadSound(a.sfx_golgotha_scream)
	rl.UnloadSound(a.sfx_grunts_attack)
	rl.UnloadSound(a.sfx_guardian_1)
	rl.UnloadSound(a.sfx_guardian_2)
	rl.UnloadSound(a.sfx_guardian_3)
	rl.UnloadSound(a.sfx_laser)
	rl.UnloadSound(a.sfx_morgan_chatter)
	rl.UnloadSound(a.sfx_rapid_fire)
	rl.UnloadSound(a.sfx_reflects_bullet)
	rl.UnloadSound(a.sfx_shrink_bullets)
	rl.UnloadSound(a.sfx_sneak_teleport)
	rl.UnloadSound(a.sfx_takes_damage)
	rl.UnloadSound(a.sfx_weird_guys_die)
	rl.CloseAudioDevice()
}

set_music_volume :: proc(a: ^Audio, v: f32) {
	a.music_volume = clamp(v, 0.0, 1.0)
	for t in Music_Track {
		rl.SetMusicVolume(a.music[t], a.music_volume)
	}
}

set_sfx_volume :: proc(a: ^Audio, v: f32) {
	a.sfx_volume = clamp(v, 0.0, 1.0)
	apply_sfx_volume(a)
}

@(private = "file")
apply_sfx_volume :: proc(a: ^Audio) {
	rl.SetSoundVolume(a.sfx_charged_beam, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_charging_beam, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_cyclops_attack, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_dash, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_enemy_dies, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_enemy_takes_damage, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_golgotha_bullet_hell, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_golgotha_scream, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_grunts_attack, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_guardian_1, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_guardian_2, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_guardian_3, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_laser, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_morgan_chatter, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_rapid_fire, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_reflects_bullet, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_shrink_bullets, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_sneak_teleport, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_takes_damage, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_weird_guys_die, a.sfx_volume)
}

play_dash_sfx :: proc(a: ^Audio)          {rl.PlaySound(a.sfx_dash)}
play_laser_sfx :: proc(a: ^Audio)         {rl.PlaySound(a.sfx_laser)}
play_charged_beam_sfx :: proc(a: ^Audio)  {rl.PlaySound(a.sfx_charged_beam)}
play_reflect_sfx :: proc(a: ^Audio)       {rl.PlaySound(a.sfx_reflects_bullet)}
play_shrink_bomb_sfx :: proc(a: ^Audio)   {rl.PlaySound(a.sfx_shrink_bullets)}
play_player_damage_sfx :: proc(a: ^Audio) {rl.PlaySound(a.sfx_takes_damage)}
play_golgotha_scream_sfx :: proc(a: ^Audio) {rl.PlaySound(a.sfx_golgotha_scream)}

// Per-frame enemy event cues. PlaySound restarts the clip on every call, so
// dozens of simultaneous grunts/cyclops would clip into a buzz — the
// is-playing guard throttles each cue to "at most one instance at a time."
// Death cues use the same guard: when a beam sweep kills several grunts in
// one frame we get one death sound, not a stack.
play_grunt_attack_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_grunts_attack) {
		rl.PlaySound(a.sfx_grunts_attack)
	}
}
play_cyclops_attack_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_cyclops_attack) {
		rl.PlaySound(a.sfx_cyclops_attack)
	}
}
play_sneak_teleport_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_sneak_teleport) {
		rl.PlaySound(a.sfx_sneak_teleport)
	}
}
play_enemy_damage_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_enemy_takes_damage) {
		rl.PlaySound(a.sfx_enemy_takes_damage)
	}
}
play_enemy_death_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_enemy_dies) {
		rl.PlaySound(a.sfx_enemy_dies)
	}
}
play_weirdguy_death_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_weird_guys_die) {
		rl.PlaySound(a.sfx_weird_guys_die)
	}
}

// Morgan ambient chatter — fires once when the cooldown expires, then waits a
// randomized gap before the next play so she mutters intermittently rather
// than looping nonstop. Caller ticks every frame she's on the field.
tick_morgan_chatter_sfx :: proc(a: ^Audio, dt: f32) {
	if rl.IsSoundPlaying(a.sfx_morgan_chatter) {
		return
	}
	a.morgan_chatter_timer -= dt
	if a.morgan_chatter_timer <= 0 {
		rl.PlaySound(a.sfx_morgan_chatter)
		span := f32(MORGAN_CHATTER_INTERVAL_MAX - MORGAN_CHATTER_INTERVAL_MIN)
		a.morgan_chatter_timer = MORGAN_CHATTER_INTERVAL_MIN + rand.float32() * span
	}
}

stop_morgan_chatter_sfx :: proc(a: ^Audio) {
	rl.StopSound(a.sfx_morgan_chatter)
	a.morgan_chatter_timer = 0
}

// Guardian intro: sounds 1 and 2 layered together for a thick stinger when
// the Ancient Guardian first appears.
play_guardian_intro_sfx :: proc(a: ^Audio) {
	rl.PlaySound(a.sfx_guardian_1)
	rl.PlaySound(a.sfx_guardian_2)
}

// One random guardian voice cue per orb death; cycles through 1/2/3 so kills
// feel reactive rather than canned.
play_guardian_orb_death_sfx :: proc(a: ^Audio) {
	switch rand.int31() % 3 {
	case 0:
		rl.PlaySound(a.sfx_guardian_1)
	case 1:
		rl.PlaySound(a.sfx_guardian_2)
	case:
		rl.PlaySound(a.sfx_guardian_3)
	}
}

// Charging-beam cue is held by retriggering a short clip whenever the previous
// instance has finished. Call every frame while the player is charging, and
// stop_charging_beam_sfx when charging ends or aborts.
tick_charging_beam_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_charging_beam) {
		rl.PlaySound(a.sfx_charging_beam)
	}
}

stop_charging_beam_sfx :: proc(a: ^Audio) {
	rl.StopSound(a.sfx_charging_beam)
}

// Rapid-fire and Golgatha bullet-hell sfx are pre-rendered loops (see the .ck
// sources next to the wavs). Same retrigger-when-finished pattern as the
// charging beam: tick every frame the source is active, stop when it isn't.
tick_rapid_fire_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_rapid_fire) {
		rl.PlaySound(a.sfx_rapid_fire)
	}
}

stop_rapid_fire_sfx :: proc(a: ^Audio) {
	rl.StopSound(a.sfx_rapid_fire)
}

tick_golgotha_bullet_hell_sfx :: proc(a: ^Audio) {
	if !rl.IsSoundPlaying(a.sfx_golgotha_bullet_hell) {
		rl.PlaySound(a.sfx_golgotha_bullet_hell)
	}
}

stop_golgotha_bullet_hell_sfx :: proc(a: ^Audio) {
	rl.StopSound(a.sfx_golgotha_bullet_hell)
}
// #endregion

// #region Game Backdrops

Background :: struct {
	textures:    [BG_LAYERS]rl.Texture2D,
	offsets:     [BG_LAYERS]f32,
	speeds:      [BG_LAYERS]f32,
	// Level 3+ swaps the parallax stack for a single static image with a wave-shader
	// distortion. shader_mode tracks that swap; seconds drives the shader's animation.
	wave:        Wave_Shader,
	seconds:     f32,
	shader_mode: bool,
}

init_background :: proc(bg: ^Background) {
	bg.speeds = {10, 25, 60}
	bg.wave = load_wave_shader()
	load_bg_textures(bg, 1)
}

unload_background :: proc(bg: ^Background) {
	unload_wave_shader(&bg.wave)
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(bg.textures[i])
	}
}

set_background_level :: proc(bg: ^Background, level: int) {
	for i in 0 ..< BG_LAYERS {
		rl.UnloadTexture(bg.textures[i])
		bg.textures[i] = {}
		bg.offsets[i] = 0
	}
	bg.shader_mode = level == 3 || level == 5
	bg.seconds = 0
	load_bg_textures(bg, level)
}

@(private = "file")
bg_path :: proc(level: int, i: int) -> cstring {
	if level <= 1 {
		return fmt.ctprintf("assets/parallaxbg%d.png", i)
	}
	if level == 3 {
		return "assets/Morgan_Fight_Background.png"
	}
	if level == 5 {
		// Ancient Guardian fight reuses the wave shader with its own backdrop.
		return "assets/level3_bg.png"
	}
	// Level 4 reuses the level-2 parallax stack for now.
	return fmt.ctprintf("assets/level2_parallaxbg%d.png", i)
}

// The bg0 file may be a stacked atlas of all BG_LAYERS frames (one per
// SCREEN_HEIGHT row), in which case bg1/bg2 files are ignored. Level 3+
// uses a single non-scrolling image and ignores the layer machinery entirely.
@(private = "file")
load_bg_textures :: proc(bg: ^Background, level: int) {
	if bg.shader_mode {
		bg.textures[0] = rl.LoadTexture(bg_path(level, 0))
		rl.SetTextureFilter(bg.textures[0], .POINT)
		return
	}

	img := rl.LoadImage(bg_path(level, 0))
	defer rl.UnloadImage(img)

	if img.height >= SCREEN_HEIGHT * BG_LAYERS {
		for i in 0 ..< BG_LAYERS {
			rec := rl.Rectangle{0, f32(i * SCREEN_HEIGHT), f32(img.width), f32(SCREEN_HEIGHT)}
			slice := rl.ImageFromImage(img, rec)
			bg.textures[i] = rl.LoadTextureFromImage(slice)
			rl.UnloadImage(slice)
			rl.SetTextureFilter(bg.textures[i], .POINT)
		}
		return
	}

	bg.textures[0] = rl.LoadTextureFromImage(img)
	rl.SetTextureFilter(bg.textures[0], .POINT)
	for i in 1 ..< BG_LAYERS {
		bg.textures[i] = rl.LoadTexture(bg_path(level, i))
		rl.SetTextureFilter(bg.textures[i], .POINT)
	}
}

update_background :: proc(bg: ^Background, dt: f32) {
	if bg.shader_mode {
		bg.seconds += dt
		return
	}
	for i in 0 ..< BG_LAYERS {
		h := f32(bg.textures[i].height)
		bg.offsets[i] += bg.speeds[i] * dt
		for bg.offsets[i] >= h {
			bg.offsets[i] -= h
		}
	}
}

draw_background :: proc(bg: ^Background) {
	if bg.shader_mode {
		tex := bg.textures[0]
		if tex.id == 0 {
			return
		}
		set_wave_seconds(&bg.wave, bg.seconds)
		rl.BeginShaderMode(bg.wave.shader)
		rl.DrawTexture(tex, 0, 0, rl.WHITE)
		rl.EndShaderMode()
		return
	}
	for i in 0 ..< BG_LAYERS {
		tex := bg.textures[i]
		if tex.height <= 0 {
			continue
		}
		h := f32(tex.height)
		y := bg.offsets[i] - h
		for cy := y; cy < f32(SCREEN_HEIGHT); cy += h {
			rl.DrawTexture(tex, 0, i32(cy), rl.WHITE)
		}
	}
}


// #endregion

//#region Mission I: Raid Golgatha's Headquarters


// Stage-card title shown for a few seconds when a mission begins. 

Mission_Title :: struct {
	active:   bool,
	timer:    f32,
	title:    cstring,
	subtitle: cstring,
}

show_mission_title :: proc(mt: ^Mission_Title, level: int) {
	title, sub, ok := mission_strings(level)
	if !ok {
		mt.active = false
		return
	}
	mt.title = title
	mt.subtitle = sub
	mt.timer = 0
	mt.active = true
}

@(private = "file")
mission_strings :: proc(level: int) -> (title: cstring, sub: cstring, ok: bool) {
	switch level {
	case 1:
		return cstring("MISSION I"), cstring("RAID GOLGATHA'S HEADQUARTERS"), true
	}
	return "", "", false
}

update_mission_title :: proc(mt: ^Mission_Title, dt: f32) {
	if !mt.active {
		return
	}
	mt.timer += dt
	total := f32(MISSION_TITLE_FADE_IN + MISSION_TITLE_HOLD + MISSION_TITLE_FADE_OUT)
	if mt.timer >= total {
		mt.active = false
	}
}

draw_mission_title :: proc(mt: ^Mission_Title) {
	if !mt.active {
		return
	}
	a := mission_title_alpha(mt.timer)
	if a == 0 {
		return
	}

	tw := rl.MeasureText(mt.title, MISSION_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	ty: i32 = MISSION_TITLE_Y
	rl.DrawText(mt.title, tx + 2, ty + 2, MISSION_TITLE_FONT_SIZE, rl.Color{0, 0, 0, a})
	rl.DrawText(mt.title, tx, ty, MISSION_TITLE_FONT_SIZE, rl.Color{255, 220, 80, a})

	sw := rl.MeasureText(mt.subtitle, MISSION_SUBTITLE_FONT_SIZE)
	sx := (i32(SCREEN_WIDTH) - sw) / 2
	sy: i32 = ty + MISSION_TITLE_FONT_SIZE + MISSION_SUBTITLE_GAP
	rl.DrawText(mt.subtitle, sx + 1, sy + 1, MISSION_SUBTITLE_FONT_SIZE, rl.Color{0, 0, 0, a})
	rl.DrawText(mt.subtitle, sx, sy, MISSION_SUBTITLE_FONT_SIZE, rl.Color{220, 220, 240, a})
}

@(private = "file")
mission_title_alpha :: proc(t: f32) -> u8 {
	fade_in := f32(MISSION_TITLE_FADE_IN)
	hold := f32(MISSION_TITLE_HOLD)
	fade_out := f32(MISSION_TITLE_FADE_OUT)
	a: f32
	switch {
	case t < fade_in:
		a = smoothstep(t / fade_in)
	case t < fade_in + hold:
		a = 1
	case t < fade_in + hold + fade_out:
		a = 1 - smoothstep((t - fade_in - hold) / fade_out)
	case:
		a = 0
	}
	if a < 0 {
		a = 0
	}
	if a > 1 {
		a = 1
	}
	return u8(a * 255)
}

//#endregion

// #region Drops (Health,etc)
HealthPack :: struct {
	pos:    rl.Vector2,
	phase:  f32,
	active: bool,
}

HealthPack_Pool :: struct {
	packs: [HEALTHPACK_MAX]HealthPack,
}

init_healthpacks :: proc(pool: ^HealthPack_Pool) {
	for i in 0 ..< HEALTHPACK_MAX {
		pool.packs[i].active = false
	}
}

try_drop_healthpack :: proc(pool: ^HealthPack_Pool, pos: rl.Vector2) {
	if rand.float32() >= HEALTHPACK_DROP_CHANCE {
		return
	}
	for i in 0 ..< HEALTHPACK_MAX {
		if !pool.packs[i].active {
			pool.packs[i] = HealthPack {
				pos    = pos,
				phase  = rand.float32() * math.TAU,
				active = true,
			}
			return
		}
	}
}

update_healthpacks :: proc(pool: ^HealthPack_Pool, player: ^Player, dt: f32) {
	pcx := player.pos.x + f32(PLAYER_FRAME_W * PLAYER_DRAW_SCALE) * 0.5
	pcy := player.pos.y + f32(PLAYER_FRAME_H * PLAYER_DRAW_SCALE) * 0.5
	r := f32(PLAYER_HIT_RADIUS) + HEALTHPACK_RADIUS
	r_sq := r * r
	for i in 0 ..< HEALTHPACK_MAX {
		h := &pool.packs[i]
		if !h.active {
			continue
		}
		h.pos.y += HEALTHPACK_DRIFT_SPEED * dt
		if h.pos.y - HEALTHPACK_ARM > f32(SCREEN_HEIGHT) {
			h.active = false
			continue
		}

		dx := h.pos.x - pcx
		dy := h.pos.y - pcy
		if dx * dx + dy * dy <= r_sq {
			h.active = false
			player.hp += HEALTHPACK_HEAL
			if player.hp > player.max_hp {
				player.hp = player.max_hp
			}
		}
	}
}

draw_healthpacks :: proc(pool: ^HealthPack_Pool) {
	t := f32(rl.GetTime())
	for i in 0 ..< HEALTHPACK_MAX {
		h := &pool.packs[i]
		if !h.active {
			continue
		}
		pulse: f32 = 0.85 + math.sin(t * HEALTHPACK_PULSE_HZ * math.TAU + h.phase) * 0.15
		arm: f32 = HEALTHPACK_ARM * pulse
		thick: f32 = HEALTHPACK_THICK

		glow := rl.Color{120, 255, 140, 80}
		rl.DrawCircleV(h.pos, arm * 1.6, glow)

		back_arm: f32 = arm + 1
		back_thick: f32 = thick + 2
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - back_arm, h.pos.y - back_thick * 0.5, back_arm * 2, back_thick},
			rl.WHITE,
		)
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - back_thick * 0.5, h.pos.y - back_arm, back_thick, back_arm * 2},
			rl.WHITE,
		)

		green := rl.Color{60, 220, 90, 255}
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - arm, h.pos.y - thick * 0.5, arm * 2, thick},
			green,
		)
		rl.DrawRectangleRec(
			rl.Rectangle{h.pos.x - thick * 0.5, h.pos.y - arm, thick, arm * 2},
			green,
		)
	}
}

// #endregion

// #region Mission II: Find Morgan's Hideout


Level2_Phase :: enum {
	Wave1_WG_Only,
	Between_1Cyclops,
	Between_1Cyc_2Sneaks,
	Wave2_WG_Sneaks,
	Between_4Sneaks,
	Between_4Sneaks_2,
	Between_4Sneaks_3,
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
	if enemies.level != 2 {
		return
	}

	if enemies.level2_waves_complete >= LEVEL2_WAVES_TO_VICTORY {
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
	case .Between_4Sneaks, .Between_4Sneaks_2, .Between_4Sneaks_3:
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
		return !any_weirdguy_alive(enemies)
	case .Between_4Sneaks, .Between_4Sneaks_2, .Between_4Sneaks_3:
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
		next = .Between_4Sneaks_2
	case .Between_4Sneaks_2:
		next = .Between_4Sneaks_3
	case .Between_4Sneaks_3:
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

// #endregion

// #region Mission IV: Flank the Enemy Space Station


Level4_Phase :: enum {
	Wave1_Grunts,
	Wave2_WG,
	Wave3_Grunts,
	Wave4_Pillars,
	Wave5_Pillars2,
}

reset_level4_pacing :: proc(enemies: ^Enemy_Pool) {
	enemies.level4_phase = .Wave1_Grunts
	enemies.level4_phase_started = false
	enemies.level4_waves_complete = 0
	enemies.fire_interval = LEVEL4_GRUNT_FIRE_INTERVAL
}

update_level4_pacing :: proc(
	enemies: ^Enemy_Pool,
	pillars: ^Pillar_Wave,
	dt: f32,
	block_next_wave: bool,
) {
	if enemies.level != 4 {
		return
	}

	// Wave4_Pillars self-loops in advance_phase_l4 (resets phase_started),
	// so without this gate the pillars would re-spawn during VICTORY_DELAY
	// and flash on screen before clear_world fires.
	if enemies.level4_waves_complete >= LEVEL4_WAVES_TO_VICTORY {
		return
	}

	// block_next_wave defers on_enter while a between-phase dialogue (l402) is
	// up, so the pillars don't pop in under the box.
	if !enemies.level4_phase_started && !block_next_wave {
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
		spawn_pillar_wave(pillars, 1)
	case .Wave5_Pillars2:
		spawn_pillar_wave(pillars, 2)
	}
}

@(private = "file")
phase_complete_l4 :: proc(enemies: ^Enemy_Pool, pillars: ^Pillar_Wave) -> bool {
	switch enemies.level4_phase {
	case .Wave1_Grunts, .Wave3_Grunts:
		return !any_grunt_alive(enemies)
	case .Wave2_WG:
		return !any_weirdguy_alive(enemies)
	case .Wave4_Pillars, .Wave5_Pillars2:
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
		next = .Wave5_Pillars2
	case .Wave5_Pillars2:
		next = .Wave5_Pillars2
	}
	enemies.level4_phase = next
	enemies.level4_phase_started = false
	enemies.level4_waves_complete += 1
}

// #endregion

// #region Pausing and Menus


Main_Menu_Screen :: enum {
	Main,
	Options,
	Controls,
}

Main_Menu :: struct {
	screen: Main_Menu_Screen,
	cursor: int,
}

reset_main_menu :: proc(mm: ^Main_Menu) {
	mm.screen = .Main
	mm.cursor = 0
}

update_main_menu :: proc(
	mm: ^Main_Menu,
	begin_game: ^bool,
	quit_app: ^bool,
	audio: ^Audio,
) {
	switch mm.screen {
	case .Main:
		item_count := 4
		step := input_menu_step_y()
		if step != 0 {
			mm.cursor = (mm.cursor + step + item_count) % item_count
		}
		if input_confirm_pressed() {
			switch mm.cursor {
			case 0:
				begin_game^ = true
			case 1:
				mm.screen = .Options
				mm.cursor = 0
			case 2:
				mm.screen = .Controls
				mm.cursor = 0
			case 3:
				when ODIN_OS != .JS {
					quit_app^ = true
				}
			}
		}

	case .Options:
		if input_menu_back_pressed() {
			mm.screen = .Main
			mm.cursor = 1
			return
		}
		item_count := 3
		step := input_menu_step_y()
		if step != 0 {
			mm.cursor = (mm.cursor + step + item_count) % item_count
		}
		h := input_menu_step_x()
		if h != 0 {
			switch mm.cursor {
			case 0:
				set_music_volume(audio, audio.music_volume + f32(h) * PAUSE_VOLUME_STEP)
			case 1:
				set_sfx_volume(audio, audio.sfx_volume + f32(h) * PAUSE_VOLUME_STEP)
			}
		}
		if input_confirm_pressed() && mm.cursor == 2 {
			mm.screen = .Main
			mm.cursor = 1
		}

	case .Controls:
		if input_menu_back_pressed() || input_confirm_pressed() {
			mm.screen = .Main
			mm.cursor = 2
		}
	}
}

draw_main_menu :: proc(mm: ^Main_Menu, audio: ^Audio) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, MAIN_MENU_OVERLAY_ALPHA})

	title := cstring("Zombi")
	tw := rl.MeasureText(title, MAIN_MENU_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	rl.DrawText(title, tx + 3, MAIN_MENU_TITLE_Y + 3, MAIN_MENU_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, tx, MAIN_MENU_TITLE_Y, MAIN_MENU_TITLE_FONT_SIZE, rl.WHITE)

	switch mm.screen {
	case .Main:
		draw_main_menu_items(mm.cursor)
	case .Options:
		draw_pause_options(mm.cursor, audio, nil)
	case .Controls:
		draw_pause_controls()
	}
}

@(private = "file")
draw_main_menu_items :: proc(cursor: int) {
	items := [?]cstring {
		cstring("BEGIN"),
		cstring("OPTIONS"),
		cstring("CONTROLS"),
		cstring("QUIT"),
	}
	y: i32 = MAIN_MENU_ITEMS_TOP_Y
	for it, i in items {
		draw_menu_label(it, y, cursor == i)
		y += PAUSE_ITEM_FONT_SIZE + PAUSE_ITEM_GAP
	}
}
Pause_Screen :: enum {
	Main,
	Options,
	Controls,
}

Pause_Menu :: struct {
	screen: Pause_Screen,
	cursor: int,
}

reset_pause_menu :: proc(pm: ^Pause_Menu) {
	pm.screen = .Main
	pm.cursor = 0
}

update_pause :: proc(pm: ^Pause_Menu, paused: ^bool, quit_to_menu: ^bool, audio: ^Audio, show_timer: ^bool) {
	switch pm.screen {
	case .Main:
		if input_pause_toggle_pressed() {
			paused^ = false
			return
		}
		item_count := 4
		step := input_menu_step_y()
		if step != 0 {
			pm.cursor = (pm.cursor + step + item_count) % item_count
		}
		if input_confirm_pressed() {
			switch pm.cursor {
			case 0:
				paused^ = false
			case 1:
				pm.screen = .Options
				pm.cursor = 0
			case 2:
				pm.screen = .Controls
				pm.cursor = 0
			case 3:
				quit_to_menu^ = true
				paused^ = false
			}
		}

	case .Options:
		if input_menu_back_pressed() {
			pm.screen = .Main
			pm.cursor = 1
			return
		}
		item_count := 4
		step := input_menu_step_y()
		if step != 0 {
			pm.cursor = (pm.cursor + step + item_count) % item_count
		}
		h := input_menu_step_x()
		if h != 0 {
			switch pm.cursor {
			case 0:
				set_music_volume(audio, audio.music_volume + f32(h) * PAUSE_VOLUME_STEP)
			case 1:
				set_sfx_volume(audio, audio.sfx_volume + f32(h) * PAUSE_VOLUME_STEP)
			case 2:
				show_timer^ = !show_timer^
			}
		}
		if input_confirm_pressed() {
			switch pm.cursor {
			case 2:
				show_timer^ = !show_timer^
			case 3:
				pm.screen = .Main
				pm.cursor = 1
			}
		}

	case .Controls:
		if input_menu_back_pressed() || input_confirm_pressed() {
			pm.screen = .Main
			pm.cursor = 2
		}
	}
}

draw_pause :: proc(pm: ^Pause_Menu, audio: ^Audio, show_timer: ^bool) {
	rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, rl.Color{0, 0, 0, PAUSE_OVERLAY_ALPHA})

	title := cstring("PAUSED")
	tw := rl.MeasureText(title, PAUSE_TITLE_FONT_SIZE)
	tx := (i32(SCREEN_WIDTH) - tw) / 2
	rl.DrawText(title, tx + 2, PAUSE_TITLE_Y + 2, PAUSE_TITLE_FONT_SIZE, rl.BLACK)
	rl.DrawText(title, tx, PAUSE_TITLE_Y, PAUSE_TITLE_FONT_SIZE, rl.WHITE)

	switch pm.screen {
	case .Main:
		draw_pause_main(pm.cursor)
	case .Options:
		draw_pause_options(pm.cursor, audio, show_timer)
	case .Controls:
		draw_pause_controls()
	}
}

@(private = "file")
draw_pause_main :: proc(cursor: int) {
	items := [?]cstring{cstring("RESUME"), cstring("OPTIONS"), cstring("CONTROLS"), cstring("QUIT")}
	y: i32 = PAUSE_MENU_TOP_Y
	for it, i in items {
		draw_menu_label(it, y, cursor == i)
		y += PAUSE_ITEM_FONT_SIZE + PAUSE_ITEM_GAP
	}
}

draw_pause_options :: proc(cursor: int, audio: ^Audio, show_timer: ^bool) {
	row_h: i32 = PAUSE_ITEM_FONT_SIZE + PAUSE_SLIDER_H + 10
	y: i32 = PAUSE_MENU_TOP_Y
	draw_menu_slider(cstring("MUSIC"), audio.music_volume, y, cursor == 0)
	y += row_h + PAUSE_ITEM_GAP
	draw_menu_slider(cstring("SFX"), audio.sfx_volume, y, cursor == 1)
	y += row_h + PAUSE_ITEM_GAP
	if show_timer != nil {
		draw_menu_toggle(cstring("SHOW TIMER"), show_timer^, y, cursor == 2)
		y += PAUSE_ITEM_FONT_SIZE + PAUSE_ITEM_GAP
		draw_menu_label(cstring("BACK"), y, cursor == 3)
	} else {
		draw_menu_label(cstring("BACK"), y, cursor == 2)
	}
}

draw_menu_toggle :: proc(label: cstring, value: bool, y: i32, selected: bool) {
	color := rl.Color{180, 180, 180, 255}
	if selected {
		color = rl.WHITE
	}
	state: cstring = "OFF"
	if value {
		state = "ON"
	}
	label_w := rl.MeasureText(label, PAUSE_ITEM_FONT_SIZE)
	state_w := rl.MeasureText(state, PAUSE_ITEM_FONT_SIZE)
	spacing: i32 = 16
	total_w := label_w + spacing + state_w
	label_x := (i32(SCREEN_WIDTH) - total_w) / 2
	state_x := label_x + label_w + spacing
	rl.DrawText(label, label_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(label, label_x, y, PAUSE_ITEM_FONT_SIZE, color)
	state_color := color
	if value && selected {
		state_color = rl.Color{80, 180, 255, 255}
	} else if value {
		state_color = rl.Color{120, 160, 200, 255}
	}
	rl.DrawText(state, state_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(state, state_x, y, PAUSE_ITEM_FONT_SIZE, state_color)
	if selected {
		rl.DrawText(cstring(">"), label_x - 14, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
		rl.DrawText(cstring("<"), state_x + state_w + 6, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
	}
}

draw_pause_controls :: proc() {
	on_gamepad := input_last_device() == .Gamepad

	header: cstring = cstring("CONTROLS - KEYBOARD")
	if on_gamepad {
		header = cstring("CONTROLS - GAMEPAD")
	}
	hw := rl.MeasureText(header, PAUSE_ITEM_FONT_SIZE)
	hx := (i32(SCREEN_WIDTH) - hw) / 2
	hy: i32 = PAUSE_MENU_TOP_Y - 30
	rl.DrawText(header, hx + 1, hy + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(header, hx, hy, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)

	y := hy + PAUSE_ITEM_FONT_SIZE + 10
	draw_control_row(cstring("MOVE"), .Move, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("ATTACK"), .Attack, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("DASH"), .Dash, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("SHRINK TIME"), .Slow_Time, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("SHRINK BOMB"), .Shrink_Bomb, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("PAUSE"), .Pause, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("CONFIRM"), .Confirm, y)
	y += PAUSE_BODY_LINE_GAP
	draw_control_row(cstring("REROLL"), .Reroll, y)
	y += PAUSE_BODY_LINE_GAP

	draw_return_hint()
}

draw_return_hint :: proc() {
	tail := cstring("RETURN")
	icon_w := input_hint_width(.Confirm, HINT_ICON_SIZE)
	tail_w := rl.MeasureText(tail, PAUSE_BODY_FONT_SIZE)
	total_w := icon_w + HINT_TEXT_GAP + tail_w
	x := (i32(SCREEN_WIDTH) - total_w) / 2
	y: i32 = SCREEN_HEIGHT - 22
	icon_y := y + (PAUSE_BODY_FONT_SIZE - HINT_ICON_SIZE) / 2
	draw_input_hint(.Back, x, icon_y, HINT_ICON_SIZE)
	rl.DrawText(tail, x + icon_w + HINT_TEXT_GAP, y, PAUSE_BODY_FONT_SIZE, rl.WHITE)
}

// Body rows are taller than the font now so icons fit; the label sits centered
// vertically inside the row's icon-height band.
draw_control_row :: proc(label: cstring, kind: Input_Hint, y: i32) {
	label_x: i32 = SCREEN_WIDTH / 2 - 110
	icon_x: i32 = SCREEN_WIDTH / 2 + 10
	label_y := y + (HINT_ICON_SIZE - PAUSE_BODY_FONT_SIZE) / 2
	rl.DrawText(label, label_x, label_y, PAUSE_BODY_FONT_SIZE, rl.WHITE)
	draw_input_hint(kind, icon_x, y, HINT_ICON_SIZE)
}

draw_menu_label :: proc(text: cstring, y: i32, selected: bool) {
	color := rl.Color{180, 180, 180, 255}
	if selected {
		color = rl.WHITE
	}
	w := rl.MeasureText(text, PAUSE_ITEM_FONT_SIZE)
	x := (i32(SCREEN_WIDTH) - w) / 2
	rl.DrawText(text, x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(text, x, y, PAUSE_ITEM_FONT_SIZE, color)
	if selected {
		rl.DrawText(cstring(">"), x - 14, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
		rl.DrawText(cstring("<"), x + w + 6, y, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
	}
}

draw_menu_slider :: proc(label: cstring, value: f32, y: i32, selected: bool) {
	color := rl.Color{180, 180, 180, 255}
	if selected {
		color = rl.WHITE
	}
	pct := fmt.ctprintf("%d%%", int(value * 100 + 0.5))
	label_w := rl.MeasureText(label, PAUSE_ITEM_FONT_SIZE)
	pct_w := rl.MeasureText(pct, PAUSE_ITEM_FONT_SIZE)
	spacing: i32 = 16
	total_w := label_w + spacing + pct_w
	label_x := (i32(SCREEN_WIDTH) - total_w) / 2
	pct_x := label_x + label_w + spacing
	rl.DrawText(label, label_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(label, label_x, y, PAUSE_ITEM_FONT_SIZE, color)
	rl.DrawText(pct, pct_x + 1, y + 1, PAUSE_ITEM_FONT_SIZE, rl.BLACK)
	rl.DrawText(pct, pct_x, y, PAUSE_ITEM_FONT_SIZE, color)

	bar_w: i32 = PAUSE_SLIDER_W
	bar_h: i32 = PAUSE_SLIDER_H
	bar_x := (i32(SCREEN_WIDTH) - bar_w) / 2
	bar_y := y + PAUSE_ITEM_FONT_SIZE + 4
	rl.DrawRectangle(bar_x, bar_y, bar_w, bar_h, rl.Color{40, 40, 60, 255})
	fill_w := i32(f32(bar_w) * value + 0.5)
	fill_color := rl.Color{120, 120, 160, 255}
	if selected {
		fill_color = rl.Color{80, 180, 255, 255}
	}
	rl.DrawRectangle(bar_x, bar_y, fill_w, bar_h, fill_color)
	rl.DrawRectangleLines(bar_x, bar_y, bar_w, bar_h, rl.Color{120, 120, 140, 255})
	if selected {
		rl.DrawText(cstring("<"), bar_x - 14, bar_y - 4, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
		rl.DrawText(cstring(">"), bar_x + bar_w + 6, bar_y - 4, PAUSE_ITEM_FONT_SIZE, rl.YELLOW)
	}
}

// #endregion

// #region Particle Handling
Particle :: struct {
	pos:      rl.Vector2,
	vel:      rl.Vector2,
	lifetime: f32,
	max_life: f32,
	color:    rl.Color,
	size:     f32,
	active:   bool,
}

Particle_Pool :: struct {
	particles: [MAX_PARTICLES]Particle,
}

spawn_impact_particles :: proc(pool: ^Particle_Pool, pos: rl.Vector2, color: rl.Color, count: int) {
	spawned := 0
	for i in 0 ..< MAX_PARTICLES {
		if spawned >= count {
			return
		}
		p := &pool.particles[i]
		if p.active {
			continue
		}
		angle := rand.float32() * math.TAU
		speed_range: f32 = PARTICLE_SPEED_MAX - PARTICLE_SPEED_MIN
		speed := f32(PARTICLE_SPEED_MIN) + rand.float32() * speed_range
		life_range: f32 = PARTICLE_LIFE_MAX - PARTICLE_LIFE_MIN
		size_range: f32 = PARTICLE_SIZE_MAX - PARTICLE_SIZE_MIN
		tinted := color
		tinted.a = 200
		p^ = Particle {
			pos      = pos,
			vel      = {math.cos(angle) * speed, math.sin(angle) * speed - 50},
			lifetime = 0,
			max_life = f32(PARTICLE_LIFE_MIN) + rand.float32() * life_range,
			color    = tinted,
			size     = f32(PARTICLE_SIZE_MIN) + rand.float32() * size_range,
			active   = true,
		}
		spawned += 1
	}
}

spawn_gather_particle :: proc(pool: ^Particle_Pool, target: rl.Vector2, color: rl.Color, charge: f32) {
	for i in 0 ..< MAX_PARTICLES {
		p := &pool.particles[i]
		if p.active {
			continue
		}
		angle := rand.float32() * math.TAU
		dist := f32(CHARGE_BEAM_GATHER_DIST_MIN) + rand.float32() * f32(CHARGE_BEAM_GATHER_DIST_RANGE)
		spawn_pos := rl.Vector2{target.x + math.cos(angle) * dist, target.y + math.sin(angle) * dist}
		tinted := color
		tinted.a = 200
		p^ = Particle {
			pos      = spawn_pos,
			vel      = (target - spawn_pos) * 3,
			lifetime = 0,
			max_life = CHARGE_BEAM_GATHER_LIFE,
			color    = tinted,
			size     = 2 + charge * 3,
			active   = true,
		}
		return
	}
}

update_particles :: proc(pool: ^Particle_Pool, dt: f32) {
	for i in 0 ..< MAX_PARTICLES {
		p := &pool.particles[i]
		if !p.active {
			continue
		}
		p.pos += p.vel * dt
		p.vel.y += PARTICLE_GRAVITY * dt
		p.lifetime += dt
		if p.lifetime >= p.max_life {
			p.active = false
		}
	}
}

draw_particles :: proc(pool: ^Particle_Pool) {
	for i in 0 ..< MAX_PARTICLES {
		p := &pool.particles[i]
		if !p.active {
			continue
		}
		alpha := 1.0 - (p.lifetime / p.max_life)
		color := p.color
		color.a = u8(f32(p.color.a) * alpha)
		rl.DrawCircleV(p.pos, p.size * alpha, color)
	}
}

// #endregion

// #region Dialogue



Dialogue_Speaker :: enum {
	Paprika,
	Zombi,
}

Dialogue_Line :: struct {
	speaker: Dialogue_Speaker,
	text:    string,
}

Dialogue_Source_Line :: struct {
	speaker: string,
	text:    string,
}

Dialogue_Source_Scene :: struct {
	scene_id: string,
	lines:    []Dialogue_Source_Line,
}

Dialogue_Source :: struct {
	scenes: []Dialogue_Source_Scene,
}

// Each entry maps to one JSON file under assets/dialogue/. Scene IDs are unique
// across all files, so find_scene walks every loaded source.
Dialogue_File :: enum {
	Level1_Hints,
	Level2,
	Level4_Scene1,
	Level4_Scene2,
	Level5,
}

DIALOGUE_FILE_PATHS := [Dialogue_File]string {
	.Level1_Hints  = "assets/dialogue/scenes_level1/hints.json",
	.Level2        = "assets/dialogue/scenes_level2/scene.json",
	.Level4_Scene1 = "assets/dialogue/scenes_level4/scene1.json",
	.Level4_Scene2 = "assets/dialogue/scenes_level4/scene2.json",
	.Level5        = "assets/dialogue/scenes_level5/scene.json",
}

Dialogue :: struct {
	active:                 bool,
	pauses_game:            bool,
	intro_done:             bool,
	wave2_intro_done:       bool,
	boss_intro_done:        bool,
	l2_intro_done:          bool,
	l4_intro_done:          bool,
	l4_pillars_intro_done:  bool,
	l5_guardian_intro_done: bool,
	lines:                  [8]Dialogue_Line,
	line_count:             int,
	line_idx:               int,
	atoms_revealed:         int,
	char_timer:             f32,
	icon_frame:             int,
	icon_frame_t:           f32,
	paprika_tex:            rl.Texture2D,
	zombi_tex:              rl.Texture2D,
	sources:                [Dialogue_File]Dialogue_Source,
	raws:                   [Dialogue_File][]byte,
}

init_dialogue :: proc(d: ^Dialogue) {
	d.paprika_tex = rl.LoadTexture("assets/sprites/captain_paprika_dialogue_box_icon.png")
	d.zombi_tex = rl.LoadTexture("assets/sprites/player_dialogue_box_icon.png")
	rl.SetTextureFilter(d.paprika_tex, .POINT)
	rl.SetTextureFilter(d.zombi_tex, .POINT)

	for f in Dialogue_File {
		load_dialogue_source(&d.sources[f], &d.raws[f], DIALOGUE_FILE_PATHS[f])
	}
}

unload_dialogue :: proc(d: ^Dialogue) {
	rl.UnloadTexture(d.paprika_tex)
	rl.UnloadTexture(d.zombi_tex)
	for f in Dialogue_File {
		if d.raws[f] != nil {
			delete(d.raws[f])
			d.raws[f] = nil
		}
	}
}

@(private = "file")
load_dialogue_source :: proc(out: ^Dialogue_Source, raw_out: ^[]byte, path: string) {
	data, ok := read_entire_file(path, context.allocator)
	if !ok {
		log.errorf("dialogue: failed to read %v", path)
		return
	}
	raw_out^ = data
	if err := json.unmarshal(data, out); err != nil {
		log.errorf("dialogue: failed to parse %v: %v", path, err)
	}
}

@(private = "file")
find_scene :: proc(d: ^Dialogue, scene_id: string) -> (^Dialogue_Source_Scene, bool) {
	for f in Dialogue_File {
		src := &d.sources[f]
		for i in 0 ..< len(src.scenes) {
			if src.scenes[i].scene_id == scene_id {
				return &src.scenes[i], true
			}
		}
	}
	return nil, false
}

@(private = "file")
parse_speaker :: proc(s: string) -> (Dialogue_Speaker, bool) {
	switch s {
	case "captain_paprika":
		return .Paprika, true
	case "player_zombi":
		return .Zombi, true
	}
	return .Paprika, false
}

// Pause-vs-overlay is decided by the caller, not the JSON. Level intros (where
// the player just landed) pause; between-wave and during-boss scenes overlay.
@(private = "file")
start_scene :: proc(d: ^Dialogue, scene_id: string, pauses_game: bool) -> bool {
	scene, ok := find_scene(d, scene_id)
	if !ok {
		log.errorf("dialogue: scene %v not found", scene_id)
		return false
	}
	n := 0
	for src_line in scene.lines {
		if n >= len(d.lines) {
			log.warnf("dialogue: scene %v has more lines than buffer (%d)", scene_id, len(d.lines))
			break
		}
		spk, sok := parse_speaker(src_line.speaker)
		if !sok {
			log.warnf("dialogue: unknown speaker %q in scene %v", src_line.speaker, scene_id)
		}
		d.lines[n] = Dialogue_Line {
			speaker = spk,
			text    = src_line.text,
		}
		n += 1
	}
	if n == 0 {
		return false
	}
	d.line_count = n
	d.pauses_game = pauses_game
	dialogue_begin(d)
	return true
}

start_level1_intro :: proc(d: ^Dialogue) {
	if d.intro_done {
		return
	}
	if start_scene(d, "hint_01", true) {
		d.intro_done = true
	}
}

start_level1_wave2_intro :: proc(d: ^Dialogue) {
	if d.wave2_intro_done {
		return
	}
	if start_scene(d, "hint_02", false) {
		d.wave2_intro_done = true
	}
}

start_level1_boss_intro :: proc(d: ^Dialogue) {
	if d.boss_intro_done {
		return
	}
	if start_scene(d, "hint_03", false) {
		d.boss_intro_done = true
	}
}

start_level2_intro :: proc(d: ^Dialogue) {
	if d.l2_intro_done {
		return
	}
	if start_scene(d, "l201", true) {
		d.l2_intro_done = true
	}
}

start_level4_intro :: proc(d: ^Dialogue) {
	if d.l4_intro_done {
		return
	}
	if start_scene(d, "l401", true) {
		d.l4_intro_done = true
	}
}

start_level4_pillars_intro :: proc(d: ^Dialogue) {
	if d.l4_pillars_intro_done {
		return
	}
	if start_scene(d, "l402", false) {
		d.l4_pillars_intro_done = true
	}
}

start_level5_guardian_intro :: proc(d: ^Dialogue) {
	if d.l5_guardian_intro_done {
		return
	}
	if start_scene(d, "l501", false) {
		d.l5_guardian_intro_done = true
	}
}

@(private = "file")
dialogue_begin :: proc(d: ^Dialogue) {
	d.line_idx = 0
	d.atoms_revealed = 0
	d.char_timer = 0
	d.icon_frame = 0
	d.icon_frame_t = 0
	d.active = true
}

@(private = "file")
line_atom_count :: proc(text: string) -> int {
	n := 0
	i := 0
	for i < len(text) {
		if text[i] == '{' {
			rel := strings.index_byte(text[i:], '}')
			if rel >= 0 {
				i += rel + 1
				n += 1
				continue
			}
		}
		n += 1
		i += 1
	}
	return n
}

update_dialogue :: proc(d: ^Dialogue, dt: f32) {
	if !d.active {
		return
	}
	if d.line_idx >= d.line_count {
		d.active = false
		return
	}

	d.icon_frame_t += dt
	for d.icon_frame_t >= DIALOGUE_ICON_FRAME_DUR {
		d.icon_frame_t -= DIALOGUE_ICON_FRAME_DUR
		d.icon_frame = (d.icon_frame + 1) % DIALOGUE_ICON_SRC_FRAMES
	}

	line := d.lines[d.line_idx]
	total := line_atom_count(line.text)

	if input_confirm_pressed() {
		if d.atoms_revealed < total {
			d.atoms_revealed = total
			return
		}
		d.line_idx += 1
		d.atoms_revealed = 0
		d.char_timer = 0
		if d.line_idx >= d.line_count {
			d.active = false
		}
		return
	}

	if d.atoms_revealed < total {
		d.char_timer += dt
		for d.char_timer >= DIALOGUE_CHAR_INTERVAL && d.atoms_revealed < total {
			d.char_timer -= DIALOGUE_CHAR_INTERVAL
			d.atoms_revealed += 1
		}
	}
}

draw_dialogue :: proc(d: ^Dialogue) {
	if !d.active || d.line_idx >= d.line_count {
		return
	}

	box_x: i32 = (SCREEN_WIDTH - DIALOGUE_BOX_W) / 2
	box_y: i32 = SCREEN_HEIGHT - DIALOGUE_BOX_H - DIALOGUE_BOX_BOTTOM_MARGIN

	rl.DrawRectangle(box_x, box_y, DIALOGUE_BOX_W, DIALOGUE_BOX_H, rl.Color{8, 8, 14, 252})
	rl.DrawRectangleLines(box_x, box_y, DIALOGUE_BOX_W, DIALOGUE_BOX_H, rl.Color{200, 200, 220, 255})

	line := d.lines[d.line_idx]

	tex: rl.Texture2D
	name: cstring
	accent: rl.Color
	switch line.speaker {
	case .Paprika:
		tex = d.paprika_tex
		name = "CAPTAIN PAPRIKA"
		accent = rl.Color{255, 140, 80, 255}
	case .Zombi:
		tex = d.zombi_tex
		name = "ZOMBI"
		accent = rl.Color{120, 220, 160, 255}
	}

	icon_x: f32 = f32(box_x + DIALOGUE_BOX_PAD)
	icon_y: f32 =
		f32(box_y) + (f32(DIALOGUE_BOX_H) - f32(DIALOGUE_ICON_DRAW_SIZE)) * 0.5
	src := rl.Rectangle {
		f32(d.icon_frame * DIALOGUE_ICON_SRC_W),
		0,
		f32(DIALOGUE_ICON_SRC_W),
		f32(DIALOGUE_ICON_SRC_H),
	}
	dst := rl.Rectangle {
		icon_x,
		icon_y,
		f32(DIALOGUE_ICON_DRAW_SIZE),
		f32(DIALOGUE_ICON_DRAW_SIZE),
	}
	rl.DrawTexturePro(tex, src, dst, {0, 0}, 0, rl.WHITE)

	nx: i32 = box_x + DIALOGUE_BOX_PAD
	ny: i32 = box_y - DIALOGUE_NAME_FONT_SIZE - 3
	rl.DrawText(name, nx + 1, ny + 1, DIALOGUE_NAME_FONT_SIZE, rl.BLACK)
	rl.DrawText(name, nx, ny, DIALOGUE_NAME_FONT_SIZE, accent)

	text_x0: i32 =
		box_x + DIALOGUE_BOX_PAD + DIALOGUE_ICON_DRAW_SIZE + DIALOGUE_BOX_PAD
	text_y0: i32 = box_y + DIALOGUE_BOX_PAD
	text_w: i32 = DIALOGUE_BOX_W - (text_x0 - box_x) - DIALOGUE_BOX_PAD
	line_h: i32 = DIALOGUE_TEXT_FONT_SIZE + DIALOGUE_TEXT_LINE_GAP

	draw_dialogue_text(line.text, d.atoms_revealed, text_x0, text_y0, text_w, line_h)

	if d.atoms_revealed >= line_atom_count(line.text) {
		draw_dialogue_confirm_prompt(box_x, box_y)
	}
}

@(private = "file")
draw_dialogue_confirm_prompt :: proc(box_x, box_y: i32) {
	if int(rl.GetTime() * 2) % 2 != 0 {
		return
	}
	font_size: i32 = DIALOGUE_TEXT_FONT_SIZE
	icon_size: i32 = DIALOGUE_INLINE_HINT_SIZE
	prompt: cstring = "Press"
	prompt_w := rl.MeasureText(prompt, font_size)
	icon_w := input_hint_width(.Confirm, icon_size)
	gap: i32 = 4
	total_w := prompt_w + gap + icon_w
	px := box_x + DIALOGUE_BOX_W - DIALOGUE_BOX_PAD - total_w
	py := box_y + DIALOGUE_BOX_H - DIALOGUE_BOX_PAD - font_size
	rl.DrawText(prompt, px + 1, py + 1, font_size, rl.BLACK)
	rl.DrawText(prompt, px, py, font_size, rl.WHITE)
	icon_y := py + (font_size - icon_size) / 2
	_ = draw_input_hint(.Confirm, px + prompt_w + gap, icon_y, icon_size)
}

@(private = "file")
token_to_hint :: proc(token: string) -> (Input_Hint, bool) {
	switch token {
	case "attack":
		return .Attack, true
	case "dash":
		return .Dash, true
	case "shrink":
		return .Shrink_Bomb, true
	case "slow":
		return .Slow_Time, true
	case "confirm":
		return .Confirm, true
	}
	return .Attack, false
}

@(private = "file")
draw_dialogue_text :: proc(text: string, atoms_revealed: int, x0, y0, w, line_h: i32) {
	font_size: i32 = DIALOGUE_TEXT_FONT_SIZE
	cur_x := x0
	cur_y := y0
	drawn := 0
	space_w := rl.MeasureText(" ", font_size)

	// Draw a plain-text chunk with drop shadow, advancing cur_x.
	draw_chunk :: proc(s: string, x, y, font_size: i32) -> i32 {
		cstr := strings.clone_to_cstring(s, context.temp_allocator)
		rl.DrawText(cstr, x + 1, y + 1, font_size, rl.BLACK)
		rl.DrawText(cstr, x, y, font_size, rl.WHITE)
		return rl.MeasureText(cstr, font_size)
	}

	i := 0
	for i < len(text) && drawn < atoms_revealed {
		ch := text[i]

		if ch == '{' {
			rel_close := strings.index_byte(text[i:], '}')
			if rel_close >= 0 {
				token := text[i + 1:i + rel_close]
				if hint, ok := token_to_hint(token); ok {
					token_w := input_hint_width(hint, DIALOGUE_INLINE_HINT_SIZE)
					if cur_x + token_w > x0 + w {
						cur_x = x0
						cur_y += line_h
					}
					icon_y := cur_y + (font_size - DIALOGUE_INLINE_HINT_SIZE) / 2
					_ = draw_input_hint(hint, cur_x, icon_y, DIALOGUE_INLINE_HINT_SIZE)
					cur_x += token_w
					i += rel_close + 1
					drawn += 1
					continue
				}
			}
		}
		if ch == ' ' {
			j := i + 1
			for j < len(text) && text[j] != ' ' && text[j] != '{' {
				j += 1
			}
			cword := strings.clone_to_cstring(text[i + 1:j], context.temp_allocator)
			word_w := rl.MeasureText(cword, font_size)
			if cur_x + space_w + word_w > x0 + w {
				cur_x = x0
				cur_y += line_h
				drawn += 1
				i += 1
				continue
			}
		}

		j := i
		if text[j] == ' ' {
			j += 1
		}
		for j < len(text) && text[j] != ' ' && text[j] != '{' {
			j += 1
		}
		end := j
		if drawn + (end - i) > atoms_revealed {
			end = i + (atoms_revealed - drawn)
		}
		chunk := text[i:end]
		cur_x += draw_chunk(chunk, cur_x, cur_y, font_size)
		drawn += len(chunk)
		i = end
	}
}

// #endregion
