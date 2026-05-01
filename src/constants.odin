package game

SCREEN_WIDTH :: 640 // px
SCREEN_HEIGHT :: 360 // px

BG_LAYERS :: 3 // count

GAMEPAD_ID :: 0 // index
STICK_DEADZONE :: 0.2 // normalized axis magnitude [0..1]

PLAYER_SPEED :: 95.0 // px/s
PLAYER_MAX_HP :: 90 // hp
PLAYER_HIT_DAMAGE :: 3 // hp/hit
PLAYER_HIT_RADIUS :: 4.0 // px
PLAYER_INVULN_TIME :: 0.6 // s
PLAYER_FLASH_HZ :: 10.0 // toggles/s
PLAYER_ANIM_FPS :: 8.0 // frames/s
PLAYER_FRAME_W :: 8 // px (sprite source)
PLAYER_FRAME_H :: 8 // px (sprite source)
PLAYER_IDLE_FRAMES :: 7 // count
PLAYER_MOVE_FRAMES :: 3 // count
PLAYER_DRAW_SCALE :: 2 // multiplier (unitless)
RETICLE_FRAME_W :: 8 // px (sprite source)
RETICLE_FRAME_H :: 8 // px (sprite source)
RETICLE_DISTANCE :: 90.0 // px (from player center)

PLAYER_DASH_SPEED :: 480.0 // px/s
PLAYER_DASH_DURATION :: 0.18 // s
PLAYER_DASH_COOLDOWN :: 0.45 // s (from dash start; must exceed DASH_DURATION)
PLAYER_DASH_TRAIL_LEN :: 12 // count (afterimage snapshots; one per frame during dash)
PLAYER_DASH_TRAIL_FADE_TIME :: 0.35 // s (afterimage visibility after dash starts)
PLAYER_DASH_TRAIL_MAX_ALPHA :: 0.65 // multiplier (cap on newest afterimage alpha)

PLAYER_MAX_STAMINA :: 50.0 // stamina
PLAYER_DASH_STAMINA_COST :: 5.0 // stamina/dash
PLAYER_STAMINA_RECOVER_RATE :: 2.0 // stamina/s (1 per 0.5s)

ENEMY_COUNT :: 3 // count
ENEMY_FRAME_W :: 16 // px (sprite source)
ENEMY_FRAME_H :: 16 // px (sprite source)
ENEMY_FRAMES :: 2 // count
ENEMY_ANIM_FPS :: 8.0 // frames/s
ENEMY_DRAW_SCALE :: 2 // multiplier (unitless)
ENEMY_ORBIT_RADIUS :: 120.0 // px (from player center)
ENEMY_SPAWN_RADIUS :: 500.0 // px (from player center)
ENEMY_APPROACH_SPEED :: 200.0 // px/s
ENEMY_ORBIT_SPEED :: 0.8 // rad/s
ENEMY_FIRE_INTERVAL :: 3.0 // s
ENEMY_BULLETS_PER_BURST :: 12 // count
ENEMY_BULLET_SPEED :: 70.0 // px/s
ENEMY_MAX_HP :: 21 // hp
ENEMY_HIT_RADIUS :: 8.0 // px
ENEMY_HIT_FLASH_TIME :: 0.08 // s

SNEAK_MAX :: 2 // count (cap on simultaneously active sneaks)
SNEAK_SPAWN_CHANCE :: 0.5 // probability [0..1] (rolled on any enemy death)
SNEAK_FRAME_W :: 16 // px (sprite source)
SNEAK_FRAME_H :: 16 // px (sprite source)
SNEAK_FRAMES :: 1 // count
SNEAK_DRAW_SCALE :: 2 // multiplier (unitless)
SNEAK_SPAWN_MARGIN :: 24.0 // px (from viewport edges when picking spawn / teleport point)
SNEAK_SWAY_AMPLITUDE :: 14.0 // px (lateral offset from spawn anchor)
SNEAK_SWAY_FREQ :: 1.4 // Hz
SNEAK_BURST_INTERVAL :: 0.3333 // s (3 bursts per second)
SNEAK_BULLETS_PER_BURST :: 4 // count
SNEAK_BURST_FAN_DEG :: 24.0 // deg (total fan width across the 4 bullets, aimed at player)
SNEAK_BULLET_SPEED :: 90.0 // px/s
SNEAK_TELEPORT_INTERVAL :: 10.0 // s
SNEAK_MAX_HP :: 6 // hp
SNEAK_HIT_RADIUS :: 7.0 // px
SNEAK_HIT_FLASH_TIME :: 0.08 // s

BULLET_LIFE :: 4.0 // s
BULLET_RADIUS :: 3.0 // px
MAX_BULLETS :: 256 // count (pool capacity)

REFLECT_HOMING_RATE :: 1.1 // 1/s (exponential lerp rate of reflected bullet velocity toward nearest enemy)
REFLECT_DAMAGE :: 8 // hp/hit
REFLECT_IMPACT_PARTICLES :: 5 // count (per enemy hit by reflected bullet)

LASER_FIRE_INTERVAL :: 0.19 // s (between shots while shoot button held)
LASER_DAMAGE :: 6 // hp/hit
LASER_LIFETIME :: 0.08 // s
LASER_THICKNESS :: 1.0 // px (core line)
LASER_GLOW_MULT :: 4.0 // multiplier (unitless, glow thickness vs core)
LASER_IMPACT_PARTICLES :: 6 // count (per enemy hit by laser)

CHARGE_BEAM_BASE_DAMAGE :: 6 // hp/hit (released at >= MIN_FIRE charge)
CHARGE_BEAM_DAMAGE_BONUS :: 6 // hp/hit (added at full charge; total = 2 * base)
CHARGE_BEAM_HOLD_DELAY :: 1.0 // s (button must be held this long before charging begins)
CHARGE_BEAM_RATE :: 2.0 // 1/s (charge fraction per second once charging starts; full in 0.5s after delay)
CHARGE_BEAM_LIFETIME_BASE :: 0.3 // s (visible duration at zero charge)
CHARGE_BEAM_LIFETIME_BONUS :: 0.3 // s (added at full charge)
CHARGE_BEAM_THICKNESS_BASE :: 5.0 // px (released beam core width at zero charge)
CHARGE_BEAM_THICKNESS_BONUS :: 25.0 // px (added at full charge)
CHARGE_BEAM_HIT_PAD :: 4.0 // px (collision half-width pad beyond beam thickness)
CHARGE_BEAM_IMPACT_PARTICLES :: 6 // count (per enemy hit by released beam)
CHARGE_BEAM_RELEASE_BURST_BASE :: 10 // count (release-point particle burst at zero charge)
CHARGE_BEAM_RELEASE_BURST_BONUS :: 30 // count (added at full charge)
CHARGE_BEAM_FRINGE_COUNT :: 15 // count (electric fringe candidate positions per draw)
CHARGE_BEAM_GATHER_DIST_MIN :: 30.0 // px (gather particle spawn distance from source)
CHARGE_BEAM_GATHER_DIST_RANGE :: 20.0 // px (gather particle spawn distance random range)
CHARGE_BEAM_GATHER_LIFE :: 0.2 // s (gather particle lifetime)
MAX_BEAMS :: 16 // count (pool capacity)

PARTICLE_GRAVITY :: 200.0 // px/s²
PARTICLE_SPEED_MIN :: 50.0 // px/s
PARTICLE_SPEED_MAX :: 200.0 // px/s
PARTICLE_LIFE_MIN :: 0.3 // s
PARTICLE_LIFE_MAX :: 0.7 // s
PARTICLE_SIZE_MIN :: 2.0 // px
PARTICLE_SIZE_MAX :: 6.0 // px
MAX_PARTICLES :: 256 // count (pool capacity)

HP_BAR_W :: 80 // px
HP_BAR_H :: 6 // px
HP_BAR_MARGIN :: 6 // px (from screen edge)
STATUS_BAR_GAP :: 2 // px (vertical gap between stacked status bars)
