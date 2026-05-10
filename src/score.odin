package game

// One scoring category per visual mechanic, not per code path. Two paths that
// share the same point value (e.g. dash-reflected bullets and Dash Frenzy
// missiles both at 25) still get distinct kinds so the victory breakdown can
// credit them separately.
Score_Kind :: enum {
	Laser,
	Charge,
	Reflect,
	Rapid_Fire,
	Missile,
	Boss,
	Pillar,
	Guardian_Orb,
}

Score_Stats :: struct {
	total: int,
	kills: [Score_Kind]int,
}

score_kind_points :: proc(k: Score_Kind) -> int {
	switch k {
	case .Laser:
		return SCORE_KILL_LASER
	case .Charge:
		return SCORE_KILL_CHARGE
	case .Reflect:
		return SCORE_KILL_REFLECT
	case .Rapid_Fire:
		return SCORE_KILL_RAPID
	case .Missile:
		return SCORE_KILL_MISSILE
	case .Boss:
		return SCORE_KILL_BOSS
	case .Pillar:
		return PILLAR_KILL_SCORE
	case .Guardian_Orb:
		return GUARDIAN_ORB_KILL_SCORE
	}
	return 0
}

score_kind_label :: proc(k: Score_Kind) -> cstring {
	switch k {
	case .Laser:
		return "LASER KILLS"
	case .Charge:
		return "CHARGE BEAM KILLS"
	case .Reflect:
		return "DASH REFLECT KILLS"
	case .Rapid_Fire:
		return "RAPID FIRE KILLS"
	case .Missile:
		return "HOMING MISSILE KILLS"
	case .Boss:
		return "BOSS KILLS"
	case .Pillar:
		return "PILLAR KILLS"
	case .Guardian_Orb:
		return "GUARDIAN ORB KILLS"
	}
	return ""
}

add_kill :: proc(s: ^Score_Stats, k: Score_Kind) {
	s.kills[k] += 1
	s.total += score_kind_points(k)
}
