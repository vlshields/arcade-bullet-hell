package game

import rl "vendor:raylib"

Audio :: struct {
	music_volume:             f32,
	sfx_volume:               f32,
	// theme2 loops during gameplay; theme1 takes over while a victory screen is
	// up and yields back to theme2 on advance_to_next_mission. on_victory tracks
	// which stream update_audio should advance.
	theme1:                   rl.Music,
	theme2:                   rl.Music,
	on_victory:               bool,
	sfx_charged_beam:         rl.Sound,
	sfx_charging_beam:        rl.Sound,
	sfx_dash:                 rl.Sound,
	sfx_golgotha_bullet_hell: rl.Sound,
	sfx_laser:                rl.Sound,
	sfx_rapid_fire:           rl.Sound,
	sfx_reflects_bullet:      rl.Sound,
	sfx_shrink_bullets:       rl.Sound,
	sfx_takes_damage:         rl.Sound,
}

init_audio :: proc(a: ^Audio) {
	rl.InitAudioDevice()
	a.music_volume = MUSIC_VOLUME
	a.sfx_volume = SFX_VOLUME

	a.theme1 = rl.LoadMusicStream("assets/audio/soundtrack/themesong1.ogg")
	a.theme1.looping = true
	a.theme2 = rl.LoadMusicStream("assets/audio/soundtrack/themesong2.ogg")
	a.theme2.looping = true
	rl.SetMusicVolume(a.theme1, a.music_volume)
	rl.SetMusicVolume(a.theme2, a.music_volume)
	rl.PlayMusicStream(a.theme2)

	a.sfx_charged_beam = rl.LoadSound("assets/audio/sfx/player_charged_beam.wav")
	a.sfx_charging_beam = rl.LoadSound("assets/audio/sfx/player_charging_beam.wav")
	a.sfx_dash = rl.LoadSound("assets/audio/sfx/player_dash.wav")
	a.sfx_golgotha_bullet_hell = rl.LoadSound("assets/audio/golgotha_bullet_hell.wav")
	a.sfx_laser = rl.LoadSound("assets/audio/sfx/player_laser.wav")
	a.sfx_rapid_fire = rl.LoadSound("assets/audio/sfx/player_rapid_fire.wav")
	a.sfx_reflects_bullet = rl.LoadSound("assets/audio/sfx/player_reflects_bullet.wav")
	a.sfx_shrink_bullets = rl.LoadSound("assets/audio/sfx/player_shrink_bullets.wav")
	a.sfx_takes_damage = rl.LoadSound("assets/audio/sfx/player_takes_damage.wav")

	apply_sfx_volume(a)
}

update_audio :: proc(a: ^Audio) {
	if a.on_victory {
		rl.UpdateMusicStream(a.theme1)
	} else {
		rl.UpdateMusicStream(a.theme2)
	}
}

// Swap to the victory loop. Idempotent: safe to call every frame the victory
// screen is up.
play_victory_music :: proc(a: ^Audio) {
	if a.on_victory {
		return
	}
	rl.StopMusicStream(a.theme2)
	rl.PlayMusicStream(a.theme1)
	a.on_victory = true
}

// Swap back to the gameplay loop. Idempotent.
play_gameplay_music :: proc(a: ^Audio) {
	if !a.on_victory {
		return
	}
	rl.StopMusicStream(a.theme1)
	rl.PlayMusicStream(a.theme2)
	a.on_victory = false
}

unload_audio :: proc(a: ^Audio) {
	rl.StopMusicStream(a.theme1)
	rl.StopMusicStream(a.theme2)
	rl.UnloadMusicStream(a.theme1)
	rl.UnloadMusicStream(a.theme2)
	rl.UnloadSound(a.sfx_charged_beam)
	rl.UnloadSound(a.sfx_charging_beam)
	rl.UnloadSound(a.sfx_dash)
	rl.UnloadSound(a.sfx_golgotha_bullet_hell)
	rl.UnloadSound(a.sfx_laser)
	rl.UnloadSound(a.sfx_rapid_fire)
	rl.UnloadSound(a.sfx_reflects_bullet)
	rl.UnloadSound(a.sfx_shrink_bullets)
	rl.UnloadSound(a.sfx_takes_damage)
	rl.CloseAudioDevice()
}

set_music_volume :: proc(a: ^Audio, v: f32) {
	a.music_volume = clamp(v, 0.0, 1.0)
	rl.SetMusicVolume(a.theme1, a.music_volume)
	rl.SetMusicVolume(a.theme2, a.music_volume)
}

set_sfx_volume :: proc(a: ^Audio, v: f32) {
	a.sfx_volume = clamp(v, 0.0, 1.0)
	apply_sfx_volume(a)
}

@(private = "file")
apply_sfx_volume :: proc(a: ^Audio) {
	rl.SetSoundVolume(a.sfx_charged_beam, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_charging_beam, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_dash, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_golgotha_bullet_hell, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_laser, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_rapid_fire, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_reflects_bullet, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_shrink_bullets, a.sfx_volume)
	rl.SetSoundVolume(a.sfx_takes_damage, a.sfx_volume)
}

play_dash_sfx :: proc(a: ^Audio)          {rl.PlaySound(a.sfx_dash)}
play_laser_sfx :: proc(a: ^Audio)         {rl.PlaySound(a.sfx_laser)}
play_charged_beam_sfx :: proc(a: ^Audio)  {rl.PlaySound(a.sfx_charged_beam)}
play_reflect_sfx :: proc(a: ^Audio)       {rl.PlaySound(a.sfx_reflects_bullet)}
play_shrink_bomb_sfx :: proc(a: ^Audio)   {rl.PlaySound(a.sfx_shrink_bullets)}
play_player_damage_sfx :: proc(a: ^Audio) {rl.PlaySound(a.sfx_takes_damage)}

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
