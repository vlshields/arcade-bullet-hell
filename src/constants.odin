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
PLAYER_DASH_DURATION :: 0.29 // s
PLAYER_DASH_COOLDOWN :: 0.65 // s (from dash start; must exceed DASH_DURATION)
PLAYER_DASH_TRAIL_LEN :: 12 // count (afterimage snapshots; one per frame during dash)
PLAYER_DASH_TRAIL_FADE_TIME :: 0.35 // s (afterimage visibility after dash starts)
PLAYER_DASH_TRAIL_MAX_ALPHA :: 0.65 // multiplier (cap on newest afterimage alpha)

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
ENEMY_ANCHOR_FOLLOW_RATE :: 0.6 // 1/s (exponential lerp rate of orbit anchor toward player)
ENEMY_FIRE_INTERVAL :: 3.0 // s
ENEMY_BULLETS_PER_BURST :: 12 // count
ENEMY_BULLET_SPEED :: 70.0 // px/s
ENEMY_MAX_HP :: 21 // hp
ENEMY_HIT_RADIUS :: 8.0 // px
ENEMY_HIT_FLASH_TIME :: 0.08 // s

BULLET_LIFE :: 4.0 // s
BULLET_RADIUS :: 3.0 // px
MAX_BULLETS :: 256 // count (pool capacity)

LASER_FIRE_INTERVAL :: 0.19 // s (between shots)
LASER_DAMAGE :: 6 // hp/hit
LASER_LIFETIME :: 0.08 // s
LASER_THICKNESS :: 1.0 // px (core line)
LASER_GLOW_MULT :: 4.0 // multiplier (unitless, glow thickness vs core)
LASER_IMPACT_PARTICLES :: 6 // count (per enemy hit)
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
