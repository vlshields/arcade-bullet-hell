package game

import rl "vendor:raylib"

// Procedural bullet glow. Each bullet is drawn as a single textured quad whose
// fragment shader computes a radial falloff from the quad center: a tight
// white-hot core sitting inside a soft tinted halo. Combined with additive
// blending in draw_bullets, overlapping bullets bloom together naturally.
// `halo_col` lifts the tint 35% toward white so dim source colors (Morgan's
// purple, etc.) still read as bright projectiles instead of muted blobs; the
// 1.5x alpha multiplier on output pushes the falloff midrange hotter without
// clipping the peak (the peak is already at 1.0).

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
