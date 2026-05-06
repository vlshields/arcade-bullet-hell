package game

SCREEN_WIDTH :: 640 // px
SCREEN_HEIGHT :: 360 // px

BG_LAYERS :: 3 // count

MUSIC_VOLUME :: 0.2 // multiplier [0..1] (default volume for the looping theme song)
SFX_VOLUME :: 0.6 // multiplier [0..1] (default volume applied to every loaded sfx clip)

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

PLAYER_PROJECTILE_ORIGIN_Y_OFFSET :: -3.0 // px (vertical offset from player center where projectiles emit; negative = above center, lines up with the gun barrel)

PLAYER_DASH_SPEED :: 480.0 // px/s
PLAYER_DASH_DURATION :: 0.18 // s
PLAYER_DASH_COOLDOWN :: 0.45 // s (from dash start; must exceed DASH_DURATION)
PLAYER_DASH_TRAIL_LEN :: 12 // count (afterimage snapshots; one per frame during dash)
PLAYER_DASH_TRAIL_FADE_TIME :: 0.35 // s (afterimage visibility after dash starts)
PLAYER_DASH_TRAIL_MAX_ALPHA :: 0.65 // multiplier (cap on newest afterimage alpha)

PLAYER_MAX_STAMINA :: 50.0 // stamina
PLAYER_DASH_STAMINA_COST :: 5.0 // stamina/dash
PLAYER_STAMINA_RECOVER_RATE :: 2.0 // stamina/s (1 per 0.5s)
DASH_FRENZY_EXTRA_STAMINA_COST :: 2.0 // stamina/dash (added on top of base when Dash Frenzy upgrade is active)

SLOW_TIME_FACTOR :: 0.5 // multiplier (unitless) on world dt while slow-time is held
SLOW_TIME_STAMINA_PER_SEC :: 10.0 // stamina/s drained while slow-time is held; ends when stamina hits 0
SLOW_TIME_TINT_R :: 80 // [0..255] (cyan-blue cool wash over the world while slow-time is active)
SLOW_TIME_TINT_G :: 180 // [0..255]
SLOW_TIME_TINT_B :: 255 // [0..255]
SLOW_TIME_TINT_ALPHA_BASE :: 55 // alpha [0..255] (midpoint of the breathing pulse)
SLOW_TIME_TINT_ALPHA_PULSE :: 20 // alpha [0..255] (amplitude of the breathing pulse around the base)
SLOW_TIME_PULSE_HZ :: 1.6 // Hz (breathing cadence for the tint pulse)

ENEMY_COUNT :: 6 // count (shared pool capacity for the per-level main enemy — sized to the largest wave)
GRUNT_WAVE_COUNT :: 3 // count (grunts per level-1 wave; orbit is evenly divided across this count)
ENEMY_FRAME_W :: 16 // px (sprite source)
ENEMY_FRAME_H :: 16 // px (sprite source)
ENEMY_FRAMES :: 2 // count
ENEMY_ANIM_FPS :: 8.0 // frames/s
ENEMY_DRAW_SCALE :: 2 // multiplier (unitless)
ENEMY_ORBIT_RADIUS :: 120.0 // px (from player center)
ENEMY_SPAWN_RADIUS :: 500.0 // px (from player center)
ENEMY_APPROACH_SPEED :: 200.0 // px/s
ENEMY_ORBIT_SPEED :: 0.6 // rad/s
ENEMY_FIRE_INTERVAL :: 3.0 // s (initial; shrinks once after the threshold below)
ENEMY_WAVE_BOOST_THRESHOLD :: 3 // count (waves cleared before fire-frequency boost applies)
ENEMY_FIRE_FREQ_BOOST :: 0.5 // fraction (added to fire frequency at threshold; interval becomes interval / (1 + this))
ENEMY_BULLETS_PER_BURST :: 12 // count
ENEMY_BULLET_SPEED :: 70.0 // px/s
ENEMY_MAX_HP :: 21 // hp
ENEMY_HIT_RADIUS :: 10.0 // px
ENEMY_HIT_FLASH_TIME :: 0.08 // s

WEIRDGUY_WAVE_COUNT :: 6 // count (weird guys per level-2 wave; respawn as a fresh wave when all are dead)
WEIRDGUY_MAX_HP :: 4 // hp
WEIRDGUY_FRAME_W :: 16 // px (sprite source)
WEIRDGUY_FRAME_H :: 16 // px (sprite source)
WEIRDGUY_FRAMES :: 1 // count
WEIRDGUY_DRAW_SCALE :: 2 // multiplier (unitless)
WEIRDGUY_HIT_RADIUS :: 10.0 // px
WEIRDGUY_PATROL_RANGE :: 220.0 // px (lateral viewport distance covered between turns)
WEIRDGUY_SPEED :: 280.0 // px/s (lateral patrol speed; "rapidly across the viewport")
WEIRDGUY_Y_MIN :: 30.0 // px (random spawn altitude lower bound)
WEIRDGUY_Y_MAX :: 200.0 // px (random spawn altitude upper bound; keeps weird guys above typical player y)
WEIRDGUY_FIRE_INTERVAL :: 0.08 // s (between single-bullet shots; "extremely rapid")
WEIRDGUY_BULLET_SPEED :: 100.0 // px/s

BOSS_TRIGGER_WAVE :: 6 // count (grunt waves cleared before Golgatha spawns)
BOSS_MAX_HP :: 110 // hp
BOSS_FRAME_W :: 32 // px (sprite source)
BOSS_FRAME_H :: 32 // px (sprite source)
BOSS_FRAMES :: 5 // count
BOSS_DRAW_SCALE :: 2 // multiplier (unitless)
BOSS_ANIM_FPS :: 6.0 // frames/s
BOSS_HIT_RADIUS :: 16.0 // px
BOSS_HIT_FLASH_TIME :: 0.08 // s
BOSS_SPAWN_X :: 320.0 // px (anchor x; SCREEN_WIDTH / 2)
BOSS_SPAWN_Y :: 60.0 // px (anchor y, fixed; sway only on x)
BOSS_SWAY_AMPLITUDE :: 38.0 // px 
BOSS_SWAY_FREQ :: 0.8 // Hz (brisk side-to-side cadence)
BOSS_FIRE_INTERVAL :: 0.033 // s (matches bhport reference: 2 frames @ 60fps)
BOSS_BULLET_ROWS :: 6 // count (matches bhport reference default)
BOSS_ANGLE_INCREMENT_DEG :: 5.0 // deg/burst (rotation of base direction; matches bhport reference)
BOSS_BULLET_SPEED :: 130.0 // px/s (bhport reference scaled to 640x360)
BOSS_SNEAK_SPAWN_INTERVAL :: 4.0 // s (cadence of try_spawn_sneak attempts during boss fight)
BOSS_NAME :: "GOLGATHA" // string
BOSS_NAME_FONT_SIZE :: 12 // px
BOSS_HUD_BAR_W :: 360 // px (centered at top of screen)
BOSS_HUD_BAR_H :: 8 // px
BOSS_HUD_NAME_Y :: 6 // px (name top edge from screen top)
BOSS_HUD_BAR_Y :: 22 // px (bar top edge from screen top)

SNEAK_MAX :: 6 // count (hard cap on simultaneously active minor enemies — sneaks + cyclops share slots; sized for the level-2 "between" phases where 4 sneaks or 1 cyclops + sneaks are scripted at once)
LEVEL1_SNEAK_CAP :: 2 // count (effective level-1 cap; preserves prior level-1 difficulty since the pool was historically size 2)
SNEAK_SPAWN_CHANCE :: 0.5 // probability [0..1] (heads = sneak, tails = cyclops on level >= 2; rolled on any enemy death)
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

CYCLOPS_MAX_HP :: 50 // hp
CYCLOPS_FRAME_W :: 16 // px (sprite source)
CYCLOPS_FRAME_H :: 16 // px (sprite source)
CYCLOPS_FRAMES :: 9 // count
CYCLOPS_ANIM_FPS :: 8.0 // frames/s
CYCLOPS_DRAW_SCALE :: 2 // multiplier (unitless)
CYCLOPS_HIT_RADIUS :: 10.0 // px (matches grunt)
CYCLOPS_BULLET_SPEED :: 90.0 // px/s (matches sneak)
CYCLOPS_CROSS_DURATION :: 5.5 // s (one full side-to-side pass)
CYCLOPS_OFFSCREEN_MARGIN :: 24.0 // px (start/end x sit this far past the screen edge)
CYCLOPS_Y_MIN :: 30.0 // px (random pass altitude lower bound)
CYCLOPS_Y_MAX :: 220.0 // px (random pass altitude upper bound; keeps cyclops above typical player y)
CYCLOPS_PATTERN_COUNT :: 3 // count (size of the bullet-pattern bag; rerolled each pass)
CYCLOPS_AIMED_INTERVAL :: 0.7 // s (cadence of pattern 0: aimed fan)
CYCLOPS_AIMED_BULLETS :: 5 // count
CYCLOPS_AIMED_FAN_DEG :: 30.0 // deg (total fan width across the aimed burst)
CYCLOPS_RING_INTERVAL :: 1.3 // s (cadence of pattern 1: full ring)
CYCLOPS_RING_BULLETS :: 10 // count (evenly spaced around the cyclops)
CYCLOPS_SPIRAL_INTERVAL :: 0.15 // s (cadence of pattern 2: rotating spiral arms)
CYCLOPS_SPIRAL_ARMS :: 2 // count (opposing arms; mini-Golgatha feel)
CYCLOPS_SPIRAL_INC_DEG :: 14.0 // deg/burst (rotation of spiral base angle)

BULLET_LIFE :: 4.0 // s
BULLET_RADIUS :: 3.0 // px
MAX_BULLETS :: 512 // count (pool capacity; sized to absorb sustained Rapid_Fire bursts (~120 in flight) on top of enemy patterns)

SHRINK_BOMBS_PER_LEVEL :: 3 // count (player's shrink-bomb stock; reset at the start of every level)
SHRINK_BOMB_DURATION :: 0.4 // s (time for an enemy bullet caught in the bomb to shrink to nothing)
SHRINK_BOMB_BURST_PARTICLES :: 24 // count (player-centered particle burst when a bomb deploys)
SHRINK_BOMB_HUD_DOT_R :: 3.0 // px (radius of each remaining-bomb pip drawn on the HUD)
SHRINK_BOMB_HUD_DOT_GAP :: 4 // px (horizontal gap between HUD pips)

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
CHARGE_BEAM_FULL_STAMINA_COST :: 15.0 // stamina (at full charge; scales linearly with charge on release)
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

RAPID_FIRE_INTERVAL :: 0.05 // s (between rapid-fire shots while attack is held; 20 shots/s for bullet-hell density)
RAPID_FIRE_DAMAGE :: 3 // hp/hit (per rapid-fire bullet on enemy)
RAPID_FIRE_SPEED :: 234.0 // px/s
RAPID_FIRE_LIFE :: 4.0 // s (per-projectile lifespan)
RAPID_FIRE_RADIUS :: 1.0 // px (core circle)
RAPID_FIRE_GLOW_MULT :: 3.5 // multiplier (glow circle radius vs core; matches LASER_GLOW_MULT family)

DASH_FRENZY_MISSILES_PER_DASH :: 2 // count (homing missiles launched on each dash while Dash Frenzy is active)
DASH_FRENZY_LAUNCH_FAN_DEG :: 70.0 // deg (total spread between the two missiles, centered on the dash direction)
MISSILE_DAMAGE :: 8 // hp/hit (per missile impact on enemy/sneak/boss)
MISSILE_SPEED :: 220.0 // px/s (constant cruise speed; missiles always travel at this speed)
MISSILE_LIFE :: 2.5 // s (auto-detonate after this if no target hit)
MISSILE_HIT_RADIUS :: 4.0 // px (circle radius used for collision against enemies)
MISSILE_TURN_RATE :: 6.0 // 1/s (exponential lerp rate of velocity toward the homing target)
MISSILE_INITIAL_BLIND_TIME :: 0.05 // s (no homing during launch fan-out so the spread is visible)
MISSILE_TRAIL_LEN :: 14 // count (past-position samples kept per missile for trail rendering)
MISSILE_TRAIL_SAMPLE_INTERVAL :: 0.018 // s (gap between trail samples; smaller = denser trail)
MISSILE_GLOW_LAYERS :: 4 // count (concentric glow circles drawn per missile body and trail node)
MISSILE_BODY_RADIUS :: 2.5 // px (innermost bright core of the missile body)
MISSILE_TRAIL_NODE_RADIUS :: 1.8 // px (innermost radius of trail node before glow scaling)
MISSILE_IMPACT_PARTICLES :: 8 // count (per missile detonation; reuses spawn_impact_particles)
MAX_MISSILES :: 24 // count (pool capacity; sized for back-to-back dashes)

HEALTHPACK_MAX :: 8 // count (pool capacity)
HEALTHPACK_DROP_CHANCE :: 0.15 // probability [0..1] (rolled per enemy/boss kill)
HEALTHPACK_HEAL :: 10 // hp (per pickup; clamped to PLAYER_MAX_HP)
HEALTHPACK_RADIUS :: 6.0 // px (collision; sums with PLAYER_HIT_RADIUS for pickup)
HEALTHPACK_ARM :: 4.5 // px (cross arm half-length at pulse=1)
HEALTHPACK_THICK :: 3.0 // px (cross bar thickness)
HEALTHPACK_PULSE_HZ :: 1.5 // Hz (visibility pulse cadence)
HEALTHPACK_DRIFT_SPEED :: 22.0 // px/s (downward drift; pack expires when it leaves the bottom of the screen — players lose their chance if they don't grab it in time)

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

SCORE_KILL_LASER :: 10 // points (per enemy killed by the rapid laser)
SCORE_KILL_CHARGE :: 15 // points (per enemy killed by the released charge beam)
SCORE_KILL_REFLECT :: 25 // points (per enemy killed by a deflected bullet)
SCORE_KILL_RAPID :: 10 // points (per enemy killed by a rapid-fire bullet)
SCORE_KILL_BOSS :: 100 // points (per boss kill)
SCORE_FONT_SIZE :: 16 // px (top-left score readout)

VICTORY_TITLE_FONT_SIZE :: 24 // px
VICTORY_SCORE_FONT_SIZE :: 16 // px
VICTORY_PROMPT_FONT_SIZE :: 10 // px (mission-advance prompt below score)
VICTORY_OVERLAY_ALPHA :: 180 // alpha [0..255]

UPGRADE_TITLE_Y :: 30 // px (top y of MISSION COMPLETE title while choosing)
UPGRADE_HEADER_Y :: 100 // px (top y of "CHOOSE YOUR UPGRADE" header)
UPGRADE_HEADER_FONT_SIZE :: 14 // px
UPGRADE_CARDS_Y :: 130 // px (top y of upgrade card row)
UPGRADE_CARD_W :: 180 // px
UPGRADE_CARD_H :: 110 // px
UPGRADE_CARD_GAP :: 24 // px (horizontal gap between cards)
UPGRADE_NAME_FONT_SIZE :: 14 // px
UPGRADE_BODY_FONT_SIZE :: 8 // px (description lines inside cards)

TRANSITION_HALF_DUR :: 0.6 // s (each half of mission transition: fade-out then fade-in, swap at midpoint)

LEVEL2_BETWEEN_1CYC2SN_SNEAK_COUNT :: 2 // count (sneaks spawned alongside the cyclops in the second between-beat)
LEVEL2_BETWEEN_4SNEAKS_COUNT :: 4 // count (sneaks spawned at the start of the all-sneaks between-beat)
LEVEL2_BETWEEN_3CYC_TARGET :: 3 // count (cyclops kills required to clear the 3-cyclops gauntlet)
LEVEL2_BETWEEN_3CYC_SNEAK_INTERVAL :: 4.0 // s (cadence of streaming sneak spawns during the 3-cyclops gauntlet)
LEVEL2_WAVES_TO_VICTORY :: 5 // count (level-2 phases the player must clear to trigger the victory screen; covers Wave1 → Between_1Cyc → Between_1Cyc_2Sneaks → Wave2 → Between_4Sneaks)

MAX_LEVEL :: 2 // count (highest level with content; victory beyond this stays on the win screen until level 3 is wired in)

PAUSE_OVERLAY_ALPHA :: 200 // alpha [0..255] (dim overlay drawn behind the pause menu)
PAUSE_TITLE_FONT_SIZE :: 20 // px
PAUSE_TITLE_Y :: 50 // px (top y of "PAUSED" title)
PAUSE_MENU_TOP_Y :: 130 // px (top y of the first menu row beneath the title)
PAUSE_ITEM_FONT_SIZE :: 14 // px (menu item / slider label font)
PAUSE_ITEM_GAP :: 14 // px (vertical gap between menu rows)
PAUSE_BODY_FONT_SIZE :: 10 // px (controls list body font)
PAUSE_BODY_LINE_GAP :: 14 // px (vertical pitch between control rows)
PAUSE_SLIDER_W :: 160 // px
PAUSE_SLIDER_H :: 6 // px
PAUSE_VOLUME_STEP :: 0.05 // multiplier (unitless; per left/right tap when adjusting volume sliders)
