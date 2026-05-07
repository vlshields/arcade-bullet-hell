package game

import rl "vendor:raylib"

// Underwater-style texcoord distortion: samples the source texture along a
// gently warped UV instead of straight-through. `seconds` is updated each
// frame so the wave keeps moving on a static texture.

@(private = "file")
WAVE_FS_DESKTOP :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform float seconds;
out vec4 finalColor;
const float freqX = 25.0;
const float freqY = 25.0;
const float ampX = 0.005;
const float ampY = 0.005;
const float speedX = 8.0;
const float speedY = 8.0;
void main() {
    float pX = sin(fragTexCoord.y * freqY + seconds * speedY) * ampX;
    float pY = cos(fragTexCoord.x * freqX + seconds * speedX) * ampY;
    vec2 uv = fragTexCoord + vec2(pX, pY);
    finalColor = texture(texture0, uv) * fragColor;
}
`

@(private = "file")
WAVE_FS_WEB :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform float seconds;
const float freqX = 25.0;
const float freqY = 25.0;
const float ampX = 0.005;
const float ampY = 0.005;
const float speedX = 8.0;
const float speedY = 8.0;
void main() {
    float pX = sin(fragTexCoord.y * freqY + seconds * speedY) * ampX;
    float pY = cos(fragTexCoord.x * freqX + seconds * speedX) * ampY;
    vec2 uv = fragTexCoord + vec2(pX, pY);
    gl_FragColor = texture2D(texture0, uv) * fragColor;
}
`

Wave_Shader :: struct {
	shader:      rl.Shader,
	seconds_loc: i32,
}

load_wave_shader :: proc() -> Wave_Shader {
	s: rl.Shader
	when ODIN_OS == .JS {
		s = rl.LoadShaderFromMemory(nil, WAVE_FS_WEB)
	} else {
		s = rl.LoadShaderFromMemory(nil, WAVE_FS_DESKTOP)
	}
	return Wave_Shader{shader = s, seconds_loc = rl.GetShaderLocation(s, "seconds")}
}

unload_wave_shader :: proc(w: ^Wave_Shader) {
	rl.UnloadShader(w.shader)
}

set_wave_seconds :: proc(w: ^Wave_Shader, seconds: f32) {
	s := seconds
	rl.SetShaderValue(w.shader, w.seconds_loc, &s, .FLOAT)
}
