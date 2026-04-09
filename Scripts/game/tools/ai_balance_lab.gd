class_name AIBalanceLab
extends RefCounted

# --------------------------------------------------
# Phase 10 Metrics
# --------------------------------------------------
var metrics := {
	"attacks": 0,
	"captures": 0,
	"months": 0,
	"passive_months": 0,
	"faction_eliminations": 0,
	"border_backups": 0
}

var _attacks_this_month: int = 0

# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: AIBalanceLab
#
# Role:
# Runs repeatable simulation batches against safe AI tuning profiles,
# compares outcomes, and writes reports for human review.
# Version 3 adds runaway-empire detection, economic-collapse detection, and frontier pressure mapping.
# ==================================================






const MapGeneratorScript = preload("res://Scripts/map/map_generator.gd")
const GameStateScript = preload("res://Scripts/game/game_state.gd")
const TurnManagerScript = preload("res://Scripts/game/turn_manager.gd")
const AITuningProfileScript = preload("res://Scripts/game/tools/ai_tuning_profile.gd")

const HUMAN_DISABLED_ID: int = -999
const DEFAULT_MONTHS: int = 36
const DEFAULT_ITERATIONS: int = 8
const DEFAULT_SEED_COUNT: int = 12
const REPORT_JSON_PATH: String = "user://ai_lab_report.json"
const REPORT_TEXT_PATH: String = "user://ai_lab_report.txt"

func run_autotune(settings: MapSettings,
		months: int = DEFAULT_MONTHS,
		iterations: int = DEFAULT_ITERATIONS,
		seed_count: int = DEFAULT_SEED_COUNT,
		base_profile: AITuningProfile = null) -> Dictionary:
	if settings == null:
		return {}
	var best_profile: AITuningProfile = _make_base_profile(base_profile)
	var best_report: Dictionary = await _evaluate_profile(settings, best_profile, months, seed_count)
	var history: Array = [{
		"iteration": 0,
		"score": float(best_report.get("score", -1000000000.0)),
		"profile": best_profile.to_dictionary(),
		"summary": best_report.get("summary_text", "baseline")
	}]
	for iteration in range(1, maxi(1, iterations) + 1):
		var candidates: Array = _build_iteration_candidates(best_profile)
		var iteration_best_score: float = float(best_report.get("score", -1000000000.0))
		var iteration_best_profile: AITuningProfile = best_profile
		var iteration_best_report: Dictionary = best_report
		for candidate_value in candidates:
			var candidate: AITuningProfile = candidate_value as AITuningProfile
			if candidate == null:
				continue
			var report: Dictionary = await _evaluate_profile(settings, candidate, months, seed_count)
			var score: float = float(report.get("score", -1000000000.0))
			if score > iteration_best_score:
				iteration_best_score = score
				iteration_best_profile = candidate.duplicate_profile()
				iteration_best_report = report
		best_profile = iteration_best_profile.duplicate_profile()
		best_report = iteration_best_report
		history.append({
			"iteration": iteration,
			"score": float(best_report.get("score", -1000000000.0)),
			"profile": best_profile.to_dictionary(),
			"summary": best_report.get("summary_text", "")
		})
	var final_report: Dictionary = {
		"best_profile": best_profile.to_dictionary(),
		"score": float(best_report.get("score", 0.0)),
		"metrics": best_report.get("metrics", {}),
		"findings": best_report.get("findings", []),
		"summary_text": best_report.get("summary_text", ""),
		"timeline_snapshots": best_report.get("timeline_snapshots", []),
		"history": history,
		"months": months,
		"seed_count": seed_count,
	}
	_write_report_files(final_report)
	DebugLogger.log("ai_lab_complete", final_report)
	return final_report


func run_autotune_async(host: Node, settings: MapSettings,
		months: int = DEFAULT_MONTHS,
		iterations: int = DEFAULT_ITERATIONS,
		seed_count: int = DEFAULT_SEED_COUNT,
		base_profile: AITuningProfile = null) -> Dictionary:
	if settings == null:
		return {}
	DebugLogger.log("ai_lab_start", {
		"months": months,
		"iterations": iterations,
		"seed_count": seed_count,
	})
	var best_profile: AITuningProfile = _make_base_profile(base_profile)
	var best_report: Dictionary = await _evaluate_profile_async(host, settings, best_profile, months, seed_count, 0, 0)
	var history: Array = [{
		"iteration": 0,
		"score": float(best_report.get("score", -1000000000.0)),
		"profile": best_profile.to_dictionary(),
		"summary": best_report.get("summary_text", "baseline")
	}]
	_write_checkpoint_report({
		"status": "baseline_complete",
		"best_profile": best_profile.to_dictionary(),
		"score": float(best_report.get("score", 0.0)),
		"metrics": best_report.get("metrics", {}),
		"findings": best_report.get("findings", []),
		"summary_text": best_report.get("summary_text", ""),
		"timeline_snapshots": best_report.get("timeline_snapshots", []),
		"history": history,
		"months": months,
		"seed_count": seed_count,
	})
	await _yield_to_host(host)

	for iteration in range(1, maxi(1, iterations) + 1):
		var candidates: Array = _build_iteration_candidates(best_profile)
		var iteration_best_score: float = float(best_report.get("score", -1000000000.0))
		var iteration_best_profile: AITuningProfile = best_profile
		var iteration_best_report: Dictionary = best_report
		for candidate_index in range(candidates.size()):
			var candidate: AITuningProfile = candidates[candidate_index] as AITuningProfile
			if candidate == null:
				continue
			var report: Dictionary = await _evaluate_profile_async(host, settings, candidate, months, seed_count, iteration, candidate_index)
			var score: float = float(report.get("score", -1000000000.0))
			if score > iteration_best_score:
				iteration_best_score = score
				iteration_best_profile = candidate.duplicate_profile()
				iteration_best_report = report
			_write_checkpoint_report({
				"status": "iteration_progress",
				"iteration": iteration,
				"candidate_index": candidate_index,
				"best_profile": iteration_best_profile.to_dictionary(),
				"score": float(iteration_best_report.get("score", 0.0)),
				"metrics": iteration_best_report.get("metrics", {}),
				"findings": iteration_best_report.get("findings", []),
				"summary_text": iteration_best_report.get("summary_text", ""),
				"months": months,
				"seed_count": seed_count,
			})
			await _yield_to_host(host)
		best_profile = iteration_best_profile.duplicate_profile()
		best_report = iteration_best_report
		history.append({
			"iteration": iteration,
			"score": float(best_report.get("score", -1000000000.0)),
			"profile": best_profile.to_dictionary(),
			"summary": best_report.get("summary_text", "")
		})
		DebugLogger.log("ai_lab_iteration_complete", {
			"iteration": iteration,
			"score": float(best_report.get("score", 0.0)),
		})
		await _yield_to_host(host)

	var final_report: Dictionary = {
		"status": "complete",
		"best_profile": best_profile.to_dictionary(),
		"score": float(best_report.get("score", 0.0)),
		"metrics": best_report.get("metrics", {}),
		"findings": best_report.get("findings", []),
		"summary_text": best_report.get("summary_text", ""),
		"balance_score": best_report.get("balance_score", {}),
		"history": history,
		"months": months,
		"seed_count": seed_count,
	}
	_write_report_files(final_report)
	DebugLogger.log("ai_lab_report_written", {
		"json_path": REPORT_JSON_PATH,
		"text_path": REPORT_TEXT_PATH,
	})
	DebugLogger.log("ai_lab_complete", final_report)
	return final_report


func _evaluate_profile_async(host: Node, settings: MapSettings, profile: AITuningProfile,
		months: int, seed_count: int, iteration: int, candidate_index: int) -> Dictionary:
	var aggregate: Dictionary = _make_empty_aggregate()
	for i in range(maxi(1, seed_count)):
		var run_metrics: Dictionary = await _simulate_seed_async(host, settings, profile, months, i, iteration, candidate_index, maxi(1, seed_count))
		_accumulate_run_metrics(aggregate, run_metrics, months)
		DebugLogger.log("ai_lab_seed_complete", {
			"iteration": iteration,
			"candidate_index": candidate_index,
			"seed_index": i,
			"attack_orders": int(run_metrics.get("attack_orders", 0)),
			"capture_count": int(run_metrics.get("capture_count", 0)),
			"runaway": bool(run_metrics.get("runaway_detected", false)),
			"economic_collapse": bool(run_metrics.get("economic_collapse_detected", false)),
		})
		_write_checkpoint_report({
			"status": "seed_complete",
			"iteration": iteration,
			"candidate_index": candidate_index,
			"seed_index": i,
			"partial_metrics": aggregate,
			"timeline_snapshots": aggregate.get("timeline_snapshots", []),
		})
		await _yield_to_host(host)
	return _aggregate_to_report(aggregate, profile, months)


func _aggregate_to_report(aggregate: Dictionary, profile: AITuningProfile, months: int) -> Dictionary:
	var runs: int = maxi(1, int(aggregate.get("runs", 0)))
	var avg_attacks_per_month: float = float(aggregate.get("attack_orders", 0)) / float(runs * maxi(1, months))
	var avg_captures_per_month: float = float(aggregate.get("capture_count", 0)) / float(runs * maxi(1, months))
	var avg_passive_months: float = float(aggregate.get("passive_months", 0)) / float(runs)
	var avg_alive_factions_end: float = float(aggregate.get("alive_factions_end_total", 0)) / float(runs)
	var avg_first_attack_month: float = float(aggregate.get("first_attack_month_sum", 0)) / float(runs)
	var avg_first_capture_month: float = float(aggregate.get("first_capture_month_sum", 0)) / float(runs)
	var avg_leader_density: float = float(aggregate.get("leader_density_sum", 0.0)) / float(runs)
	var avg_backup_coverage: float = float(aggregate.get("backup_coverage_sum", 0.0)) / float(runs)
	var avg_border_backup_coverage: float = float(aggregate.get("border_backup_coverage_sum", 0.0)) / float(runs)
	var unique_attacker_count: int = int((aggregate.get("unique_attackers", {}) as Dictionary).size())
	var runaway_run_rate: float = float(aggregate.get("runaway_detected_runs", 0)) / float(runs)
	var avg_runaway_months: float = float(aggregate.get("runaway_months_sum", 0)) / float(runs)
	var avg_top_empire_share_peak: float = float(aggregate.get("top_empire_share_peak_sum", 0.0)) / float(runs)
	var economic_collapse_run_rate: float = float(aggregate.get("economic_collapse_runs", 0)) / float(runs)
	var avg_collapse_months: float = float(aggregate.get("economic_collapse_months_sum", 0)) / float(runs)
	var avg_collapsed_faction_months: float = float(aggregate.get("collapsed_faction_months_sum", 0)) / float(runs)
	var avg_frontline_pressure: float = float(aggregate.get("frontline_pressure_sum", 0.0)) / float(runs)
	var avg_frontline_overload: float = float(aggregate.get("frontline_overload_sum", 0.0)) / float(runs)
	var avg_hot_front_share: float = float(aggregate.get("hot_front_share_sum", 0.0)) / float(runs)
	var avg_general_pool_size: float = float(aggregate.get("general_pool_size_sum", 0.0)) / float(runs)
	var avg_general_pool_size_start: float = float(aggregate.get("general_pool_size_start_sum", 0.0)) / float(runs)
	var avg_general_pool_size_end: float = float(aggregate.get("general_pool_size_end_sum", 0.0)) / float(runs)
	var avg_frontier_provinces_per_faction: float = float(aggregate.get("avg_frontier_provinces_per_faction_sum", 0.0)) / float(runs)
	var avg_available_leaders_per_faction: float = float(aggregate.get("avg_available_leaders_per_faction_sum", 0.0)) / float(runs)
	var avg_unused_available_leaders: float = float(aggregate.get("avg_unused_available_leaders_sum", 0.0)) / float(runs)
	var avg_attacks_vs_neutral_per_month: float = float(aggregate.get("attack_orders_vs_neutral", 0)) / float(runs * maxi(1, months))
	var avg_attacks_vs_faction_per_month: float = float(aggregate.get("attack_orders_vs_faction", 0)) / float(runs * maxi(1, months))
	var avg_passive_faction_war_months: float = float(aggregate.get("passive_faction_war_months", 0)) / float(runs)
	var frontline_pressure_by_faction_avg: Dictionary = _average_dictionary(aggregate.get("frontline_pressure_by_faction_sum", {}) as Dictionary, runs)
	var metrics: Dictionary = {
		"avg_attacks_per_month": avg_attacks_per_month,
		"avg_captures_per_month": avg_captures_per_month,
		"avg_passive_months": avg_passive_months,
		"avg_alive_factions_end": avg_alive_factions_end,
		"avg_first_attack_month": avg_first_attack_month,
		"avg_first_capture_month": avg_first_capture_month,
		"unique_attacker_count": unique_attacker_count,
		"avg_leader_density": avg_leader_density,
		"avg_backup_coverage": avg_backup_coverage,
		"avg_border_backup_coverage": avg_border_backup_coverage,
		"runaway_run_rate": runaway_run_rate,
		"avg_runaway_months": avg_runaway_months,
		"avg_top_empire_share_peak": avg_top_empire_share_peak,
		"economic_collapse_run_rate": economic_collapse_run_rate,
		"avg_collapse_months": avg_collapse_months,
		"avg_collapsed_faction_months": avg_collapsed_faction_months,
		"avg_frontline_pressure": avg_frontline_pressure,
		"avg_frontline_overload": avg_frontline_overload,
		"avg_hot_front_share": avg_hot_front_share,
		"frontline_pressure_by_faction_avg": frontline_pressure_by_faction_avg,
		"avg_general_pool_size": avg_general_pool_size,
		"avg_general_pool_size_start": avg_general_pool_size_start,
		"avg_general_pool_size_end": avg_general_pool_size_end,
		"avg_frontier_provinces_per_faction": avg_frontier_provinces_per_faction,
		"avg_available_leaders_per_faction": avg_available_leaders_per_faction,
		"avg_unused_available_leaders": avg_unused_available_leaders,
		"avg_attacks_vs_neutral_per_month": avg_attacks_vs_neutral_per_month,
		"avg_attacks_vs_faction_per_month": avg_attacks_vs_faction_per_month,
		"avg_passive_faction_war_months": avg_passive_faction_war_months,
		"runs": runs,
	}
	var score: float = 0.0
	score += avg_attacks_per_month * 80.0
	score += avg_captures_per_month * 180.0
	score += float(unique_attacker_count) * 18.0
	score += maxf(0.0, 7.0 - avg_first_attack_month) * 10.0
	score += maxf(0.0, 9.0 - avg_first_capture_month) * 12.0
	score += avg_backup_coverage * 35.0
	score += avg_border_backup_coverage * 55.0
	score += maxf(0.0, avg_leader_density - 1.15) * 30.0
	score += maxf(0.0, 0.55 - runaway_run_rate) * 90.0
	score += maxf(0.0, 0.55 - economic_collapse_run_rate) * 80.0
	score += maxf(0.0, 0.60 - avg_frontline_overload) * 50.0
	score += avg_hot_front_share * 30.0
	score -= avg_passive_months * 9.0
	score -= maxf(0.0, 2.0 - avg_attacks_per_month) * 70.0
	score -= maxf(0.0, 0.35 - avg_captures_per_month) * 160.0
	score -= maxf(0.0, 0.30 - avg_backup_coverage) * 120.0
	score -= maxf(0.0, 0.20 - avg_border_backup_coverage) * 140.0
	score -= runaway_run_rate * 210.0
	score -= avg_runaway_months * 3.0
	score -= economic_collapse_run_rate * 180.0
	score -= avg_collapse_months * 4.0
	score -= avg_collapsed_faction_months * 6.0
	score -= maxf(0.0, avg_frontline_overload - 0.35) * 120.0
	score -= float(int(aggregate.get("no_attack_runs", 0))) * 120.0
	score -= float(int(aggregate.get("no_capture_runs", 0))) * 150.0
	var findings: Array[String] = _build_findings(metrics, profile)
	var balance_score: Dictionary = _build_balance_score(metrics)
	return {
		"score": score,
		"balance_score": balance_score,
		"metrics": metrics,
		"findings": findings,
		"summary_text": _build_summary_text(metrics, findings, profile),
		"timeline_snapshots": aggregate.get("timeline_snapshots", []),
	}


func _make_empty_aggregate() -> Dictionary:
	return {
		"attack_orders": 0,
		"capture_count": 0,
		"passive_months": 0,
		"unique_attackers": {},
		"alive_factions_end_total": 0,
		"runs": 0,
		"first_attack_month_sum": 0,
		"first_capture_month_sum": 0,
		"no_attack_runs": 0,
		"no_capture_runs": 0,
		"leader_density_sum": 0.0,
		"backup_coverage_sum": 0.0,
		"border_backup_coverage_sum": 0.0,
		"runaway_detected_runs": 0,
		"runaway_months_sum": 0,
		"top_empire_share_peak_sum": 0.0,
		"economic_collapse_runs": 0,
		"economic_collapse_months_sum": 0,
		"collapsed_faction_months_sum": 0,
		"frontline_pressure_sum": 0.0,
		"frontline_overload_sum": 0.0,
		"hot_front_share_sum": 0.0,
		"frontline_pressure_by_faction_sum": {},
		"general_pool_size_sum": 0.0,
		"general_pool_size_start_sum": 0.0,
		"general_pool_size_end_sum": 0.0,
		"avg_frontier_provinces_per_faction_sum": 0.0,
		"avg_available_leaders_per_faction_sum": 0.0,
		"avg_unused_available_leaders_sum": 0.0,
		"attack_orders_vs_neutral": 0,
		"attack_orders_vs_faction": 0,
		"passive_faction_war_months": 0,
		"timeline_snapshots": [],
	}

func _accumulate_run_metrics(aggregate: Dictionary, run_metrics: Dictionary, months: int) -> void:
	aggregate["attack_orders"] = int(aggregate.get("attack_orders", 0)) + int(run_metrics.get("attack_orders", 0))
	aggregate["capture_count"] = int(aggregate.get("capture_count", 0)) + int(run_metrics.get("capture_count", 0))
	aggregate["passive_months"] = int(aggregate.get("passive_months", 0)) + int(run_metrics.get("passive_months", 0))
	aggregate["alive_factions_end_total"] = int(aggregate.get("alive_factions_end_total", 0)) + int(run_metrics.get("alive_factions_end", 0))
	aggregate["runs"] = int(aggregate.get("runs", 0)) + 1
	aggregate["leader_density_sum"] = float(aggregate.get("leader_density_sum", 0.0)) + float(run_metrics.get("leader_density_avg", 0.0))
	aggregate["backup_coverage_sum"] = float(aggregate.get("backup_coverage_sum", 0.0)) + float(run_metrics.get("backup_coverage_avg", 0.0))
	aggregate["border_backup_coverage_sum"] = float(aggregate.get("border_backup_coverage_sum", 0.0)) + float(run_metrics.get("border_backup_coverage_avg", 0.0))
	aggregate["runaway_detected_runs"] = int(aggregate.get("runaway_detected_runs", 0)) + (1 if bool(run_metrics.get("runaway_detected", false)) else 0)
	aggregate["runaway_months_sum"] = int(aggregate.get("runaway_months_sum", 0)) + int(run_metrics.get("runaway_months", 0))
	aggregate["top_empire_share_peak_sum"] = float(aggregate.get("top_empire_share_peak_sum", 0.0)) + float(run_metrics.get("top_empire_share_peak", 0.0))
	aggregate["economic_collapse_runs"] = int(aggregate.get("economic_collapse_runs", 0)) + (1 if bool(run_metrics.get("economic_collapse_detected", false)) else 0)
	aggregate["economic_collapse_months_sum"] = int(aggregate.get("economic_collapse_months_sum", 0)) + int(run_metrics.get("economic_collapse_months", 0))
	aggregate["collapsed_faction_months_sum"] = int(aggregate.get("collapsed_faction_months_sum", 0)) + int(run_metrics.get("collapsed_faction_months", 0))
	aggregate["frontline_pressure_sum"] = float(aggregate.get("frontline_pressure_sum", 0.0)) + float(run_metrics.get("frontline_pressure_avg", 0.0))
	aggregate["frontline_overload_sum"] = float(aggregate.get("frontline_overload_sum", 0.0)) + float(run_metrics.get("frontline_overload_avg", 0.0))
	aggregate["hot_front_share_sum"] = float(aggregate.get("hot_front_share_sum", 0.0)) + float(run_metrics.get("hot_front_share_avg", 0.0))
	aggregate["general_pool_size_sum"] = float(aggregate.get("general_pool_size_sum", 0.0)) + float(run_metrics.get("general_pool_size_avg", 0.0))
	aggregate["general_pool_size_start_sum"] = float(aggregate.get("general_pool_size_start_sum", 0.0)) + float(run_metrics.get("general_pool_size_start", 0.0))
	aggregate["general_pool_size_end_sum"] = float(aggregate.get("general_pool_size_end_sum", 0.0)) + float(run_metrics.get("general_pool_size_end", 0.0))
	aggregate["avg_frontier_provinces_per_faction_sum"] = float(aggregate.get("avg_frontier_provinces_per_faction_sum", 0.0)) + float(run_metrics.get("avg_frontier_provinces_per_faction", 0.0))
	aggregate["avg_available_leaders_per_faction_sum"] = float(aggregate.get("avg_available_leaders_per_faction_sum", 0.0)) + float(run_metrics.get("avg_available_leaders_per_faction", 0.0))
	aggregate["avg_unused_available_leaders_sum"] = float(aggregate.get("avg_unused_available_leaders_sum", 0.0)) + float(run_metrics.get("avg_unused_available_leaders", 0.0))
	aggregate["attack_orders_vs_neutral"] = int(aggregate.get("attack_orders_vs_neutral", 0)) + int(run_metrics.get("attack_orders_vs_neutral", 0))
	aggregate["attack_orders_vs_faction"] = int(aggregate.get("attack_orders_vs_faction", 0)) + int(run_metrics.get("attack_orders_vs_faction", 0))
	aggregate["passive_faction_war_months"] = int(aggregate.get("passive_faction_war_months", 0)) + int(run_metrics.get("passive_faction_war_months", 0))
	var first_attack: int = int(run_metrics.get("first_attack_month", months + 1))
	var first_capture: int = int(run_metrics.get("first_capture_month", months + 1))
	aggregate["first_attack_month_sum"] = int(aggregate.get("first_attack_month_sum", 0)) + first_attack
	aggregate["first_capture_month_sum"] = int(aggregate.get("first_capture_month_sum", 0)) + first_capture
	if first_attack > months:
		aggregate["no_attack_runs"] = int(aggregate.get("no_attack_runs", 0)) + 1
	if first_capture > months:
		aggregate["no_capture_runs"] = int(aggregate.get("no_capture_runs", 0)) + 1
	var unique_attackers: Dictionary = aggregate.get("unique_attackers", {}) as Dictionary
	for key in (run_metrics.get("unique_attackers", {}) as Dictionary).keys():
		unique_attackers[key] = true
	_merge_numeric_dictionary(aggregate.get("frontline_pressure_by_faction_sum", {}) as Dictionary, run_metrics.get("frontline_pressure_by_faction_avg", {}) as Dictionary)
	var timeline: Array = aggregate.get("timeline_snapshots", []) as Array
	for snapshot_value in (run_metrics.get("timeline_snapshots", []) as Array):
		timeline.append(snapshot_value)

func _merge_numeric_dictionary(target: Dictionary, source: Dictionary) -> void:
	for key in source.keys():
		target[str(key)] = float(target.get(str(key), 0.0)) + float(source.get(key, 0.0))

func _average_dictionary(source: Dictionary, divisor: int) -> Dictionary:
	var out: Dictionary = {}
	var denom: float = maxf(1.0, float(divisor))
	for key in source.keys():
		out[str(key)] = float(source.get(key, 0.0)) / denom
	return out

func _notify_host_progress(host: Node, payload: Dictionary) -> void:
	if host == null or not is_instance_valid(host):
		return
	if host.has_method("_on_ai_lab_progress"):
		host.call("_on_ai_lab_progress", payload)


func _yield_to_host(host: Node) -> void:
	if host == null or not is_instance_valid(host):
		return
	await host.get_tree().process_frame

func _write_checkpoint_report(report: Dictionary) -> void:
	_write_report_files(report)
	DebugLogger.log("ai_lab_checkpoint_written", {
		"status": str(report.get("status", "checkpoint")),
		"json_path": REPORT_JSON_PATH,
		"text_path": REPORT_TEXT_PATH,
	})


func _make_base_profile(base_profile: AITuningProfile) -> AITuningProfile:
	if base_profile != null:
		return base_profile.duplicate_profile()
	var profile: AITuningProfile = AITuningProfileScript.new()
	profile.sanitize()
	return profile

func _build_iteration_candidates(base_profile: AITuningProfile) -> Array:
	var deltas: Array = [
		{},
		{"attack_pwin_offset": -0.04},
		{"attack_pwin_offset": -0.08},
		{"fort_defense_mult": -0.10},
		{"fort_defense_mult": -0.15, "chokepoint_defense_mult": -0.10},
		{"reserve_floor_mult": -0.08},
		{"treasury_reserve_mult": 0.10, "recruit_econ_guard": 0.10},
		{"treasury_reserve_mult": 0.20, "recruit_econ_guard": 0.20, "fortify_econ_guard": -0.05},
		{"attack_econ_guard": -0.10, "recruit_econ_guard": 0.05, "fortify_econ_guard": 0.05},
		{"attack_score_mult": 0.10},
		{"fort_attack_bonus_mult": 0.10},
		{"starting_extra_generals_per_faction": 1},
				{"attack_pwin_offset": -0.05, "fort_defense_mult": -0.10},
		{"attack_pwin_offset": -0.04, "reserve_floor_mult": -0.08, "attack_score_mult": 0.10},
		{"attack_pwin_offset": -0.03, "max_attacks_bonus": 1, "starting_extra_generals_per_faction": 1},
		{"surplus_war_chest_mult": -0.25, "surplus_attack_pwin_bonus": 0.03, "anti_stalemate_attack_score_mult": 0.10},
		{"anti_stalemate_pwin_bonus": 0.03, "anti_stalemate_max_attacks_bonus": 1, "fortify_surplus_mult": -0.10},
		{"attack_pwin_offset": -0.05, "attack_econ_guard": -0.10, "surplus_war_chest_mult": -0.20},
	]
	var out: Array = []
	for delta in deltas:
		var candidate: AITuningProfile = base_profile.duplicate_profile()
		_apply_delta(candidate, delta)
		out.append(candidate)
	return out

func _apply_delta(profile: AITuningProfile, delta: Dictionary) -> void:
	profile.attack_pwin_offset += float(delta.get("attack_pwin_offset", 0.0))
	profile.attack_score_mult += float(delta.get("attack_score_mult", 0.0))
	profile.reserve_floor_mult += float(delta.get("reserve_floor_mult", 0.0))
	profile.fort_defense_mult += float(delta.get("fort_defense_mult", 0.0))
	profile.chokepoint_defense_mult += float(delta.get("chokepoint_defense_mult", 0.0))
	profile.fort_attack_bonus_mult += float(delta.get("fort_attack_bonus_mult", 0.0))
	profile.max_attacks_bonus += int(delta.get("max_attacks_bonus", 0))
	profile.starting_extra_generals_per_faction += int(delta.get("starting_extra_generals_per_faction", 0))
	profile.treasury_reserve_mult += float(delta.get("treasury_reserve_mult", 0.0))
	profile.recruit_econ_guard += float(delta.get("recruit_econ_guard", 0.0))
	profile.fortify_econ_guard += float(delta.get("fortify_econ_guard", 0.0))
	profile.attack_econ_guard += float(delta.get("attack_econ_guard", 0.0))
	profile.surplus_war_chest_mult += float(delta.get("surplus_war_chest_mult", 0.0))
	profile.surplus_attack_pwin_bonus += float(delta.get("surplus_attack_pwin_bonus", 0.0))
	profile.anti_stalemate_month += int(delta.get("anti_stalemate_month", 0))
	profile.anti_stalemate_pwin_bonus += float(delta.get("anti_stalemate_pwin_bonus", 0.0))
	profile.anti_stalemate_attack_score_mult += float(delta.get("anti_stalemate_attack_score_mult", 0.0))
	profile.anti_stalemate_max_attacks_bonus += int(delta.get("anti_stalemate_max_attacks_bonus", 0))
	profile.fortify_surplus_mult += float(delta.get("fortify_surplus_mult", 0.0))
	profile.sanitize()


func _evaluate_profile(settings: MapSettings, profile: AITuningProfile,
		months: int, seed_count: int) -> Dictionary:
	var aggregate: Dictionary = _make_empty_aggregate()
	for i in range(maxi(1, seed_count)):
		var run_metrics: Dictionary = await _simulate_seed(settings, profile, months, i)
		_accumulate_run_metrics(aggregate, run_metrics, months)
		_write_seed_checkpoint_report(profile, aggregate, i + 1)
	return _aggregate_to_report(aggregate, profile, months)


func _simulate_seed(settings: MapSettings, profile: AITuningProfile,
		months: int, seed_index: int) -> Dictionary:
	var cloned_settings: MapSettings = settings.duplicate(true) as MapSettings
	if cloned_settings == null:
		cloned_settings = settings
	cloned_settings.seed = _derive_seed(settings, seed_index)
	var generator = MapGeneratorScript.new()
	var map_data: MapData = generator.generate_map(cloned_settings)
	var state: GameState = GameStateScript.new()
	state.ai_tuning_profile = profile.duplicate_profile()
	state.rng_seed = _derive_seed(settings, seed_index + 97)
	state.init_with_map(map_data)
	DebugLogger.set_silent(true)  # suppress disk writes during simulation
	var tm = TurnManagerScript.new()
	var metrics := {
		"attack_orders": 0,
		"capture_count": 0,
		"passive_months": 0,
		"alive_factions_end": 0,
		"first_attack_month": months + 1,
		"first_capture_month": months + 1,
		"unique_attackers": {},
		"leader_density_avg": 0.0,
		"backup_coverage_avg": 0.0,
		"border_backup_coverage_avg": 0.0,
		"runaway_detected": false,
		"runaway_months": 0,
		"top_empire_share_peak": 0.0,
		"economic_collapse_detected": false,
		"economic_collapse_months": 0,
		"collapsed_faction_months": 0,
		"frontline_pressure_avg": 0.0,
		"frontline_overload_avg": 0.0,
		"hot_front_share_avg": 0.0,
		"frontline_pressure_by_faction_avg": {},
		"general_pool_size_avg": 0.0,
		"general_pool_size_start": 0.0,
		"general_pool_size_end": 0.0,
		"avg_frontier_provinces_per_faction": 0.0,
		"avg_available_leaders_per_faction": 0.0,
		"avg_unused_available_leaders": 0.0,
		"attack_orders_vs_neutral": 0,
		"attack_orders_vs_faction": 0,
		"passive_faction_war_months": 0,
		"timeline_snapshots": [],
	}
	metrics["general_pool_size_start"] = float(_measure_commander_pressure(state).get("general_pool_size", 0))
	var leader_pressure_samples: int = 0
	var stress_samples: int = 0
	var frontline_samples: int = 0
	for month in range(maxi(1, months)):
		var summary: Dictionary = await tm.execute_month_with_summary(state, HUMAN_DISABLED_ID, 0, true)
		var attack_orders: int = int(summary.get("attack_orders", 0))
		var attack_orders_vs_neutral: int = int(summary.get("attack_orders_vs_neutral", 0))
		var attack_orders_vs_faction: int = int(summary.get("attack_orders_vs_faction", 0))
		var capture_count: int = int(summary.get("capture_count", 0))
		metrics["attack_orders"] = int(metrics.get("attack_orders", 0)) + attack_orders
		metrics["attack_orders_vs_neutral"] = int(metrics.get("attack_orders_vs_neutral", 0)) + attack_orders_vs_neutral
		metrics["attack_orders_vs_faction"] = int(metrics.get("attack_orders_vs_faction", 0)) + attack_orders_vs_faction
		metrics["capture_count"] = int(metrics.get("capture_count", 0)) + capture_count
		if attack_orders <= 0:
			metrics["passive_months"] = int(metrics.get("passive_months", 0)) + 1
		if attack_orders_vs_faction <= 0:
			metrics["passive_faction_war_months"] = int(metrics.get("passive_faction_war_months", 0)) + 1
		elif int(metrics.get("first_attack_month", months + 1)) > months:
			metrics["first_attack_month"] = month + 1
		if capture_count > 0 and int(metrics.get("first_capture_month", months + 1)) > months:
			metrics["first_capture_month"] = month + 1
		var faction_attack_orders: Dictionary = summary.get("faction_attack_orders", {}) as Dictionary
		var unique_attackers: Dictionary = metrics.get("unique_attackers", {}) as Dictionary
		for key in faction_attack_orders.keys():
			if int(faction_attack_orders.get(key, 0)) > 0:
				unique_attackers[key] = true
		# Sample slow structural metrics every 6 months — accurate enough for averages
		if month % 6 == 0:
			var pressure: Dictionary = _measure_leader_pressure(state)
			metrics["leader_density_avg"] = float(metrics.get("leader_density_avg", 0.0)) + float(pressure.get("leader_density", 0.0))
			metrics["backup_coverage_avg"] = float(metrics.get("backup_coverage_avg", 0.0)) + float(pressure.get("backup_coverage", 0.0))
			metrics["border_backup_coverage_avg"] = float(metrics.get("border_backup_coverage_avg", 0.0)) + float(pressure.get("border_backup_coverage", 0.0))
			leader_pressure_samples += 1
		var empire: Dictionary = _measure_empire_runaway(state)
		metrics["runaway_months"] = int(metrics.get("runaway_months", 0)) + int(empire.get("runaway_months", 0))
		metrics["top_empire_share_peak"] = maxf(float(metrics.get("top_empire_share_peak", 0.0)), float(empire.get("top_empire_share", 0.0)))
		if bool(empire.get("runaway_detected", false)):
			metrics["runaway_detected"] = true
		var economy: Dictionary = _measure_economic_stability(state)
		metrics["economic_collapse_months"] = int(metrics.get("economic_collapse_months", 0)) + int(economy.get("collapse_months", 0))
		metrics["collapsed_faction_months"] = int(metrics.get("collapsed_faction_months", 0)) + int(economy.get("collapsed_faction_months", 0))
		if bool(economy.get("economic_collapse_detected", false)):
			metrics["economic_collapse_detected"] = true
		stress_samples += 1
		if month % 6 == 0:
			var frontline: Dictionary = _measure_frontline_pressure(state)
			metrics["frontline_pressure_avg"] = float(metrics.get("frontline_pressure_avg", 0.0)) + float(frontline.get("frontline_pressure", 0.0))
			metrics["frontline_overload_avg"] = float(metrics.get("frontline_overload_avg", 0.0)) + float(frontline.get("frontline_overload", 0.0))
			metrics["hot_front_share_avg"] = float(metrics.get("hot_front_share_avg", 0.0)) + float(frontline.get("hot_front_share", 0.0))
			_merge_numeric_dictionary(metrics.get("frontline_pressure_by_faction_avg", {}) as Dictionary, frontline.get("pressure_by_faction", {}) as Dictionary)
			frontline_samples += 1
			var commander: Dictionary = _measure_commander_pressure(state)
			metrics["general_pool_size_avg"] = float(metrics.get("general_pool_size_avg", 0.0)) + float(commander.get("general_pool_size", 0.0))
			metrics["avg_frontier_provinces_per_faction"] = float(metrics.get("avg_frontier_provinces_per_faction", 0.0)) + float(commander.get("avg_frontier_provinces_per_faction", 0.0))
			metrics["avg_available_leaders_per_faction"] = float(metrics.get("avg_available_leaders_per_faction", 0.0)) + float(commander.get("avg_available_leaders_per_faction", 0.0))
			metrics["avg_unused_available_leaders"] = float(metrics.get("avg_unused_available_leaders", 0.0)) + float(commander.get("avg_unused_available_leaders", 0.0))
		if ((month + 1) % 12) == 0 or (month + 1) == maxi(1, months):
			(metrics.get("timeline_snapshots", []) as Array).append(_build_timeline_snapshot(state, month + 1, attack_orders, capture_count))
	DebugLogger.set_silent(false)  # restore logging after simulation
	metrics["alive_factions_end"] = int(_count_alive_factions(state))
	if leader_pressure_samples > 0:
		metrics["leader_density_avg"] = float(metrics.get("leader_density_avg", 0.0)) / float(leader_pressure_samples)
		metrics["backup_coverage_avg"] = float(metrics.get("backup_coverage_avg", 0.0)) / float(leader_pressure_samples)
		metrics["border_backup_coverage_avg"] = float(metrics.get("border_backup_coverage_avg", 0.0)) / float(leader_pressure_samples)
	if stress_samples > 0:
		metrics["economic_collapse_months"] = int(metrics.get("economic_collapse_months", 0))
		metrics["collapsed_faction_months"] = int(metrics.get("collapsed_faction_months", 0))
	if frontline_samples > 0:
		metrics["frontline_pressure_avg"] = float(metrics.get("frontline_pressure_avg", 0.0)) / float(frontline_samples)
		metrics["frontline_overload_avg"] = float(metrics.get("frontline_overload_avg", 0.0)) / float(frontline_samples)
		metrics["hot_front_share_avg"] = float(metrics.get("hot_front_share_avg", 0.0)) / float(frontline_samples)
		metrics["frontline_pressure_by_faction_avg"] = _average_dictionary(metrics.get("frontline_pressure_by_faction_avg", {}) as Dictionary, frontline_samples)
		metrics["general_pool_size_avg"] = float(metrics.get("general_pool_size_avg", 0.0)) / float(frontline_samples)
		metrics["avg_frontier_provinces_per_faction"] = float(metrics.get("avg_frontier_provinces_per_faction", 0.0)) / float(frontline_samples)
		metrics["avg_available_leaders_per_faction"] = float(metrics.get("avg_available_leaders_per_faction", 0.0)) / float(frontline_samples)
		metrics["avg_unused_available_leaders"] = float(metrics.get("avg_unused_available_leaders", 0.0)) / float(frontline_samples)
	metrics["general_pool_size_end"] = float(_measure_commander_pressure(state).get("general_pool_size", 0))
	return metrics

func _simulate_seed_async(host: Node, settings: MapSettings, profile: AITuningProfile,
		months: int, seed_index: int, iteration: int, candidate_index: int, seed_count: int) -> Dictionary:
	var cloned_settings: MapSettings = settings.duplicate(true) as MapSettings
	if cloned_settings == null:
		cloned_settings = settings
	cloned_settings.seed = _derive_seed(settings, seed_index)
	var generator = MapGeneratorScript.new()
	var map_data: MapData = generator.generate_map(cloned_settings)
	var state: GameState = GameStateScript.new()
	state.ai_tuning_profile = profile.duplicate_profile()
	state.rng_seed = _derive_seed(settings, seed_index + 97)
	state.init_with_map(map_data)
	DebugLogger.set_silent(true)  # suppress disk writes during simulation
	_notify_host_progress(host, {
		"status": "seed_started",
		"iteration": iteration,
		"candidate_index": candidate_index,
		"seed_index": seed_index,
		"seed_count": seed_count,
		"month": 0,
		"months": maxi(1, months),
		"preview_map_data": state.map_data,
		"owner_by_province": _snapshot_owner_by_province(state),
	})
	await _yield_to_host(host)
	var tm = TurnManagerScript.new()
	var metrics := {
		"attack_orders": 0,
		"capture_count": 0,
		"passive_months": 0,
		"alive_factions_end": 0,
		"first_attack_month": months + 1,
		"first_capture_month": months + 1,
		"unique_attackers": {},
		"leader_density_avg": 0.0,
		"backup_coverage_avg": 0.0,
		"border_backup_coverage_avg": 0.0,
		"runaway_detected": false,
		"runaway_months": 0,
		"top_empire_share_peak": 0.0,
		"economic_collapse_detected": false,
		"economic_collapse_months": 0,
		"collapsed_faction_months": 0,
		"frontline_pressure_avg": 0.0,
		"frontline_overload_avg": 0.0,
		"hot_front_share_avg": 0.0,
		"frontline_pressure_by_faction_avg": {},
		"general_pool_size_avg": 0.0,
		"general_pool_size_start": 0.0,
		"general_pool_size_end": 0.0,
		"avg_frontier_provinces_per_faction": 0.0,
		"avg_available_leaders_per_faction": 0.0,
		"avg_unused_available_leaders": 0.0,
		"attack_orders_vs_neutral": 0,
		"attack_orders_vs_faction": 0,
		"passive_faction_war_months": 0,
		"timeline_snapshots": [],
	}
	metrics["general_pool_size_start"] = float(_measure_commander_pressure(state).get("general_pool_size", 0))
	var leader_pressure_samples: int = 0
	var stress_samples: int = 0
	var frontline_samples: int = 0
	for month in range(maxi(1, months)):
		var summary: Dictionary = await tm.execute_month_with_summary(state, HUMAN_DISABLED_ID, 0, true)
		var attack_orders: int = int(summary.get("attack_orders", 0))
		var attack_orders_vs_neutral: int = int(summary.get("attack_orders_vs_neutral", 0))
		var attack_orders_vs_faction: int = int(summary.get("attack_orders_vs_faction", 0))
		var capture_count: int = int(summary.get("capture_count", 0))
		metrics["attack_orders"] = int(metrics.get("attack_orders", 0)) + attack_orders
		metrics["attack_orders_vs_neutral"] = int(metrics.get("attack_orders_vs_neutral", 0)) + attack_orders_vs_neutral
		metrics["attack_orders_vs_faction"] = int(metrics.get("attack_orders_vs_faction", 0)) + attack_orders_vs_faction
		metrics["capture_count"] = int(metrics.get("capture_count", 0)) + capture_count
		if attack_orders <= 0:
			metrics["passive_months"] = int(metrics.get("passive_months", 0)) + 1
		if attack_orders_vs_faction <= 0:
			metrics["passive_faction_war_months"] = int(metrics.get("passive_faction_war_months", 0)) + 1
		elif int(metrics.get("first_attack_month", months + 1)) > months:
			metrics["first_attack_month"] = month + 1
		if capture_count > 0 and int(metrics.get("first_capture_month", months + 1)) > months:
			metrics["first_capture_month"] = month + 1
		var faction_attack_orders: Dictionary = summary.get("faction_attack_orders", {}) as Dictionary
		var unique_attackers: Dictionary = metrics.get("unique_attackers", {}) as Dictionary
		for key in faction_attack_orders.keys():
			if int(faction_attack_orders.get(key, 0)) > 0:
				unique_attackers[key] = true
		var pressure: Dictionary = _measure_leader_pressure(state)
		metrics["leader_density_avg"] = float(metrics.get("leader_density_avg", 0.0)) + float(pressure.get("leader_density", 0.0))
		metrics["backup_coverage_avg"] = float(metrics.get("backup_coverage_avg", 0.0)) + float(pressure.get("backup_coverage", 0.0))
		metrics["border_backup_coverage_avg"] = float(metrics.get("border_backup_coverage_avg", 0.0)) + float(pressure.get("border_backup_coverage", 0.0))
		leader_pressure_samples += 1
		var empire: Dictionary = _measure_empire_runaway(state)
		metrics["runaway_months"] = int(metrics.get("runaway_months", 0)) + int(empire.get("runaway_months", 0))
		metrics["top_empire_share_peak"] = maxf(float(metrics.get("top_empire_share_peak", 0.0)), float(empire.get("top_empire_share", 0.0)))
		if bool(empire.get("runaway_detected", false)):
			metrics["runaway_detected"] = true
		var economy: Dictionary = _measure_economic_stability(state)
		metrics["economic_collapse_months"] = int(metrics.get("economic_collapse_months", 0)) + int(economy.get("collapse_months", 0))
		metrics["collapsed_faction_months"] = int(metrics.get("collapsed_faction_months", 0)) + int(economy.get("collapsed_faction_months", 0))
		if bool(economy.get("economic_collapse_detected", false)):
			metrics["economic_collapse_detected"] = true
		stress_samples += 1
		var frontline: Dictionary = _measure_frontline_pressure(state)
		metrics["frontline_pressure_avg"] = float(metrics.get("frontline_pressure_avg", 0.0)) + float(frontline.get("frontline_pressure", 0.0))
		metrics["frontline_overload_avg"] = float(metrics.get("frontline_overload_avg", 0.0)) + float(frontline.get("frontline_overload", 0.0))
		metrics["hot_front_share_avg"] = float(metrics.get("hot_front_share_avg", 0.0)) + float(frontline.get("hot_front_share", 0.0))
		_merge_numeric_dictionary(metrics.get("frontline_pressure_by_faction_avg", {}) as Dictionary, frontline.get("pressure_by_faction", {}) as Dictionary)
		frontline_samples += 1
		var commander: Dictionary = _measure_commander_pressure(state)
		metrics["general_pool_size_avg"] = float(metrics.get("general_pool_size_avg", 0.0)) + float(commander.get("general_pool_size", 0.0))
		metrics["avg_frontier_provinces_per_faction"] = float(metrics.get("avg_frontier_provinces_per_faction", 0.0)) + float(commander.get("avg_frontier_provinces_per_faction", 0.0))
		metrics["avg_available_leaders_per_faction"] = float(metrics.get("avg_available_leaders_per_faction", 0.0)) + float(commander.get("avg_available_leaders_per_faction", 0.0))
		metrics["avg_unused_available_leaders"] = float(metrics.get("avg_unused_available_leaders", 0.0)) + float(commander.get("avg_unused_available_leaders", 0.0))
		if ((month + 1) % 12) == 0 or (month + 1) == maxi(1, months):
			(metrics.get("timeline_snapshots", []) as Array).append(_build_timeline_snapshot(state, month + 1, attack_orders, capture_count))
		# Only yield and update the map every 12 months (once per year).
		# Yielding every month multiplies runtime by the frame budget — with
		# 72 months × 12 seeds × many candidates this adds hours to a run.
		var is_checkpoint_month: bool = ((month + 1) % 12 == 0) or (month + 1 == maxi(1, months))
		if is_checkpoint_month:
			_notify_host_progress(host, {
				"status": "month_complete",
				"iteration": iteration,
				"candidate_index": candidate_index,
				"seed_index": seed_index,
				"seed_count": seed_count,
				"month": month + 1,
				"months": maxi(1, months),
				"state_month": int(state.month_index),
				"attack_orders": attack_orders,
				"capture_count": capture_count,
				"owner_by_province": _snapshot_owner_by_province(state),
			})
			await _yield_to_host(host)
	DebugLogger.set_silent(false)  # restore logging after simulation
	metrics["alive_factions_end"] = int(_count_alive_factions(state))
	if leader_pressure_samples > 0:
		metrics["leader_density_avg"] = float(metrics.get("leader_density_avg", 0.0)) / float(leader_pressure_samples)
		metrics["backup_coverage_avg"] = float(metrics.get("backup_coverage_avg", 0.0)) / float(leader_pressure_samples)
		metrics["border_backup_coverage_avg"] = float(metrics.get("border_backup_coverage_avg", 0.0)) / float(leader_pressure_samples)
	if stress_samples > 0:
		metrics["economic_collapse_months"] = int(metrics.get("economic_collapse_months", 0))
		metrics["collapsed_faction_months"] = int(metrics.get("collapsed_faction_months", 0))
	if frontline_samples > 0:
		metrics["frontline_pressure_avg"] = float(metrics.get("frontline_pressure_avg", 0.0)) / float(frontline_samples)
		metrics["frontline_overload_avg"] = float(metrics.get("frontline_overload_avg", 0.0)) / float(frontline_samples)
		metrics["hot_front_share_avg"] = float(metrics.get("hot_front_share_avg", 0.0)) / float(frontline_samples)
		metrics["frontline_pressure_by_faction_avg"] = _average_dictionary(metrics.get("frontline_pressure_by_faction_avg", {}) as Dictionary, frontline_samples)
		metrics["general_pool_size_avg"] = float(metrics.get("general_pool_size_avg", 0.0)) / float(frontline_samples)
		metrics["avg_frontier_provinces_per_faction"] = float(metrics.get("avg_frontier_provinces_per_faction", 0.0)) / float(frontline_samples)
		metrics["avg_available_leaders_per_faction"] = float(metrics.get("avg_available_leaders_per_faction", 0.0)) / float(frontline_samples)
		metrics["avg_unused_available_leaders"] = float(metrics.get("avg_unused_available_leaders", 0.0)) / float(frontline_samples)
	metrics["general_pool_size_end"] = float(_measure_commander_pressure(state).get("general_pool_size", 0))
	_notify_host_progress(host, {
		"status": "seed_finished",
		"iteration": iteration,
		"candidate_index": candidate_index,
		"seed_index": seed_index,
		"seed_count": seed_count,
		"month": maxi(1, months),
		"months": maxi(1, months),
		"alive_factions_end": int(metrics.get("alive_factions_end", 0)),
	})
	return metrics


func _snapshot_owner_by_province(state: GameState) -> Dictionary:
	var out: Dictionary = {}
	if state == null or state.map_data == null:
		return out
	for item in state.map_data.provinces:
		var province: ProvinceData = item as ProvinceData
		if province == null:
			continue
		out[int(province.id)] = int(province.owner_id)
	return out


func _measure_leader_pressure(state: GameState) -> Dictionary:
	if state == null or state.map_data == null:
		return {"leader_density": 0.0, "backup_coverage": 0.0, "border_backup_coverage": 0.0}
	var owned_count: int = 0
	var total_leaders_on_map: int = 0
	var backup_ready: int = 0
	var border_count: int = 0
	var border_backup_ready: int = 0
	for item in state.map_data.provinces:
		var province: ProvinceData = item as ProvinceData
		if province == null or int(province.owner_id) < 0:
			continue
		owned_count += 1
		var leader_count: int = (province.leader_ids as Array).size()
		total_leaders_on_map += leader_count
		if leader_count >= 2:
			backup_ready += 1
		var is_border: bool = false
		var neighbors: Array = []
		if state.map_data.adjacency.has(int(province.id)):
			neighbors = state.map_data.adjacency.get(int(province.id), []) as Array
		else:
			for route_item in state.map_data.routes:
				var route: RouteData = route_item as RouteData
				if route == null:
					continue
				if int(route.a) == int(province.id):
					neighbors.append(int(route.b))
				elif int(route.b) == int(province.id):
					neighbors.append(int(route.a))
		for other_id_variant in neighbors:
			var other_id: int = int(other_id_variant)
			if other_id < 0 or other_id >= state.map_data.provinces.size():
				continue
			var other: ProvinceData = state.map_data.provinces[other_id] as ProvinceData
			if other != null and int(other.owner_id) != int(province.owner_id):
				is_border = true
				break
		if is_border:
			border_count += 1
			if leader_count >= 2:
				border_backup_ready += 1
	var denom_owned: float = maxf(1.0, float(owned_count))
	var denom_border: float = maxf(1.0, float(border_count))
	return {
		"leader_density": float(total_leaders_on_map) / denom_owned,
		"backup_coverage": float(backup_ready) / denom_owned,
		"border_backup_coverage": float(border_backup_ready) / denom_border,
	}


func _measure_empire_runaway(state: GameState) -> Dictionary:
	if state == null or state.map_data == null:
		return {"runaway_detected": false, "runaway_months": 0, "top_empire_share": 0.0}
	var total_owned: int = 0
	var top_owned: int = 0
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		var owned: int = int((faction.provinces as Array).size())
		total_owned += owned
		top_owned = maxi(top_owned, owned)
	if total_owned <= 0:
		return {"runaway_detected": false, "runaway_months": 0, "top_empire_share": 0.0}
	var top_share: float = float(top_owned) / float(total_owned)
	var runaway: bool = top_share >= 0.45
	return {
		"runaway_detected": runaway,
		"runaway_months": 1 if runaway else 0,
		"top_empire_share": top_share,
	}

func _measure_economic_stability(state: GameState) -> Dictionary:
	if state == null or state.map_data == null:
		return {"economic_collapse_detected": false, "collapse_months": 0, "collapsed_faction_months": 0}
	var collapsed_faction_months: int = 0
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if int((faction.provinces as Array).size()) <= 0:
			continue
		var income: int = int(faction.income_last_turn)
		var gold: int = int(faction.gold)
		var collapsed: bool = gold <= -100 or (gold <= 0 and income <= 0)
		if collapsed:
			collapsed_faction_months += 1
	var economic_collapse_detected: bool = collapsed_faction_months >= 2
	return {
		"economic_collapse_detected": economic_collapse_detected,
		"collapse_months": 1 if economic_collapse_detected else 0,
		"collapsed_faction_months": collapsed_faction_months,
	}

func _measure_frontline_pressure(state: GameState) -> Dictionary:
	if state == null or state.map_data == null:
		return {
			"frontline_pressure": 0.0,
			"frontline_overload": 0.0,
			"hot_front_share": 0.0,
			"pressure_by_faction": {},
		}
	var total_owned: int = 0
	var total_border: int = 0
	var overloaded_border: int = 0
	var hot_front: int = 0
	var pressure_by_faction: Dictionary = {}
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		var provinces: Array = faction.provinces as Array
		var owned: int = provinces.size()
		if owned <= 0:
			continue
		total_owned += owned
		var faction_border: int = 0
		for pid_value in provinces:
			var province_id: int = int(pid_value)
			if province_id < 0 or province_id >= state.map_data.provinces.size():
				continue
			var province: ProvinceData = state.map_data.provinces[province_id] as ProvinceData
			if province == null:
				continue
			if not _is_border_province(state, province):
				continue
			faction_border += 1
			total_border += 1
			var leader_count: int = (province.leader_ids as Array).size()
			if leader_count <= 1:
				overloaded_border += 1
			if leader_count <= 0:
				hot_front += 1
		pressure_by_faction[str(int(faction.id))] = float(faction_border) / maxf(1.0, float(owned))
	var border_pressure: float = float(total_border) / maxf(1.0, float(total_owned))
	var overload: float = float(overloaded_border) / maxf(1.0, float(total_border))
	var hot_share: float = float(hot_front) / maxf(1.0, float(total_border))
	return {
		"frontline_pressure": border_pressure,
		"frontline_overload": overload,
		"hot_front_share": hot_share,
		"pressure_by_faction": pressure_by_faction,
	}

func _is_border_province(state: GameState, province: ProvinceData) -> bool:
	if state == null or state.map_data == null or province == null:
		return false
	var neighbors: Array = []
	if state.map_data.adjacency.has(int(province.id)):
		neighbors = state.map_data.adjacency.get(int(province.id), []) as Array
	else:
		for route_item in state.map_data.routes:
			var route: RouteData = route_item as RouteData
			if route == null:
				continue
			if int(route.a) == int(province.id):
				neighbors.append(int(route.b))
			elif int(route.b) == int(province.id):
				neighbors.append(int(route.a))
	for other_id_variant in neighbors:
		var other_id: int = int(other_id_variant)
		if other_id < 0 or other_id >= state.map_data.provinces.size():
			continue
		var other: ProvinceData = state.map_data.provinces[other_id] as ProvinceData
		if other != null and int(other.owner_id) != int(province.owner_id):
			return true
	return false



func _measure_commander_pressure(state: GameState) -> Dictionary:
	if state == null or state.map_data == null:
		return {
			"general_pool_size": 0,
			"avg_frontier_provinces_per_faction": 0.0,
			"avg_available_leaders_per_faction": 0.0,
			"avg_unused_available_leaders": 0.0,
		}
	var faction_count: int = 0
	var frontier_sum: int = 0
	var available_sum: int = 0
	var unused_sum: int = 0
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if int(faction.id) < 0:
			continue
		faction_count += 1
		var frontier: int = 0
		for province_id_variant in faction.provinces:
			var pid: int = int(province_id_variant)
			if pid < 0 or pid >= state.map_data.provinces.size():
				continue
			var province: ProvinceData = state.map_data.provinces[pid] as ProvinceData
			if _is_border_province(state, province):
				frontier += 1
		frontier_sum += frontier
		var available: int = 0
		for leader_id_variant in faction.leader_ids:
			var leader: LeaderData = state.get_leader(int(leader_id_variant))
			if leader == null:
				continue
			if str(leader.status) != "wounded" and not bool(leader.on_mission):
				available += 1
		available_sum += available
		unused_sum += maxi(0, available - frontier)
	var denom: float = maxf(1.0, float(faction_count))
	return {
		"general_pool_size": int((state.dismissed_general_pool as Array).size()),
		"avg_frontier_provinces_per_faction": float(frontier_sum) / denom,
		"avg_available_leaders_per_faction": float(available_sum) / denom,
		"avg_unused_available_leaders": float(unused_sum) / denom,
	}

func _build_balance_score(metrics: Dictionary) -> Dictionary:
	var score: float = 100.0
	var positives: Array[String] = []
	var concerns: Array[String] = []
	var avg_attacks: float = float(metrics.get("avg_attacks_per_month", 0.0))
	var avg_captures: float = float(metrics.get("avg_captures_per_month", 0.0))
	var avg_passive: float = float(metrics.get("avg_passive_months", 0.0))
	var runaway_rate: float = float(metrics.get("runaway_run_rate", 0.0))
	var collapse_rate: float = float(metrics.get("economic_collapse_run_rate", 0.0))
	var border_backup: float = float(metrics.get("avg_border_backup_coverage", 0.0))
	var attackers: int = int(metrics.get("unique_attacker_count", 0))
	if avg_attacks >= 2.0:
		positives.append("Wars are firing at a healthy pace.")
	else:
		concerns.append("Attack tempo is still low.")
		score -= maxf(0.0, 2.0 - avg_attacks) * 16.0
	if avg_captures >= 0.45:
		positives.append("Province turnover is happening.")
	else:
		concerns.append("Borders are changing too slowly.")
		score -= maxf(0.0, 0.45 - avg_captures) * 38.0
	if avg_passive <= 18.0:
		positives.append("Midgame passivity is under control.")
	else:
		concerns.append("Midgame stalemates remain common.")
		score -= minf(30.0, maxf(0.0, avg_passive - 18.0) * 1.1)
	if runaway_rate <= 0.15:
		positives.append("Runaway empire risk is controlled.")
	else:
		concerns.append("Snowball risk is creeping up.")
		score -= runaway_rate * 35.0
	if collapse_rate <= 0.30:
		positives.append("Faction economies are mostly stable.")
	else:
		concerns.append("Economic collapses still happen too often.")
		score -= collapse_rate * 28.0
	if border_backup >= 0.25:
		positives.append("Border provinces usually have enough leader backup.")
	else:
		concerns.append("Frontier leader coverage is still thin.")
		score -= maxf(0.0, 0.25 - border_backup) * 90.0
	if attackers >= 6:
		positives.append("Offense is spread across multiple factions.")
	else:
		concerns.append("Only a few factions are carrying the wars.")
		score -= float(maxi(0, 6 - attackers)) * 3.0
	score = clampf(score, 0.0, 100.0)
	var grade: String = "D"
	if score >= 90.0:
		grade = "A"
	elif score >= 80.0:
		grade = "B"
	elif score >= 70.0:
		grade = "C"
	return {
		"score": roundf(score * 10.0) / 10.0,
		"grade": grade,
		"positives": positives,
		"concerns": concerns,
	}


func _build_findings(metrics: Dictionary, profile: AITuningProfile) -> Array[String]:
	var findings: Array[String] = []
	var avg_attacks: float = float(metrics.get("avg_attacks_per_month", 0.0))
	var avg_captures: float = float(metrics.get("avg_captures_per_month", 0.0))
	var avg_first_attack: float = float(metrics.get("avg_first_attack_month", 99.0))
	var avg_first_capture: float = float(metrics.get("avg_first_capture_month", 99.0))
	var unique_attackers: int = int(metrics.get("unique_attacker_count", 0))
	var backup_coverage: float = float(metrics.get("avg_backup_coverage", 0.0))
	var border_backup: float = float(metrics.get("avg_border_backup_coverage", 0.0))
	var runaway_rate: float = float(metrics.get("runaway_run_rate", 0.0))
	var top_share_peak: float = float(metrics.get("avg_top_empire_share_peak", 0.0))
	var collapse_rate: float = float(metrics.get("economic_collapse_run_rate", 0.0))
	var collapse_months: float = float(metrics.get("avg_collapse_months", 0.0))
	var frontline_pressure: float = float(metrics.get("avg_frontline_pressure", 0.0))
	var frontline_overload: float = float(metrics.get("avg_frontline_overload", 0.0))
	var hot_front_share: float = float(metrics.get("avg_hot_front_share", 0.0))
	var faction_attacks: float = float(metrics.get("avg_attacks_vs_faction_per_month", 0.0))
	var neutral_attacks: float = float(metrics.get("avg_attacks_vs_neutral_per_month", 0.0))
	var passive_faction_war_months: float = float(metrics.get("avg_passive_faction_war_months", 0.0))
	if avg_attacks < 1.5:
		findings.append("AI is still too passive. Lower attack caution or defender scaling further.")
	if faction_attacks < 0.80 and neutral_attacks > faction_attacks:
		findings.append("The AI still prefers neutrals over faction wars. Increase border-war pressure and relax non-critical defense floors.")
	if passive_faction_war_months >= 12.0:
		findings.append("Border wars stall for too many months once neutrals thin out. The planner still needs stronger war-conversion pressure.")
	elif avg_attacks > 6.0:
		findings.append("AI is attacking very often. Watch for reckless wars and tempo spikes.")
	else:
		findings.append("Attack frequency is in a healthy range for strategic pressure.")
	if avg_captures < 0.35:
		findings.append("Too few provinces are changing hands. Fort and chokepoint defense likely remain too strong.")
	elif avg_captures > 2.5:
		findings.append("Province turnover is very high. Check for snowballing or defenses being too weak.")
	else:
		findings.append("Province capture rate looks healthy for continued testing.")
	if avg_first_attack > 6.0:
		findings.append("Wars are starting late. Early aggression is probably still under-tuned.")
	if avg_first_capture > 9.0:
		findings.append("Meaningful map change starts late. Consider easing attack thresholds a little more.")
	if unique_attackers <= 2:
		findings.append("Only a few factions are acting offensively. Some doctrines may still be over-cautious.")
	if backup_coverage < 0.30:
		findings.append("Leader scarcity is still choking offense. Border provinces rarely have a backup commander.")
	if border_backup < 0.20:
		findings.append("Frontier coverage is thin. Extra generals or smarter transfers should improve willingness to attack.")
	if runaway_rate >= 0.50 or top_share_peak >= 0.55:
		findings.append("Runaway empire risk is high. One faction is snowballing too often across the test set.")
	elif runaway_rate <= 0.20:
		findings.append("Runaway empire risk is controlled across most seeds.")
	if collapse_rate >= 0.50 or collapse_months >= 6.0:
		findings.append("Economic collapse is too common. Some factions are stalling at zero or negative treasury for long stretches.")
	elif collapse_rate <= 0.20:
		findings.append("Faction economies are mostly stable across the simulation window.")
	if frontline_overload >= 0.45 or hot_front_share >= 0.20:
		findings.append("Frontline pressure is overloaded. Too many border provinces are defended by one or zero leaders.")
	elif frontline_pressure < 0.20:
		findings.append("Frontline pressure is light. This map setup may be too insulated for strong midgame wars.")
	else:
		findings.append("Frontline pressure mapping looks usable for comparing future AI passes.")
	if int(profile.starting_extra_generals_per_faction) >= 2 and avg_attacks < 1.0:
		findings.append("Even with extra starting generals the AI is passive, so the remaining issue is probably threshold math rather than leader supply.")
	return findings

func _build_summary_text(metrics: Dictionary, findings: Array, profile: AITuningProfile) -> String:
	return "AI Lab v3 | atk/mo=%.2f faction_atk/mo=%.2f neutral_atk/mo=%.2f cap/mo=%.2f first_atk=%.2f first_cap=%.2f attackers=%d backup=%.2f border_backup=%.2f runaway=%.2f econ=%.2f front=%.2f extra_generals=%d" % [
		float(metrics.get("avg_attacks_per_month", 0.0)),
		float(metrics.get("avg_attacks_vs_faction_per_month", 0.0)),
		float(metrics.get("avg_attacks_vs_neutral_per_month", 0.0)),
		float(metrics.get("avg_captures_per_month", 0.0)),
		float(metrics.get("avg_first_attack_month", 0.0)),
		float(metrics.get("avg_first_capture_month", 0.0)),
		int(metrics.get("unique_attacker_count", 0)),
		float(metrics.get("avg_backup_coverage", 0.0)),
		float(metrics.get("avg_border_backup_coverage", 0.0)),
		float(metrics.get("runaway_run_rate", 0.0)),
		float(metrics.get("economic_collapse_run_rate", 0.0)),
		float(metrics.get("avg_frontline_pressure", 0.0)),
		int(profile.starting_extra_generals_per_faction)
	]


func _build_timeline_snapshot(state: GameState, month_number: int, attack_orders: int, capture_count: int) -> Dictionary:
	var province_counts: Array = []
	var gold_board: Array = []
	if state != null and state.map_data != null:
		for faction_item in state.map_data.factions:
			var faction: FactionData = faction_item as FactionData
			if faction == null:
				continue
			province_counts.append({
				"faction": int(faction.id),
				"provinces": int((faction.provinces as Array).size()),
				"gold": int(faction.gold),
			})
		province_counts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("provinces", 0)) == int(b.get("provinces", 0)):
				return int(a.get("gold", 0)) > int(b.get("gold", 0))
			return int(a.get("provinces", 0)) > int(b.get("provinces", 0))
		)
		for i in range(mini(5, province_counts.size())):
			gold_board.append(province_counts[i])
	return {
		"month": month_number,
		"attack_orders": attack_orders,
		"capture_count": capture_count,
		"leaders_alive": _count_alive_factions(state),
		"top_factions": gold_board,
	}

func _write_seed_checkpoint_report(profile: AITuningProfile, aggregate: Dictionary, completed_runs: int) -> void:
	var checkpoint := {
		"candidate_index": -1,
		"iteration": -1,
		"seed_index": completed_runs - 1,
		"status": "seed_complete",
		"partial_metrics": aggregate,
		"profile": profile.to_dictionary(),
		"balance_score": _build_balance_score(_aggregate_to_report(aggregate, profile, 36).get("metrics", {})),
	}
	var json_file := FileAccess.open(REPORT_JSON_PATH, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(JSON.stringify(checkpoint, "	"))
		json_file.close()

func _write_report_files(report: Dictionary) -> void:
	var json_file := FileAccess.open(REPORT_JSON_PATH, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(JSON.stringify(report, "	"))
		json_file.close()
	var text_file := FileAccess.open(REPORT_TEXT_PATH, FileAccess.WRITE)
	if text_file != null:
		text_file.store_string(_report_to_text(report))
		text_file.close()

func _report_to_text(report: Dictionary) -> String:
	var lines: PackedStringArray = []
	var status: String = str(report.get("status", "complete"))
	var is_complete: bool = status == "complete" or not report.has("status")
	var metrics: Dictionary = report.get("metrics", {}) as Dictionary
	if metrics.is_empty() and report.has("partial_metrics"):
		metrics = report.get("partial_metrics", {}) as Dictionary
	var best_profile: Dictionary = report.get("best_profile", {}) as Dictionary
	if best_profile.is_empty() and report.has("profile"):
		best_profile = report.get("profile", {}) as Dictionary
	lines.append("KINGDOM AI LAB REPORT V3")
	lines.append("Status: %s" % status)
	lines.append("")
	if is_complete:
		lines.append("Optimization Score: %s" % str(report.get("score", 0.0)))
	else:
		lines.append("Progress: iteration=%s candidate=%s seed=%s" % [str(report.get("iteration", "--")), str(report.get("candidate_index", "--")), str(report.get("seed_index", "--"))])
	lines.append("Best Profile: %s" % JSON.stringify(best_profile))
	var balance_score: Dictionary = report.get("balance_score", {}) as Dictionary
	if not balance_score.is_empty():
		lines.append("Balance Score: %s / 100 (%s)" % [str(balance_score.get("score", 0.0)), str(balance_score.get("grade", "--"))])
	lines.append("Summary: %s" % str(report.get("summary_text", "")))
	lines.append("")
	if not balance_score.is_empty():
		lines.append("Balance Read:")
		for positive in (balance_score.get("positives", []) as Array):
			lines.append("+ %s" % str(positive))
		for concern in (balance_score.get("concerns", []) as Array):
			lines.append("! %s" % str(concern))
		lines.append("")
	lines.append("Findings:")
	for finding_value in report.get("findings", []):
		lines.append("- %s" % str(finding_value))
	if report.has("partial_metrics"):
		lines.append("")
		lines.append("Partial Metrics: %s" % JSON.stringify(report.get("partial_metrics", {})))
	lines.append("")
	lines.append("Metrics: %s" % JSON.stringify(metrics))
	var timeline: Array = report.get("timeline_snapshots", []) as Array
	if timeline.is_empty() and report.has("partial_metrics"):
		timeline = (report.get("partial_metrics", {}) as Dictionary).get("timeline_snapshots", []) as Array
	if not timeline.is_empty():
		lines.append("")
		lines.append("Timeline Snapshots:")
		for snapshot_value in timeline:
			var snapshot: Dictionary = snapshot_value as Dictionary
			if snapshot.is_empty():
				continue
			var top_parts: PackedStringArray = []
			for faction_value in (snapshot.get("top_factions", []) as Array):
				var row: Dictionary = faction_value as Dictionary
				top_parts.append("F%s P%s G%s" % [str(row.get("faction", "?")), str(row.get("provinces", 0)), str(row.get("gold", 0))])
			lines.append("- M%s | atk=%s cap=%s alive=%s | %s" % [str(snapshot.get("month", 0)), str(snapshot.get("attack_orders", 0)), str(snapshot.get("capture_count", 0)), str(snapshot.get("leaders_alive", 0)), ", ".join(top_parts)])
	return "\n".join(lines)

func _derive_seed(settings: MapSettings, offset: int) -> int:
	var base_seed: int = int(settings.seed)
	if base_seed == 0:
		base_seed = 1357911
	return base_seed + (offset * 7919)

func _count_alive_factions(state: GameState) -> int:
	if state == null or state.map_data == null:
		return 0
	var alive: int = 0
	for item in state.map_data.factions:
		var faction: FactionData = item as FactionData
		if faction == null:
			continue
		if int((faction.provinces as Array).size()) > 0:
			alive += 1
	return alive
