# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionAutoTuner
#
# Role:
# Hill-climbs the MissionTuningProfile knob space to find
# parameters that hit target win rates per mission category
# and produce the target sigil economy by month 72.
#
# Allowed Interactions:
# - MissionLab (runs simulations)
# - MissionTuningProfile (mutates knobs during search)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not touch UI
# ==================================================

class_name MissionAutoTuner
extends Node

const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")

# --------------------------------------------------
# KNOB SEARCH SPACE
# Each entry: [knob_name, min, max, step, is_bool]
# --------------------------------------------------
const KNOB_SPACE: Array = [
	["scale_low",              0.50, 1.00, 0.05, false],
	["scale_high",             0.80, 1.60, 0.05, false],
	["elite_scale_low",        0.40, 0.90, 0.05, false],
	["elite_scale_high",       0.60, 1.20, 0.05, false],
	["elite_sigil_chance",     0.40, 0.70, 0.05, false],  # capped — prevents economy flood
	["elite_sigil_on_loss",    0.0,  1.0,  1.0,  true ],  # bool toggle
	["non_elite_sigil_chance", 0.00, 0.15, 0.01, false],
	["item_chance_skirmish",   0.00, 0.30, 0.05, false],
	["item_chance_treasure",   0.30, 0.90, 0.05, false],
	["item_chance_hunt",       0.20, 0.70, 0.05, false],
	["item_chance_elite",      0.50, 1.00, 0.05, false],
	["spawn_roll_chance",      0.30, 0.90, 0.05, false],
]

const RESTART_INTERVAL: int = 30
const SEEDS_PER_EVAL: int   = 30

var _best_score: float    = -99999.0
var _best_profile: Dictionary = {}
var _iteration: int       = 0
var _running: bool        = false

signal tuning_progress(iteration: int, score: float, profile: Dictionary)
signal tuning_complete(best_score: float, best_profile: Dictionary)


# --------------------------------------------------
# ENTRY POINT
# --------------------------------------------------

func start(iterations: int = 60) -> void:
	_running      = true
	_iteration    = 0
	_best_score   = -99999.0
	_best_profile = _profile_to_dict(MissionTuningProfile.get_instance())

	DebugLogger.log("event:mission_autotuner_start", {
		"iterations": iterations,
		"seeds_per_eval": SEEDS_PER_EVAL,
		"knobs": KNOB_SPACE.size(),
		"targets": {
			"elite_win_rate":    MissionTuningProfile.get_instance().target_elite_win_rate,
			"hunt_win_rate":     MissionTuningProfile.get_instance().target_hunt_win_rate,
			"treasure_win_rate": MissionTuningProfile.get_instance().target_treasure_win_rate,
			"skirmish_win_rate": MissionTuningProfile.get_instance().target_skirmish_win_rate,
			"sigils_per_leader": MissionTuningProfile.get_instance().target_sigils_per_leader,
		}
	})

	# Baseline
	var baseline: float = _evaluate(MissionTuningProfile.get_instance())
	_best_score = baseline
	DebugLogger.log("event:mission_autotuner_baseline", {"score": baseline})

	for i in range(iterations):
		if not _running:
			break
		_iteration = i + 1

		var candidate: MissionTuningProfile
		if _iteration % RESTART_INTERVAL == 0:
			candidate = _perturb_profile(_best_profile, 3)
			DebugLogger.log("event:mission_autotuner_restart", {"iteration": _iteration})
		else:
			candidate = _mutate_profile(_best_profile)

		var score: float = _evaluate(candidate)

		if score > _best_score:
			_best_score   = score
			_best_profile = _profile_to_dict(candidate)
			DebugLogger.log("event:mission_autotuner_improvement", {
				"iteration": _iteration,
				"score":     score,
				"profile":   _best_profile,
			})

		emit_signal("tuning_progress", _iteration, _best_score, _best_profile)

		# Yield every 5 iterations to avoid freezing the editor
		if _iteration % 5 == 0:
			await get_tree().process_frame

	DebugLogger.log("event:mission_autotuner_complete", {
		"best_score":   _best_score,
		"best_profile": _best_profile,
		"iterations":   _iteration,
	})
	emit_signal("tuning_complete", _best_score, _best_profile)
	_running = false


func stop() -> void:
	_running = false


# --------------------------------------------------
# EVALUATION
# --------------------------------------------------

func _evaluate(profile: MissionTuningProfile) -> float:
	MissionTuningProfile._instance = profile
	var results: Dictionary = MissionLab.run_full_suite(SEEDS_PER_EVAL)
	return MissionLab.score_results(results)


# --------------------------------------------------
# MUTATION
# --------------------------------------------------

func _mutate_profile(base: Dictionary) -> MissionTuningProfile:
	var p: MissionTuningProfile = MissionTuningProfile.new()
	_copy_dict_to_profile(base, p)
	var knob: Array = KNOB_SPACE[randi() % KNOB_SPACE.size()]
	_apply_knob_mutation(p, knob, 1)
	return p


func _perturb_profile(base: Dictionary, knob_count: int) -> MissionTuningProfile:
	var p: MissionTuningProfile = MissionTuningProfile.new()
	_copy_dict_to_profile(base, p)
	# Shuffle and pick knob_count knobs
	var indices: Array = range(KNOB_SPACE.size())
	for i in range(indices.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp = indices[i]; indices[i] = indices[j]; indices[j] = tmp
	for i in range(mini(knob_count, indices.size())):
		var knob: Array = KNOB_SPACE[indices[i]]
		_apply_knob_mutation(p, knob, 2 + randi() % 3)
	return p


func _apply_knob_mutation(p: MissionTuningProfile, knob: Array, steps: int) -> void:
	var knob_name: String = str(knob[0])
	var knob_min: float   = float(knob[1])
	var knob_max: float   = float(knob[2])
	var knob_step: float  = float(knob[3])
	var is_bool: bool     = bool(knob[4]) if knob.size() > 4 else false

	if is_bool:
		# Toggle bool
		var cur: bool = bool(p.get(knob_name))
		p.set(knob_name, not cur)
	else:
		var current: float = float(p.get(knob_name))
		var delta: float   = knob_step * float(steps) * (1 if randf() > 0.5 else -1)
		p.set(knob_name, clampf(current + delta, knob_min, knob_max))


# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func _profile_to_dict(p: MissionTuningProfile) -> Dictionary:
	var d: Dictionary = {}
	for knob in KNOB_SPACE:
		var name: String = str(knob[0])
		d[name] = p.get(name)
	return d


func _copy_dict_to_profile(d: Dictionary, p: MissionTuningProfile) -> void:
	for key in d.keys():
		if p.get(key) != null:
			p.set(key, d[key])


func apply_best_profile() -> void:
	if _best_profile.is_empty():
		return
	var p: MissionTuningProfile = MissionTuningProfile.get_instance()
	_copy_dict_to_profile(_best_profile, p)
	DebugLogger.log("event:mission_autotuner_applied", {"profile": _best_profile})
