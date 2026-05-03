## Project

Vertical-scrolling bullet-hell shoot-em-up built in Odin against Raylib bindings (`vendor:raylib`). A submission for the [bullet hell game jam](https://itch.io/jam/bullet-jam-7) on itch.io. This is a reference for anyone who wants to test/build the game and/or examine the source. The how-to-play and other gameplay details will live on the game's itch.io page. 

## Building 

### For web

Requires [emscripten](https://emscripten.org/). 

I find it best to create a shell script with some of the following commands. This is only a general guidline, no hard-fast rules here. Replace these with your desired build flags and parameters, etc.

First, load the emscripten sdk env:

```bash
# supress verbose output
export EMSDK_QUIET=1

# replace with /path/to/emsdk
[[ -f "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh" ]] && . "$EMSCRIPTEN_SDK_DIR/emsdk_env.sh"
```

The path should be something like `/home/$USER/emsdk`

now build targeting wasm:

```bash
# -vet -strict-style -disallow-do flags are optional
odin build src/main_web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -vet -strict-style -disallow-do -out:$OUT_DIR/game.wasm.o

files="$OUT_DIR/game.wasm.o ${ODIN_PATH}/vendor/raylib/wasm/libraylib.a"

emcc -o $OUT_DIR/index.html $files \
# some optional flags can go here. For example: -sUSE_GLFW=3
    
	--js-library src/main_web/emscripten_sleep_noop.js \
	--shell-file src/main_web/index_template.html \
	--preload-file assets

rm $OUT_DIR/game.wasm.o
```
Give OUT_DIR a seperate build dir from cwd. Something like `$OUT_DIR = '/build/web'` is fine.  

You'll then just need a simple http server from your target build dir. I use python's built in http server.

### Desktop

Compiling anything local with Odin is a breeze. The assets however are not included in this repo, so only the web build is officially supported.