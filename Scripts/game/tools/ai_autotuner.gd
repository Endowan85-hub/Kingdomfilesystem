# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: AI AutoTuner
#
# Role:
# Runs repeated AI Lab simulations, evaluates scorecard
# metrics, mutates tuning profile parameters, and searches
# for a profile that meets campaign AI performance goals.
#
# Allowed Interactions:
# - AIBalanceLab (run simulations, read metrics)
# - AITuningProfile (read/mutate tuning knobs)
# - DebugLogger (progress logging)
# - FileAccess (checkpoint and output files)
#
# Forbidden Responsibilities:
# - Must not modify GameState directly
# - Must not queue orders
# - Must not modify planner logic or code
# - Must not touch map generation or combat resolution
#
# Game Phase:
# External simulation tool (outside main turn loop)
#
# Safe knobs mutated:
#   attack_pwin_offset, attack_score_mult, reserve_floor_mult,
#   shield_floor_mult, source_exposure_mult, hold_value_mult,
#   attrition_floor_mult, econ_reserve_guard_mult,
#   war_pressure_bonus_mult, post_neutral_war_bonus_mult,
#   surplus_war_chest_mult, surplus_attack_pwin_bonus,
#   anti_stalemate_month, anti_stalemate_pwin_bonus,
#   anti_stalemate_attack_score_mult, faction_war_pwin_bonus,
#   faction_war_attack_score_mult
#
# Output files:
#   user://ai_autotune_best_profile.json
#   user://ai_autotune_history.json
#   user://ai_autotune_report.txt
#   user://ai_autotune_checkpoint.json  (crash-safe resume)
# ==================================================

class_name AIAutoTuner
extends RefCounted

const AIBalanceLabScript    = preload("res://Scripts/game/tools/ai_balance_lab.gd")
const AITuningProfileScript = preload("res://Scripts/game/tools/ai_tuning_profile.gd")

# --------------------------------------------------
# Output paths
# --------------------------------------------------
const PATH_BEST_PROFILE : String = "user://ai_autotune_best_profile.json"
const PATH_HISTORY      : String = "user://ai_autotune_history.json"
const PATH_REPORT       : String = "user://ai_autotune_report.txt"
const PATH_CHECKPOINT   : String = "user://ai_autotune_checkpoint.json"

# --------------------------------------------------
# Default run parameters
# --------------------------------------------------
const DEFAULT_MONTHS          : int   = 72
const DEFAULT_SEEDS           : int   = 12
const DEFAULT_MAX_ITERATIONS  : int   = 40
const DEFAULT_STALL_LIMIT     : int   = 8
const DEFAULT_PHASE1_CANDIDATES: int  = 14   # broad random
const DEFAULT_PHASE2_CANDIDATES: int  = 10   # focused near best
const DEFAULT_PHASE3_CANDIDATES: int  = 8    # small nudges
const VALIDATION_SEEDS        : int   = 12
const VALIDATION_SEED_OFFSET  : int   = 99991  # different seed set

# --------------------------------------------------
# Goal thresholds (all must pass for STOP)
# --------------------------------------------------
const GOAL_ATTACKS_PER_MONTH    : float = 1.5
const GOAL_CAPTURES_PER_MONTH   : float = 0.5
const GOAL_PASSIVE_RATE_MAX     : float = 0.15   # ≤ 15% of months passive
const GOAL_COLLAPSE_RATE_MAX    : float = 0.10
const GOAL_FIRST_WAR_MONTH_MAX  : float = 30.0
const GOAL_UNIQUE_ATTACKERS_MIN : int   = 12
const GOAL_LEADER_DENSITY_MIN   : float = 1.2
const GOAL_LEADER_DENSITY_MAX   : float = 1.8
const GOAL_BORDER_BACKUP_MIN    : float = 0.60
const GOAL_FRONTLINE_OVL_MAX    : float = 0.70

# --------------------------------------------------
# Mutation bounds for each safe knob
# [field_name, min, max, step_broad, step_narrow]
# step_broad  = phase 1 random step size
# step_narrow = phase 3 fine-tune step size
# --------------------------------------------------
const KNOB_BOUNDS: Array = [
	# field                           min     max    broad  narrow
	["attack_pwin_offset",           -0.25,   0.25,  0.06,  0.02],
	["attack_score_mult",             0.50,   1.75,  0.12,  0.04],
	["reserve_floor_mult",            0.50,   1.50,  0.10,  0.03],
	["shield_floor_mult",             0.50,   1.50,  0.10,  0.03],
	["source_exposure_mult",          0.50,   2.00,  0.15,  0.05],
	["hold_value_mult",               0.10,   3.00,  0.25,  0.08],
	["attrition_floor_mult",          0.00,   2.00,  0.15,  0.05],
	["econ_reserve_guard_mult",       0.25,   2.00,  0.15,  0.05],
	["war_pressure_bonus_mult",       0.00,   3.00,  0.20,  0.07],
	["post_neutral_war_bonus_mult",   0.00,   3.00,  0.20,  0.07],
	["surplus_war_chest_mult",        1.00,   3.00,  0.15,  0.05],
	["surplus_attack_pwin_bonus",     0.00,   0.20,  0.03,  0.01],
	["anti_stalemate_pwin_bonus",     0.00,   0.20,  0.03,  0.01],
	["anti_stalemate_attack_score_mult", 1.00, 2.00, 0.12,  0.04],
	["faction_war_pwin_bonus",        0.00,   0.20,  0.03,  0.01],
	["faction_war_attack_score_mult", 1.00,   2.00,  0.12,  0.04],
]

# anti_stalemate_month is int — handled separately
const ANTI_STALEMATE_MONTH_MIN  : int = 6
const ANTI_STALEMATE_MONTH_MAX  : int = 30
const ANTI_STALEMATE_MONTH_STEP : int = 2

# --------------------------------------------------
# State
# --------------------------------------------------
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lab: AIBalanceLab = null
var _settings: MapSettings = null
var _render_host: Node = null
var _months: int = DEFAULT_MONTHS
var _seeds: int = DEFAULT_SEEDS
var _max_iterations: int = DEFAULT_MAX_ITERATIONS
var _stall_limit: int = DEFAULT_STALL_LIMIT
var _start_time_usec: int = 0

# Progress signal — host can connect to receive live updates
signal progress_updated(payload: Dictionary)


# ==================================================
# PUBLIC API
# ==================================================

func run_async(host: Node,
		settings: MapSettings,
		base_profile: AITuningProfile = null,
		months: int = DEFAULT_MONTHS,
		seeds: int = DEFAULT_SEEDS,
		max_iterations: int = DEFAULT_MAX_ITERATIONS,
		stall_limit: int = DEFAULT_STALL_LIMIT,
		render_host: Node = null) -> Dictionary:
	# --------------------------------------------------
	# Main async entry point.
	# Resumes from checkpoint if one exists.
	# Returns final result dictionary.
	# --------------------------------------------------
	_lab      = AIBalanceLabScript.new()
	_settings = settings
	_months   = months
	_seeds    = seeds
	_max_iterations = max_iterations
	_stall_limit    = stall_limit
	_rng.randomize()
	_start_time_usec = Time.get_ticks_usec()
	_render_host = render_host

	DebugLogger.log("ai_autotune_start", {
		"months": months, "seeds": seeds,
		"max_iterations": max_iterations, "stall_limit": stall_limit
	})

	# Try to resume from checkpoint
	var resume: Dictionary = _load_checkpoint()
	var start_iteration: int = 0
	var best_profile: AITuningProfile
	var best_score: float
	var best_metrics: Dictionary = {}
	var history: Array = []

	if not resume.is_empty():
		best_profile = _profile_from_dict(resume.get("best_profile", {}))
		best_score   = float(resume.get("best_score", -1e9))
		history      = resume.get("history", []) as Array
		start_iteration = int(resume.get("next_iteration", 1))
		DebugLogger.log("ai_autotune_resume", {"iteration": start_iteration, "score": best_score})
		# Try to recover metrics from last history entry
		if not history.is_empty():
			var last_h: Dictionary = history[history.size()-1] as Dictionary
			best_metrics = last_h.get("metrics", {}) as Dictionary
		_emit_progress(host, "resumed", start_iteration, best_score, best_profile)
	else:
		# Fresh start — baseline evaluation
		best_profile = _make_profile(base_profile)
		_emit_progress(host, "baseline_start", 0, 0.0, best_profile)
		var baseline_report: Dictionary = await _evaluate(host, best_profile, 0, -1)
		best_score   = float(baseline_report.get("score", -1e9))
		best_metrics = baseline_report.get("metrics", {}) as Dictionary
		history.append(_history_entry(0, best_score, best_profile, baseline_report))
		_save_checkpoint(0, best_score, best_profile, history, 1)
		_emit_progress(host, "baseline_complete", 0, best_score, best_profile, {"metrics": best_metrics})
		await _yield(host)

	var stall_count: int = 0
	var phase: int = 1  # 1=broad, 2=focused, 3=narrow

	# --------------------------------------------------
	# Main search loop
	# --------------------------------------------------
	for iteration in range(start_iteration, max_iterations + 1):
		if _goals_met(_last_metrics(history)):
			DebugLogger.log("ai_autotune_goals_met_early", {"iteration": iteration})
			break

		# Update phase based on stall count
		if stall_count == 0:
			phase = 1
		elif stall_count < 3:
			phase = 2
		else:
			phase = 3

		var candidates: Array = _build_candidates(best_profile, phase)
		var improved: bool = false

		for ci in range(candidates.size()):
			var candidate: AITuningProfile = candidates[ci] as AITuningProfile
			var report: Dictionary = await _evaluate(host, candidate, iteration, ci)
			var score: float = float(report.get("score", -1e9))

			var cand_metrics: Dictionary = report.get("metrics", {}) as Dictionary
			_emit_progress(host, "candidate_evaluated", iteration, score, candidate, {
				"candidate_index": ci,
				"candidate_count": candidates.size(),
				"phase": phase,
				"best_score": best_score,
				"metrics": cand_metrics,
			})

			if score > best_score:
				best_score   = score
				best_profile = candidate.duplicate_profile()
				best_metrics = report.get("metrics", best_metrics) as Dictionary
				improved      = true
				_save_checkpoint(iteration, best_score, best_profile, history, iteration + 1)

			await _yield(host)

		if improved:
			stall_count = 0
		else:
			stall_count += 1

		history.append(_history_entry(iteration, best_score, best_profile, {}))
		_save_checkpoint(iteration, best_score, best_profile, history, iteration + 1)
		_emit_progress(host, "iteration_complete", iteration, best_score, best_profile, {
			"stall_count": stall_count, "phase": phase, "metrics": best_metrics
		})

		DebugLogger.log("ai_autotune_iteration", {
			"iteration": iteration, "score": best_score,
			"stall_count": stall_count, "phase": phase
		})

		if stall_count >= stall_limit:
			DebugLogger.log("ai_autotune_stall_stop", {"iteration": iteration})
			break

		await _yield(host)

	# --------------------------------------------------
	# Validation pass — different seed set
	# --------------------------------------------------
	_emit_progress(host, "validation_start", -1, best_score, best_profile)
	var validation_report: Dictionary = await _evaluate_validation(host, best_profile)
	var validation_passed: bool = _goals_met(validation_report.get("metrics", {}))

	# --------------------------------------------------
	# Write outputs
	# --------------------------------------------------
	var final_result: Dictionary = {
		"best_profile":       best_profile.to_dictionary(),
		"best_score":         best_score,
		"validation_score":   float(validation_report.get("score", 0.0)),
		"validation_passed":  validation_passed,
		"validation_metrics": validation_report.get("metrics", {}),
		"goals_met":          _goals_met(_last_metrics(history)),
		"iterations_run":     history.size() - 1,
		"history":            history,
		"elapsed_seconds":    float(Time.get_ticks_usec() - _start_time_usec) / 1_000_000.0,
	}

	_write_outputs(final_result)
	_delete_checkpoint()

	_emit_progress(host, "complete", -1, best_score, best_profile, {
		"validation_passed": validation_passed,
		"goals_met": final_result["goals_met"],
	})

	DebugLogger.log("ai_autotune_complete", {
		"score": best_score,
		"validation_passed": validation_passed,
		"goals_met": final_result["goals_met"],
		"iterations": final_result["iterations_run"],
	})

	return final_result


# ==================================================
# GOAL EVALUATION
# ==================================================

func _goals_met(metrics: Dictionary) -> bool:
	if metrics.is_empty():
		return false
	var months: float       = float(_months)
	var atk_per_mo: float   = float(metrics.get("avg_attacks_per_month", 0.0))
	var cap_per_mo: float   = float(metrics.get("avg_captures_per_month", 0.0))
	var passive_mo: float   = float(metrics.get("avg_passive_months", 0.0))
	var collapse: float     = float(metrics.get("economic_collapse_run_rate", 1.0))
	var first_war: float    = float(metrics.get("avg_first_attack_month", 99.0))
	var unique_atk: int     = int(metrics.get("unique_attacker_count", 0))
	var density: float      = float(metrics.get("avg_leader_density", 0.0))
	var border_bk: float    = float(metrics.get("avg_border_backup_coverage", 0.0))
	var frontline: float    = float(metrics.get("avg_frontline_overload", 1.0))
	var passive_rate: float = passive_mo / maxf(1.0, months)

	return (
		atk_per_mo  >= GOAL_ATTACKS_PER_MONTH    and
		cap_per_mo  >= GOAL_CAPTURES_PER_MONTH   and
		passive_rate <= GOAL_PASSIVE_RATE_MAX     and
		collapse     <= GOAL_COLLAPSE_RATE_MAX    and
		first_war    <= GOAL_FIRST_WAR_MONTH_MAX  and
		unique_atk   >= GOAL_UNIQUE_ATTACKERS_MIN and
		density      >= GOAL_LEADER_DENSITY_MIN   and
		density      <= GOAL_LEADER_DENSITY_MAX   and
		border_bk    >= GOAL_BORDER_BACKUP_MIN    and
		frontline    <= GOAL_FRONTLINE_OVL_MAX
	)


func _score_goals(metrics: Dictionary) -> Dictionary:
	# Returns per-goal pass/fail for report
	if metrics.is_empty():
		return {}
	var months: float       = float(_months)
	var passive_mo: float   = float(metrics.get("avg_passive_months", 0.0))
	var passive_rate: float = passive_mo / maxf(1.0, months)
	return {
		"attacks_per_month":     float(metrics.get("avg_attacks_per_month", 0.0)) >= GOAL_ATTACKS_PER_MONTH,
		"captures_per_month":    float(metrics.get("avg_captures_per_month", 0.0)) >= GOAL_CAPTURES_PER_MONTH,
		"passive_rate":          passive_rate <= GOAL_PASSIVE_RATE_MAX,
		"collapse_rate":         float(metrics.get("economic_collapse_run_rate", 1.0)) <= GOAL_COLLAPSE_RATE_MAX,
		"first_war_month":       float(metrics.get("avg_first_attack_month", 99.0)) <= GOAL_FIRST_WAR_MONTH_MAX,
		"unique_attackers":      int(metrics.get("unique_attacker_count", 0)) >= GOAL_UNIQUE_ATTACKERS_MIN,
		"leader_density":        (float(metrics.get("avg_leader_density", 0.0)) >= GOAL_LEADER_DENSITY_MIN and
								  float(metrics.get("avg_leader_density", 0.0)) <= GOAL_LEADER_DENSITY_MAX),
		"border_backup":         float(metrics.get("avg_border_backup_coverage", 0.0)) >= GOAL_BORDER_BACKUP_MIN,
		"frontline_overload":    float(metrics.get("avg_frontline_overload", 1.0)) <= GOAL_FRONTLINE_OVL_MAX,
	}


# ==================================================
# CANDIDATE GENERATION
# ==================================================

func _build_candidates(base: AITuningProfile, phase: int) -> Array:
	var candidates: Array = []
	var count: int = DEFAULT_PHASE1_CANDIDATES
	if phase == 2:
		count = DEFAULT_PHASE2_CANDIDATES
	elif phase == 3:
		count = DEFAULT_PHASE3_CANDIDATES

	# Always include base (no change) as a candidate
	candidates.append(base.duplicate_profile())

	for _i in range(count - 1):
		var candidate: AITuningProfile = base.duplicate_profile()
		_mutate(candidate, phase)
		candidates.append(candidate)

	return candidates


func _mutate(profile: AITuningProfile, phase: int) -> void:
	# Decide how many knobs to perturb per candidate
	var knobs_to_touch: int = 1
	if phase == 1:
		knobs_to_touch = _rng.randi_range(1, 3)
	elif phase == 2:
		knobs_to_touch = _rng.randi_range(1, 2)
	else:
		knobs_to_touch = 1

	# Shuffle knob list and pick the first N
	var shuffled: Array = KNOB_BOUNDS.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	for k in range(mini(knobs_to_touch, shuffled.size())):
		var knob: Array = shuffled[k] as Array
		var field:  String = str(knob[0])
		var lo:     float  = float(knob[1])
		var hi:     float  = float(knob[2])
		var step_b: float  = float(knob[3])
		var step_n: float  = float(knob[4])
		var step:   float  = step_b if phase == 1 else step_n
		var sign:   float  = 1.0 if _rng.randf() > 0.5 else -1.0
		var delta:  float  = step * sign * _rng.randf_range(0.5, 1.0)
		var current: float = float(profile.get(field))
		var new_val: float = clampf(current + delta, lo, hi)
		profile.set(field, new_val)

	# Handle anti_stalemate_month (int) separately
	if _rng.randf() < 0.30:
		var sign: int  = 1 if _rng.randf() > 0.5 else -1
		var step: int  = ANTI_STALEMATE_MONTH_STEP if phase == 1 else 1
		var cur:  int  = int(profile.anti_stalemate_month)
		profile.anti_stalemate_month = clampi(cur + sign * step,
			ANTI_STALEMATE_MONTH_MIN, ANTI_STALEMATE_MONTH_MAX)

	profile.sanitize()


# ==================================================
# LAB EVALUATION
# ==================================================

func _evaluate(host: Node, profile: AITuningProfile,
		iteration: int, candidate_index: int) -> Dictionary:
	if _lab == null or _settings == null:
		return {}
	# Use render_host as the lab host so _on_ai_lab_progress fires on the view
	# giving live map preview. Fall back to host (UI) if no render_host set.
	var lab_host: Node = _render_host if (_render_host != null and is_instance_valid(_render_host)) else host
	return await _lab.run_autotune_async(lab_host, _settings, _months,
		0, _seeds, profile)


func _evaluate_validation(host: Node, profile: AITuningProfile) -> Dictionary:
	if _lab == null or _settings == null:
		return {}
	var val_settings: MapSettings = _settings.duplicate(true) as MapSettings
	if val_settings == null:
		val_settings = _settings
	val_settings.seed = int(_settings.seed) + VALIDATION_SEED_OFFSET
	var lab_host: Node = _render_host if (_render_host != null and is_instance_valid(_render_host)) else host
	return await _lab.run_autotune_async(lab_host, val_settings, _months,
		0, VALIDATION_SEEDS, profile)


# ==================================================
# FILE I/O
# ==================================================

func _save_checkpoint(iteration: int, score: float,
		profile: AITuningProfile, history: Array, next_iteration: int) -> void:
	var data: Dictionary = {
		"iteration":      iteration,
		"best_score":     score,
		"best_profile":   profile.to_dictionary(),
		"history":        history,
		"next_iteration": next_iteration,
		"timestamp":      Time.get_ticks_msec(),
	}
	var f := FileAccess.open(PATH_CHECKPOINT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


func _load_checkpoint() -> Dictionary:
	if not FileAccess.file_exists(PATH_CHECKPOINT):
		return {}
	var f := FileAccess.open(PATH_CHECKPOINT, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}
	return result as Dictionary


func _delete_checkpoint() -> void:
	if FileAccess.file_exists(PATH_CHECKPOINT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH_CHECKPOINT))


func _write_outputs(result: Dictionary) -> void:
	# Best profile JSON
	var pf := FileAccess.open(PATH_BEST_PROFILE, FileAccess.WRITE)
	if pf != null:
		pf.store_string(JSON.stringify(result.get("best_profile", {}), "\t"))
		pf.close()

	# History JSON
	var hf := FileAccess.open(PATH_HISTORY, FileAccess.WRITE)
	if hf != null:
		hf.store_string(JSON.stringify(result.get("history", []), "\t"))
		hf.close()

	# Human-readable report
	var rf := FileAccess.open(PATH_REPORT, FileAccess.WRITE)
	if rf != null:
		rf.store_string(_build_report_text(result))
		rf.close()

	DebugLogger.log("ai_autotune_outputs_written", {
		"best_profile": PATH_BEST_PROFILE,
		"history": PATH_HISTORY,
		"report": PATH_REPORT,
	})


func _build_report_text(result: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("KINGDOM AI AUTOTUNE REPORT")
	lines.append("Generated: %s" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("RESULT: %s" % ("GOALS MET" if bool(result.get("goals_met", false)) else "GOALS NOT MET"))
	lines.append("Validation: %s" % ("PASSED" if bool(result.get("validation_passed", false)) else "FAILED"))
	lines.append("Best Score: %.2f" % float(result.get("best_score", 0.0)))
	lines.append("Validation Score: %.2f" % float(result.get("validation_score", 0.0)))
	lines.append("Iterations run: %d" % int(result.get("iterations_run", 0)))
	lines.append("Elapsed: %.1f seconds" % float(result.get("elapsed_seconds", 0.0)))
	lines.append("")
	lines.append("--- GOAL CHECK ---")
	var val_metrics: Dictionary = result.get("validation_metrics", {}) as Dictionary
	var goal_results: Dictionary = _score_goals(val_metrics)
	var goal_labels: Dictionary = {
		"attacks_per_month":   "Attacks/month >= %.1f" % GOAL_ATTACKS_PER_MONTH,
		"captures_per_month":  "Captures/month >= %.1f" % GOAL_CAPTURES_PER_MONTH,
		"passive_rate":        "Passive rate <= %.0f%%" % (GOAL_PASSIVE_RATE_MAX * 100),
		"collapse_rate":       "Collapse rate <= %.0f%%" % (GOAL_COLLAPSE_RATE_MAX * 100),
		"first_war_month":     "First war month <= %.0f" % GOAL_FIRST_WAR_MONTH_MAX,
		"unique_attackers":    "Unique attackers >= %d" % GOAL_UNIQUE_ATTACKERS_MIN,
		"leader_density":      "Leader density %.1f–%.1f" % [GOAL_LEADER_DENSITY_MIN, GOAL_LEADER_DENSITY_MAX],
		"border_backup":       "Border backup >= %.2f" % GOAL_BORDER_BACKUP_MIN,
		"frontline_overload":  "Frontline overload <= %.2f" % GOAL_FRONTLINE_OVL_MAX,
	}
	for key in goal_labels.keys():
		var passed: bool = bool(goal_results.get(key, false))
		lines.append("  %s  %s" % ["[PASS]" if passed else "[FAIL]", str(goal_labels[key])])
	lines.append("")
	lines.append("--- VALIDATION METRICS ---")
	for key in val_metrics.keys():
		lines.append("  %s: %s" % [str(key), str(val_metrics[key])])
	lines.append("")
	lines.append("--- BEST PROFILE (Godot-ready values) ---")
	var profile_dict: Dictionary = result.get("best_profile", {}) as Dictionary
	for key in profile_dict.keys():
		var val = profile_dict[key]
		if val is float:
			lines.append("  %s = %.4f" % [str(key), float(val)])
		else:
			lines.append("  %s = %s" % [str(key), str(val)])
	lines.append("")
	lines.append("--- SCORE HISTORY ---")
	for entry_value in (result.get("history", []) as Array):
		var entry: Dictionary = entry_value as Dictionary
		lines.append("  iter=%d  score=%.2f  %s" % [
			int(entry.get("iteration", 0)),
			float(entry.get("score", 0.0)),
			str(entry.get("summary", ""))
		])
	return "\n".join(lines)


# ==================================================
# HELPERS
# ==================================================

func _make_profile(base: AITuningProfile) -> AITuningProfile:
	if base != null:
		return base.duplicate_profile()
	var p: AITuningProfile = AITuningProfileScript.new()
	p.sanitize()
	return p


func _profile_from_dict(d: Dictionary) -> AITuningProfile:
	var p: AITuningProfile = AITuningProfileScript.new()
	p.apply_dictionary(d)
	return p


func _history_entry(iteration: int, score: float,
		profile: AITuningProfile, report: Dictionary) -> Dictionary:
	return {
		"iteration": iteration,
		"score":     score,
		"profile":   profile.to_dictionary(),
		"summary":   str(report.get("summary_text", "")),
		"metrics":   report.get("metrics", {}) as Dictionary,
	}


func _last_metrics(history: Array) -> Dictionary:
	if history.is_empty():
		return {}
	var last: Dictionary = history[history.size() - 1] as Dictionary
	return last.get("metrics", {}) as Dictionary


func _emit_progress(host: Node, status: String,
		iteration: int, score: float,
		profile: AITuningProfile, extra: Dictionary = {}) -> void:
	var payload: Dictionary = {
		"status":    status,
		"iteration": iteration,
		"score":     score,
		"profile":   profile.to_dictionary() if profile != null else {},
	}
	for key in extra.keys():
		payload[key] = extra[key]
	# Emit signal — UI receives this
	progress_updated.emit(payload)
	# Call UI host directly if it handles autotune progress
	if host != null and is_instance_valid(host) and host.has_method("_on_autotune_progress"):
		host.call("_on_autotune_progress", payload)
	# Also notify render host (view) for autotune-specific status text
	if _render_host != null and is_instance_valid(_render_host) and _render_host != host:
		if _render_host.has_method("_on_autotune_progress"):
			_render_host.call("_on_autotune_progress", payload)


func _yield(host: Node) -> void:
	if host != null and is_instance_valid(host):
		await host.get_tree().process_frame
