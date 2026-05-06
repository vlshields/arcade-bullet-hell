package game

import rl "vendor:raylib"

Audio :: struct {
	theme: rl.Music,
}

init_audio :: proc(a: ^Audio) {
	rl.InitAudioDevice()
	a.theme = rl.LoadMusicStream("assets/audio/soundtrack/themesong1.ogg")
	a.theme.looping = true
	rl.SetMusicVolume(a.theme, MUSIC_VOLUME)
	rl.PlayMusicStream(a.theme)
}

update_audio :: proc(a: ^Audio) {
	rl.UpdateMusicStream(a.theme)
}

unload_audio :: proc(a: ^Audio) {
	rl.StopMusicStream(a.theme)
	rl.UnloadMusicStream(a.theme)
	rl.CloseAudioDevice()
}
