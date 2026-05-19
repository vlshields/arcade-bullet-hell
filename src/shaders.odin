package game

import rl "vendor:raylib"

// #region Bullet Shaders

@(private = "file")
GLOW_FS_DESKTOP :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;
void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d = length(uv);
    if (d > 1.0) discard;
    float edge = 1.0 - d;
    float halo = pow(edge, 3.5);
    float core = pow(edge, 5.0);
    vec3 hue = fragColor.rgb * 1.3;
    vec3 halo_col = mix(hue, vec3(1.0), 0.2);
    vec3 col = mix(halo_col, vec3(1.0), core * 0.5);
    finalColor = vec4(col, halo * fragColor.a * 2.0);
}
`

@(private = "file")
GLOW_FS_WEB :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
void main() {
    vec2 uv = fragTexCoord * 2.0 - 1.0;
    float d = length(uv);
    if (d > 1.0) discard;
    float edge = 1.0 - d;
    float halo = pow(edge, 3.5);
    float core = pow(edge, 5.0);
    vec3 hue = fragColor.rgb * 1.3;
    vec3 halo_col = mix(hue, vec3(1.0), 0.2);
    vec3 col = mix(halo_col, vec3(1.0), core * 0.5);
    gl_FragColor = vec4(col, halo * fragColor.a * 2.0);
}
`

load_glow_shader :: proc() -> rl.Shader {
	when ODIN_OS == .JS {
		return rl.LoadShaderFromMemory(nil, GLOW_FS_WEB)
	} else {
		return rl.LoadShaderFromMemory(nil, GLOW_FS_DESKTOP)
	}
}

// 1x1 white texture used solely so DrawTexturePro generates the 0..1
// fragTexCoord span the glow shader needs. The texture itself is never sampled.
load_glow_texture :: proc() -> rl.Texture2D {
	img := rl.GenImageColor(1, 1, rl.WHITE)
	tex := rl.LoadTextureFromImage(img)
	rl.UnloadImage(img)
	return tex
}

// #endregion

// #region Flash Shader
@(private = "file")
FLASH_FS_DESKTOP :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
out vec4 finalColor;
void main() {
    vec4 texelColor = texture(texture0, fragTexCoord);
    finalColor = vec4(1.0, 1.0, 1.0, texelColor.a * fragColor.a);
}
`

@(private = "file")
FLASH_FS_WEB :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
void main() {
    vec4 texelColor = texture2D(texture0, fragTexCoord);
    gl_FragColor = vec4(1.0, 1.0, 1.0, texelColor.a * fragColor.a);
}
`

load_flash_shader :: proc() -> rl.Shader {
	when ODIN_OS == .JS {
		return rl.LoadShaderFromMemory(nil, FLASH_FS_WEB)
	} else {
		return rl.LoadShaderFromMemory(nil, FLASH_FS_DESKTOP)
	}
}


// #endregion

// #region Wave Shader



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

// #endregion

// #region BG Tint Shader

// Desaturates and darkens the background so the procedurally-drawn bullets
// (which run at full saturation in their own pass) sit visibly on top.
// `saturation` is 0..1: 0 leaves the BG untouched, 1 pulls it fully to luma-
// grayscale. `darkness` is a flat multiplier on RGB (1 = no change, 0.5 = half
// brightness). Tune these constants until projectiles read clearly against the
// busiest BG; a future blur uniform can be added here if desat alone isn't enough.
@(private = "file")
BG_TINT_SATURATION :: 0.7
@(private = "file")
BG_TINT_DARKNESS :: 0.7

@(private = "file")
BG_TINT_FS_DESKTOP :: `#version 330
in vec2 fragTexCoord;
in vec4 fragColor;
uniform sampler2D texture0;
uniform float saturation;
uniform float darkness;
out vec4 finalColor;
void main() {
    vec4 t = texture(texture0, fragTexCoord) * fragColor;
    float luma = dot(t.rgb, vec3(0.299, 0.587, 0.114));
    vec3 desat = mix(t.rgb, vec3(luma), saturation);
    finalColor = vec4(desat * darkness, t.a);
}
`

@(private = "file")
BG_TINT_FS_WEB :: `#version 100
precision mediump float;
varying vec2 fragTexCoord;
varying vec4 fragColor;
uniform sampler2D texture0;
uniform float saturation;
uniform float darkness;
void main() {
    vec4 t = texture2D(texture0, fragTexCoord) * fragColor;
    float luma = dot(t.rgb, vec3(0.299, 0.587, 0.114));
    vec3 desat = mix(t.rgb, vec3(luma), saturation);
    gl_FragColor = vec4(desat * darkness, t.a);
}
`

Bg_Tint_Shader :: struct {
	shader:         rl.Shader,
	saturation_loc: i32,
	darkness_loc:   i32,
}

load_bg_tint_shader :: proc() -> Bg_Tint_Shader {
	s: rl.Shader
	when ODIN_OS == .JS {
		s = rl.LoadShaderFromMemory(nil, BG_TINT_FS_WEB)
	} else {
		s = rl.LoadShaderFromMemory(nil, BG_TINT_FS_DESKTOP)
	}
	sat: f32 = BG_TINT_SATURATION
	dark: f32 = BG_TINT_DARKNESS
	sat_loc := rl.GetShaderLocation(s, "saturation")
	dark_loc := rl.GetShaderLocation(s, "darkness")
	rl.SetShaderValue(s, sat_loc, &sat, .FLOAT)
	rl.SetShaderValue(s, dark_loc, &dark, .FLOAT)
	return Bg_Tint_Shader{shader = s, saturation_loc = sat_loc, darkness_loc = dark_loc}
}

unload_bg_tint_shader :: proc(t: ^Bg_Tint_Shader) {
	rl.UnloadShader(t.shader)
}

// #endregion