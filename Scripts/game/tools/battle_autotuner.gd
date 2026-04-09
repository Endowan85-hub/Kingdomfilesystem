# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: BattleAutoTuner
#
# Role:
# Searches BattleTuningProfile knob space to find
# optimal combat balance parameters.
# Uses hill-climbing with random restarts.
#
# Allowed Interactions:
# - BattleLab (runs simulations)
# - BattleTuningProfile (mutates knobs during search)
#
# Forbidden Responsibilities:
# - Must not modify GameState
# - Must not touch UI
# ==================================================

class_name BattleAutoTuner
extends Node

const DebugLogger = preload("res://Scripts/debug/debug_logger.gd")

# --------------------------------------------------
# KNOB SEARCH SPACE
# Each entry: [knob_name, min, max, step]
# --------------------------------------------------
const KNOB_SPACE: Array = [
	["def_constant",              20.0,  60.0,  2.0],
	["variance_fraction",          0.05,  0.30,  0.05],
	["type_advantage_mult",        1.0,   1.8,   0.10],
	["type_disadvantage_mult",     0.4,   0.95,  0.10],
	["defend_mult",                1.2,   2.0,   0.1],
	["leader_atk_bonus_fraction",  0.05,  0.30,  0.05],
	["leader_def_bonus_fraction",  0.05,  0.30,  0.05],
	["fort_def_mult",              0.05,  0.30,  0.05],
]

# Random restart every N iterations to escape local optima
const RESTART_INTERVAL: int = 40

var _best_score: float = -99999.0
var _best_profile: Dictionary = {}
var _iteration: int = 0
var _seeds_per_run: int = 20
var _running: bool = false

signal tuning_progress(iteration: int, score: float, profile: Dictionary)
signal tuning_complete(best_score: float, best_profile: Dictionary)

# --------------------------------------------------
# ENTRY POINT
# --------------------------------------------------

func start(iterations: int = 50, seeds_per_run: int = 20) -> void:
	_seeds_per_run = seeds_per_run
	_running = true
	_iteration = 0
	_best_score = -99999.0
	_best_profile = _profile_to_dict(BattleTuningProfile.get_instance())

	DebugLogger.log("event:battle_autotuner_start", {
		"iterations": iterations, "seeds_per_run": seeds_per_run,
		"knobs": KNOB_SPACE.size()
	})

	# Baseline
	var baseline_score: float = _evaluate(BattleTuningProfile.get_instance())
	_best_score = baseline_score
	DebugLogger.log("event:battle_autotuner_baseline", {"score": baseline_score})

	for i in range(iterations):
		if not _running:
			break
		_iteration = i + 1

		# Partial restart every RESTART_INTERVAL iterations
		# Perturbs 3 random knobs from best known profile instead of full reset
		# Escapes local optima without losing all progress
		var candidate: BattleTuningProfile
		if _iteration % RESTART_INTERVAL == 0:
			candidate = _perturb_profile(_best_profile, 3)
			DebugLogger.log("event:battle_autotuner_restart", {"iteration": _iteration})
		else:
			# Hill climb: mutate one random knob from best known
			candidate = _mutate_profile(_best_profile)

		var score: float = _evaluate(candidate)

		if score > _best_score:
			_best_score = score
			_best_profile = _profile_to_dict(candidate)
			DebugLogger.log("event:battle_autotuner_improvement", {
				"iteration": _iteration, "score": score,
				"profile": _best_profile
			})

		emit_signal("tuning_progress", _iteration, _best_score, _best_profile)

		# Yield every 10 iterations to avoid freezing
		if _iteration % 10 == 0:
			await get_tree().process_frame

	DebugLogger.log("event:battle_autotuner_complete", {
		"best_score": _best_score, "best_profile": _best_profile,
		"iterations": _iteration
	})
	emit_signal("tuning_complete", _best_score, _best_profile)
	_running = false

func stop() -> void:
	_running = false

# --------------------------------------------------
# EVALUATION
# --------------------------------------------------

func _evaluate(profile: BattleTuningProfile) -> float:
	BattleTuningProfile._instance = profile
	var results: Dictionary = BattleLab.run_full_suite(_seeds_per_run)
	return BattleLab.score_results(results, profile)

# --------------------------------------------------
# MUTATION
# --------------------------------------------------

func _mutate_profile(base: Dictionary) -> BattleTuningProfile:
	var p: BattleTuningProfile = BattleTuningProfile.new()
	# Copy base
	for key in base.keys():
		if key in p:
			p.set(key, base[key])
	# Mutate one random knob
	var knob: Array = KNOB_SPACE[randi() % KNOB_SPACE.size()]
	var knob_name: String = str(knob[0])
	var knob_min: float = float(knob[1])
	var knob_max: float = float(knob[2])
	var knob_step: float = float(knob[3])
	var current: float = float(p.get(knob_name))
	# Move one step in either direction
	var delta: float = knob_step * (1 if randf() > 0.5 else -1)
	p.set(knob_name, clampf(current + delta, knob_min, knob_max))
	return p


func _random_profile() -> BattleTuningProfile:
	var p: BattleTuningProfile = BattleTuningProfile.new()
	for knob in KNOB_SPACE:
		var knob_name: String = str(knob[0])
		var knob_min: float = float(knob[1])
		var knob_max: float = float(knob[2])
		var knob_step: float = float(knob[3])
		var steps: int = int((knob_max - knob_min) / knob_step)
		var random_val: float = knob_min + float(randi() % (steps + 1)) * knob_step
		p.set(knob_name, clampf(random_val, knob_min, knob_max))
	return p


# Perturbs N random knobs by multiple steps from best known profile
# Gentler than full reset — keeps good knobs, shakes up stuck ones
func _perturb_profile(base: Dictionary, knob_count: int) -> BattleTuningProfile:
	var p: BattleTuningProfile = BattleTuningProfile.new()
	for key in base.keys():
		if key in p:
			p.set(key, base[key])
	# Shuffle knob indices and pick knob_count of them
	var indices: Array = []
	for i in range(KNOB_SPACE.size()):
		indices.append(i)
	for i in range(indices.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp
	for i in range(mini(knob_count, indices.size())):
		var knob: Array = KNOB_SPACE[indices[i]]
		var knob_name: String = str(knob[0])
		var knob_min: float = float(knob[1])
		var knob_max: float = float(knob[2])
		var knob_step: float = float(knob[3])
		var current: float = float(p.get(knob_name))
		# Move 2-4 steps in a random direction for stronger perturbation
		var steps: int = 2 + randi() % 3
		var delta: float = knob_step * float(steps) * (1 if randf() > 0.5 else -1)
		p.set(knob_name, clampf(current + delta, knob_min, knob_max))
	return p

# --------------------------------------------------
# HELPERS
# --------------------------------------------------

func _profile_to_dict(p: BattleTuningProfile) -> Dictionary:
	var d: Dictionary = {}
	for knob in KNOB_SPACE:
		var name: String = str(knob[0])
		d[name] = p.get(name)
	return d

func apply_best_profile() -> void:
	if _best_profile.is_empty():
		return
	var p: BattleTuningProfile = BattleTuningProfile.get_instance()
	for key in _best_profile.keys():
		if key in p:
			p.set(key, _best_profile[key])
	DebugLogger.log("event:battle_autotuner_applied", {"profile": _best_profile})
