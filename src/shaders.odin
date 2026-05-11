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
    float core = pow(edge, 8.0);
    vec3 halo_col = mix(fragColor.rgb, vec3(1.0), 0.35);
    vec3 col = mix(halo_col, vec3(1.0), core);
    finalColor = vec4(col, halo * fragColor.a * 1.5);
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
    float core = pow(edge, 8.0);
    vec3 halo_col = mix(fragColor.rgb, vec3(1.0), 0.35);
    vec3 col = mix(halo_col, vec3(1.0), core);
    gl_FragColor = vec4(col, halo * fragColor.a * 1.5);
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