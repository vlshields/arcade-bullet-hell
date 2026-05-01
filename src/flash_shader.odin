package game

import rl "vendor:raylib"

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
