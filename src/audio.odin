package game

import rl "vendor:raylib"

Audio :: struct {
	music_volume:        f32,
	sfx_volume:          f32,
	theme:               rl.Music,
	sfx_charged_beam:    rl.Sound,
	sfx_charging_beam:   rl.Sound,
	sfx_dash:            rl.Sound,
	sfx_laser:           rl.Sound,
	sfx_reflects_bullet: rl.Sound,
	sfx_shrink_bullets:  rl.Sound,
	sfx_takes_damage:    rl.Sound,
}

init_audio :: proc(a: ^Audio) {
	rl.InitAudioDevice()
	a.music_volume = MUSIC_VOLUME
	a.sfx_volume = SFX_VOLUME

	a.theme = rl.LoadMusicStream("assets/audio/soundtrack/themesong1.ogg")
	a.theme.looping = true
	rl.SetMusicVolume(a.theme, a.music_volume)
	rl.PlayMusicStream(a.theme)

	a.sfx_charged_beam = rl.LoadSound("assets/audio/sfx/player_charged_beam.wav")
	a.sfx_charging_beam = rl.LoadSound("assets/audio/sfx/player_charging_beam.wav")
	a.sfx_dash = rl.LoadSound("assets/audio/sfx/player_dash.wav")
	a.sfx_laser = rl.LoadSound("assets/audio/sfx/player_laser.wav")
	a.sfx_reflects_bullet = rl.LoadSound("assets/audio/sfx/player_reflects_bullet.wav")
	a.sfx_shrink_bullets = rl.LoadSound("assets/audio/sfx/player_shrink_bullets.wav")
	a.sfx_takes_damage = rl.LoadSound("assets/audio/sfx/player_takes_damage.wav")

	apply_sfx_volume(a)
}

update_audio :: proc(a: ^Audio) {
	rl.UpdateMusicStream(a.theme)
}

unload_audio :: proc(a: ^Audio) {
	rl.StopMusicStream(a.theme)
	rl.UnloadMusicStream(a.theme)
	rl.UnloadSound(a.sfx_charged_beam)
	rl.UnloadSound(a.sfx_charging_beam)
	rl.UnloadSound(a.sfx_dash)
	rl.UnloadSound(a.sfx_laser)
	rl.UnloadSound(a.sfx_reflects_bullet)
	rl.UnloadSound(a.sfx_shrink_bullets)
	rl.UnloadSound(a.sfx_takes_damage)
	rl.CloseAudioDevice()
}

set_music_volume :: proc(a: ^Audio, v: f32) {
	a.music_volume = clamp(v, 0.0, 1.0)
	rl.SetMusicVolume(a.theme, a.music_volume)
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
	rl.SetSoundVolume(a.sfx_laser, a.sfx_volume)
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
