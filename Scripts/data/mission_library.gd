# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: MissionLibrary
#
# Role:
# Holds the static template data for all 20 missions.
# MissionResolver reads these templates to spawn MissionData instances.
#
# Each template defines:
#   - id, display_name, mission_type, risk_level
#   - biomes it can spawn in
#   - duration range
#   - spawn weight (within its type category)
#   - enemy_profile: describes enemy force composition for scaling
#   - reward_table: XP range, item/gem/gold chances, capture/recruit flags
#   - special_rule: any override behaviour for MissionResolver
#
# Allowed Interactions:
# - MissionResolver (reads templates to spawn missions)
# - MissionPanel UI (reads display_name, type, risk for display)
#
# Forbidden Responsibilities:
# - Must not store live mission state (that is MissionData)
# - Must not modify GameState
# - Must not queue orders
# ==================================================

class_name MissionLibrary

# --------------------------------------------------
# SPAWN WEIGHTS (type-level)
# Used by MissionResolver when rolling a new mission for a slot.
# --------------------------------------------------
const TYPE_WEIGHTS: Dictionary = {
	"skirmish": 25,
	"treasure": 25,
	"hunt":     25,
	"elite":    25,
}

# --------------------------------------------------
# MISSION TEMPLATES
# --------------------------------------------------
# enemy_profile fields:
#   leader_count   — number of enemy leaders (0 or 1 for missions)
#   unit_count_min — minimum enemy units (before scaling)
#   unit_count_max — maximum enemy units (before scaling)
#   unit_tier      — 1 | 2 | 3 (base tier before scaling)
#   roles          — Array of preferred roles for enemy unit selection
#   leader_pool    — "hostile" | "rescue_ally" | "none"
#   has_ally       — true for rescue missions (spawns allied Rising General)
#   ally_pool      — "rescue" (pool for the allied general)
#   scaling        — "player_power" (scale to player) | "fixed" (no scaling)
#
# reward_table fields:
#   xp_min / xp_max       — XP range on win
#   gold_min / gold_max   — gold reward range (0 = no gold)
#   item_chance           — 0.0–1.0 probability of item drop
#   item_tier_weight      — "standard" | "high" | "rare"
#   gem_chance            — probability of skill gem inside item roll
#   unit_capture          — true if unit capture rolls apply on win
#   leader_recruit        — true if a leader can be recruited on win
#   leader_recruit_chance — 0.0–1.0 (1.0 = guaranteed on hunt capture win)
#
# special_rule:
#   "none"                — no special behaviour
#   "rescue_protect"      — rescue mission: ally must survive for recruit
#   "boss_hp_zero_end"    — battle ends immediately when enemy leader hits 0 HP
#   "evasive_boss"        — enemy leader has Evasive trait
#   "split_formation"     — enemies spawn split across grid (not one formation)
#   "aggressive_open"     — enemy deploys near divider line regardless of playstyle

const TEMPLATES: Array = [

	# ════════════════════════════════════════════════
	# HUNT MISSIONS
	# ════════════════════════════════════════════════

	{
		"id":           "bandit_warlord",
		"display_name": "The Bandit Warlord",
		"mission_type": "hunt_capture",
		"risk_level":   "medium",
		"biomes":       ["plains", "desert", "tundra"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 30,
		"flavour":      "He built his warband from deserters and outcasts. Beaten in battle, he respects strength above all else.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 4,
			"unit_count_max": 6,
			"unit_tier":      1,
			"roles":          ["frontline", "shock"],
			"leader_pool":    "hostile",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              120,
			"xp_max":              180,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.20,
			"item_tier_weight":    "standard",
			"gem_chance":          0.0,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "boss_hp_zero_end",
	},

	{
		"id":           "rogue_knight",
		"display_name": "The Rogue Knight",
		"mission_type": "hunt_capture",
		"risk_level":   "medium_high",
		"biomes":       ["plains", "mountain", "forest"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 20,
		"flavour":      "A knight stripped of his title after refusing orders. He rides alone now, selling his blade to no one.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 2,
			"unit_count_max": 3,
			"unit_tier":      2,
			"roles":          ["cavalry"],
			"leader_pool":    "hostile",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              150,
			"xp_max":              220,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.30,
			"item_tier_weight":    "high",
			"gem_chance":          0.0,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "boss_hp_zero_end",
	},

	{
		"id":           "fallen_captain",
		"display_name": "The Fallen Captain",
		"mission_type": "hunt_capture",
		"risk_level":   "medium",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 2,
		"duration_max": 3,
		"spawn_weight": 30,
		"flavour":      "Once a respected commander. Now leads a loose band of sell-swords, drinking away whatever honour he had left.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 3,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["frontline", "ranged"],
			"leader_pool":    "hostile",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              100,
			"xp_max":              160,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.25,
			"item_tier_weight":    "standard",
			"gem_chance":          0.0,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "boss_hp_zero_end",
	},

	{
		"id":           "dark_duelist",
		"display_name": "The Dark Duelist",
		"mission_type": "hunt_capture",
		"risk_level":   "high",
		"biomes":       ["plains", "desert", "coast"],
		"duration_min": 3,
		"duration_max": 4,
		"spawn_weight": 20,
		"flavour":      "No one knows his real name. He has never lost a duel. He is beginning to wonder if that is a gift or a curse.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 1,
			"unit_count_max": 2,
			"unit_tier":      2,
			"roles":          ["skirmisher"],
			"leader_pool":    "hostile",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              200,
			"xp_max":              300,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.50,
			"sigil_chance":         0.20,
			"item_tier_weight":    "rare",
			"gem_chance":          0.05,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "evasive_boss",
	},

	{
		"id":           "rescue_captured_ranger",
		"display_name": "Rescue: The Captured Ranger",
		"mission_type": "hunt_rescue",
		"risk_level":   "medium",
		"biomes":       ["forest", "swamp", "tundra"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 15,
		"flavour":      "Captured during a scouting mission gone wrong. Still armed. Still dangerous.",
		"enemy_profile": {
			"leader_count":   0,
			"unit_count_min": 4,
			"unit_count_max": 6,
			"unit_tier":      1,
			"roles":          ["frontline", "ranged"],
			"leader_pool":    "none",
			"has_ally":       true,
			"ally_pool":      "rescue",
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              120,
			"xp_max":              180,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.20,
			"item_tier_weight":    "standard",
			"gem_chance":          0.0,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "rescue_protect",
	},

	{
		"id":           "rescue_exiled_general",
		"display_name": "Rescue: The Exiled General",
		"mission_type": "hunt_rescue",
		"risk_level":   "medium_high",
		"biomes":       ["plains", "mountain", "desert"],
		"duration_min": 4,
		"duration_max": 4,
		"spawn_weight": 10,
		"flavour":      "Exiled after being framed for a crime he did not commit. He wants nothing more than to fight under a worthy banner again.",
		"enemy_profile": {
			"leader_count":   0,
			"unit_count_min": 6,
			"unit_count_max": 8,
			"unit_tier":      2,
			"roles":          ["frontline", "shock", "tank"],
			"leader_pool":    "none",
			"has_ally":       true,
			"ally_pool":      "rescue",
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              180,
			"xp_max":              260,
			"gold_min":            0,
			"gold_max":            0,
			"item_chance":         0.35,
			"item_tier_weight":    "high",
			"gem_chance":          0.0,
			"unit_capture":        false,
			"leader_recruit":      true,
			"leader_recruit_chance": 1.0,
		},
		"special_rule": "rescue_protect",
	},

	# ════════════════════════════════════════════════
	# SKIRMISH MISSIONS
	# ════════════════════════════════════════════════

	{
		"id":           "border_clash",
		"display_name": "Border Clash",
		"mission_type": "skirmish",
		"risk_level":   "low",
		"biomes":       ["plains", "desert", "tundra"],
		"duration_min": 2,
		"duration_max": 2,
		"spawn_weight": 25,
		"flavour":      "A patrol from a rival settlement pushed too far across the border. Drive them back.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 3,
			"unit_count_max": 4,
			"unit_tier":      1,
			"roles":          ["frontline", "anti_cav_pike"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":              60,
			"xp_max":              100,
			"gold_min":            50,
			"gold_max":            100,
			"item_chance":         0.0,
			"item_tier_weight":    "standard",
			"gem_chance":          0.0,
			"unit_capture":        true,
			"leader_recruit":      false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "rogue_patrol",
		"display_name": "Rogue Patrol",
		"mission_type": "skirmish",
		"risk_level":   "low",
		"biomes":       ["plains", "forest", "coast"],
		"duration_min": 2,
		"duration_max": 2,
		"spawn_weight": 20,
		"flavour":      "A patrol gone rogue. They answer to no one now and raid whatever they please.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 2,
			"unit_count_max": 4,
			"unit_tier":      1,
			"roles":          ["cavalry", "skirmisher"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            50,
			"xp_max":            90,
			"gold_min":          40,
			"gold_max":          80,
			"item_chance":       0.0,
			"item_tier_weight":  "standard",
			"gem_chance":        0.0,
			"unit_capture":      true,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "militia_uprising",
		"display_name": "Militia Uprising",
		"mission_type": "skirmish",
		"risk_level":   "medium",
		"biomes":       ["plains", "coast", "desert"],
		"duration_min": 2,
		"duration_max": 3,
		"spawn_weight": 15,
		"flavour":      "The farmhands took up pitchforks. Someone gave them bad orders and now they are your problem.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 6,
			"unit_count_max": 8,
			"unit_tier":      1,
			"roles":          ["frontline", "frontline", "frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            80,
			"xp_max":            130,
			"gold_min":          60,
			"gold_max":          120,
			"item_chance":       0.0,
			"item_tier_weight":  "standard",
			"gem_chance":        0.0,
			"unit_capture":      true,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "raider_ambush",
		"display_name": "Raider Ambush",
		"mission_type": "skirmish",
		"risk_level":   "medium",
		"biomes":       ["forest", "tundra", "swamp"],
		"duration_min": 2,
		"duration_max": 3,
		"spawn_weight": 15,
		"flavour":      "Raiders hit hard and fast. If you survive the first charge, you have already won.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 4,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["shock", "cavalry"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            80,
			"xp_max":            130,
			"gold_min":          50,
			"gold_max":          100,
			"item_chance":       0.0,
			"item_tier_weight":  "standard",
			"gem_chance":        0.0,
			"unit_capture":      true,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "aggressive_open",
	},

	{
		"id":           "warband_skirmish",
		"display_name": "Warband Skirmish",
		"mission_type": "skirmish",
		"risk_level":   "medium",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 2,
		"duration_max": 3,
		"spawn_weight": 15,
		"flavour":      "A proper warband. Trained fighters between contracts looking for a fight.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 5,
			"unit_count_max": 6,
			"unit_tier":      1,
			"roles":          ["tank", "frontline", "ranged"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            90,
			"xp_max":            140,
			"gold_min":          60,
			"gold_max":          120,
			"item_chance":       0.0,
			"item_tier_weight":  "standard",
			"gem_chance":        0.0,
			"unit_capture":      true,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "scout_interception",
		"display_name": "Scout Interception",
		"mission_type": "skirmish",
		"risk_level":   "low",
		"biomes":       ["forest", "plains", "mountain"],
		"duration_min": 2,
		"duration_max": 2,
		"spawn_weight": 10,
		"flavour":      "They were watching your province. Stop them before they report back.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 2,
			"unit_count_max": 3,
			"unit_tier":      1,
			"roles":          ["skirmisher", "ranged"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            40,
			"xp_max":            70,
			"gold_min":          30,
			"gold_max":          60,
			"item_chance":       0.0,
			"item_tier_weight":  "standard",
			"gem_chance":        0.0,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	# ════════════════════════════════════════════════
	# TREASURE MISSIONS
	# ════════════════════════════════════════════════

	{
		"id":           "abandoned_caravan",
		"display_name": "Abandoned Caravan",
		"mission_type": "treasure",
		"risk_level":   "low",
		"biomes":       ["plains", "desert", "coast"],
		"duration_min": 2,
		"duration_max": 2,
		"spawn_weight": 30,
		"flavour":      "Attacked once already and left for dead on the road. Whatever is still in those crates is yours.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 2,
			"unit_count_max": 3,
			"unit_tier":      1,
			"roles":          ["frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            40,
			"xp_max":            70,
			"gold_min":          80,
			"gold_max":          150,
			"item_chance":       0.60,
			"item_tier_weight":  "standard",
			"gem_chance":        0.05,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "lost_supply_cache",
		"display_name": "Lost Supply Cache",
		"mission_type": "treasure",
		"risk_level":   "very_low",
		"biomes":       ["mountain", "tundra", "forest"],
		"duration_min": 2,
		"duration_max": 2,
		"spawn_weight": 25,
		"flavour":      "Military supplies that never reached their destination. Someone has been sitting on them hoping no one notices.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 1,
			"unit_count_max": 2,
			"unit_tier":      1,
			"roles":          ["frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            30,
			"xp_max":            50,
			"gold_min":          60,
			"gold_max":          120,
			"item_chance":       0.50,
			"item_tier_weight":  "standard",
			"gem_chance":        0.03,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "smuggler_hideout",
		"display_name": "Smuggler Hideout",
		"mission_type": "treasure",
		"risk_level":   "medium",
		"biomes":       ["coast", "swamp", "forest"],
		"duration_min": 2,
		"duration_max": 3,
		"spawn_weight": 20,
		"flavour":      "They move goods that are not supposed to exist. Their stock is impressive. Their loyalty to it is not.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 4,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["skirmisher", "frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            70,
			"xp_max":            110,
			"gold_min":          150,
			"gold_max":          280,
			"item_chance":       0.65,
			"item_tier_weight":  "standard",
			"gem_chance":        0.08,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "ruined_vault",
		"display_name": "Ruined Vault",
		"mission_type": "treasure",
		"risk_level":   "medium",
		"biomes":       ["mountain", "plains", "desert"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 15,
		"flavour":      "They built this vault to last forever. The builders are long gone. The things inside are not.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 4,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["tank", "anti_cav_pike"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            60,
			"xp_max":            100,
			"gold_min":          100,
			"gold_max":          200,
			"item_chance":       0.70,
			"item_tier_weight":  "high",
			"gem_chance":        0.10,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "buried_relic_site",
		"display_name": "Buried Relic Site",
		"mission_type": "treasure",
		"risk_level":   "medium",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 10,
		"flavour":      "Treasure hunters found something old. Then something found them. Now it is your turn.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 3,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["frontline", "ranged", "shock"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            80,
			"xp_max":            120,
			"gold_min":          80,
			"gold_max":          160,
			"item_chance":       0.70,
			"item_tier_weight":  "high",
			"gem_chance":        0.12,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "split_formation",
	},

	# ════════════════════════════════════════════════
	# ELITE MISSIONS
	# ════════════════════════════════════════════════

	{
		"id":           "veteran_mercenaries",
		"display_name": "The Veteran Mercenaries",
		"mission_type": "elite",
		"risk_level":   "high",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 3,
		"duration_max": 4,
		"spawn_weight": 40,
		"flavour":      "They have fought for every faction on this continent. They are not loyal. They are expensive. They are worth it.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 6,
			"unit_count_max": 7,
			"unit_tier":      2,
			"roles":          ["frontline", "tank", "ranged", "shock"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            250,
			"xp_max":            380,
			"gold_min":          200,
			"gold_max":          350,
			"item_chance":       0.70,
			"sigil_chance":         0.20,
			"item_tier_weight":  "high",
			"gem_chance":        0.05,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "champions_challenge",
		"display_name": "The Champion's Challenge",
		"mission_type": "elite",
		"risk_level":   "high",
		"biomes":       ["plains", "desert", "coast"],
		"duration_min": 3,
		"duration_max": 4,
		"spawn_weight": 30,
		"flavour":      "He left a banner on the road with a single challenge written on it. Most leaders ride past. A few do not.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 1,
			"unit_count_max": 2,
			"unit_tier":      3,
			"roles":          ["frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            280,
			"xp_max":            400,
			"gold_min":          150,
			"gold_max":          250,
			"item_chance":       1.0,
			"sigil_chance":         0.20,
			"item_tier_weight":  "rare",
			"gem_chance":        0.15,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "evasive_boss",
	},

	{
		"id":           "rival_commander",
		"display_name": "The Rival Commander",
		"mission_type": "elite",
		"risk_level":   "high",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 4,
		"duration_max": 4,
		"spawn_weight": 30,
		"flavour":      "He has been watching your expansion for months. He has decided it needs to end. Send your best.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 6,
			"unit_count_max": 8,
			"unit_tier":      2,
			"roles":          ["frontline", "tank", "ranged", "shock", "cavalry"],
			"leader_pool":    "hostile",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            300,
			"xp_max":            450,
			"gold_min":          200,
			"gold_max":          400,
			"item_chance":       0.80,
			"sigil_chance":         0.20,
			"item_tier_weight":  "rare",
			"gem_chance":        0.05,
			"unit_capture":      false,
			"leader_recruit":    true,
			"leader_recruit_chance": 0.10,
		},
		"special_rule": "boss_hp_zero_end",
	},

	{
		"id":           "ancient_guardian",
		"display_name": "The Ancient Guardian",
		"mission_type": "elite",
		"risk_level":   "high",
		"biomes":       ["mountain", "swamp", "forest", "tundra"],
		"duration_min": 3,
		"duration_max": 4,
		"spawn_weight": 20,
		"flavour":      "Something old guards that place. No one who has gone in unprepared has come back.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 4,
			"unit_count_max": 6,
			"unit_tier":      3,
			"roles":          ["tank", "frontline"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            280,
			"xp_max":            400,
			"gold_min":          150,
			"gold_max":          300,
			"item_chance":       0.90,
			"sigil_chance":         0.20,
			"item_tier_weight":  "rare",
			"gem_chance":        0.20,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "elite_warband",
		"display_name": "Elite Warband",
		"mission_type": "elite",
		"risk_level":   "high",
		"biomes":       ["plains", "forest", "coast", "desert", "tundra", "swamp", "mountain"],
		"duration_min": 3,
		"duration_max": 4,
		"spawn_weight": 25,
		"flavour":      "A full warband of hardened veterans. They do not negotiate. They do not retreat.",
		"enemy_profile": {
			"leader_count":   1,
			"unit_count_min": 6,
			"unit_count_max": 8,
			"unit_tier":      2,
			"roles":          ["frontline", "shock", "ranged"],
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "player_power",
		},
		"reward_table": {
			"xp_min":            260,
			"xp_max":            380,
			"gold_min":          180,
			"gold_max":          320,
			"item_chance":       0.65,
			"sigil_chance":         0.20,
			"item_tier_weight":  "high",
			"gem_chance":        0.05,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	# --------------------------------------------------
	# TUTORIAL MISSIONS — spawn once per faction, early game only
	# Each teaches one leg of the damage triangle
	# --------------------------------------------------
	{
		"id":           "tutorial_broken_armor",
		"display_name": "Broken Armor Line",
		"mission_type": "tutorial",
		"risk_level":   "low",
		"biomes":       ["plains", "forest", "mountain", "desert", "tundra", "swamp", "coast"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 1,
		"flavour":      "A line of heavily armored warriors blocks the road. Their shields are thick, but blunt weapons can crack them.",
		"hint":         "Blunt breaks armor — use hammers and maces against heavily armored enemies.",
		"enemy_profile": {
			"leader_count":   0,
			"unit_count_min": 4,
			"unit_count_max": 4,
			"unit_tier":      1,
			"roles":          ["tank"],
			"force_damage_type": "slash",
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "fixed",
		},
		"reward_table": {
			"xp_min":            60,
			"xp_max":            80,
			"gold_min":          30,
			"gold_max":          60,
			"item_chance":       0.0,
			"gem_chance":        0.0,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "tutorial_cavalry_threat",
		"display_name": "Cavalry Threat",
		"mission_type": "tutorial",
		"risk_level":   "low",
		"biomes":       ["plains", "forest", "mountain", "desert", "tundra", "swamp", "coast"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 1,
		"flavour":      "Mounted raiders are terrorizing the villages. Spears and lances will stop them cold.",
		"hint":         "Pierce counters cavalry — spears and lances are effective against mounted forces.",
		"enemy_profile": {
			"leader_count":   0,
			"unit_count_min": 3,
			"unit_count_max": 3,
			"unit_tier":      1,
			"roles":          ["cavalry"],
			"force_damage_type": "slash",
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "fixed",
		},
		"reward_table": {
			"xp_min":            60,
			"xp_max":            80,
			"gold_min":          30,
			"gold_max":          60,
			"item_chance":       0.0,
			"gem_chance":        0.0,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},

	{
		"id":           "tutorial_light_infantry",
		"display_name": "Light Infantry Rush",
		"mission_type": "tutorial",
		"risk_level":   "low",
		"biomes":       ["plains", "forest", "mountain", "desert", "tundra", "swamp", "coast"],
		"duration_min": 3,
		"duration_max": 3,
		"spawn_weight": 1,
		"flavour":      "Fast, unarmored skirmishers are swarming the road. Swords will tear through them.",
		"hint":         "Slash excels against light units — swords and blades tear through unarmored foes.",
		"enemy_profile": {
			"leader_count":   0,
			"unit_count_min": 5,
			"unit_count_max": 5,
			"unit_tier":      1,
			"roles":          ["skirmisher"],
			"force_damage_type": "pierce",
			"leader_pool":    "none",
			"has_ally":       false,
			"scaling":        "fixed",
		},
		"reward_table": {
			"xp_min":            60,
			"xp_max":            80,
			"gold_min":          30,
			"gold_max":          60,
			"item_chance":       0.0,
			"gem_chance":        0.0,
			"unit_capture":      false,
			"leader_recruit":    false,
			"leader_recruit_chance": 0.0,
		},
		"special_rule": "none",
	},
]

# --------------------------------------------------
# STATIC ACCESSORS
# --------------------------------------------------

static func get_template(template_id: String) -> Dictionary:
	for t in TEMPLATES:
		if str(t.get("id", "")) == template_id:
			return t as Dictionary
	return {}


static func get_templates_for_biome(biome: String) -> Array:
	var out: Array = []
	for t in TEMPLATES:
		var biomes: Array = t.get("biomes", []) as Array
		if biomes.has(biome):
			out.append(t)
	return out


static func get_templates_by_type(mission_type: String) -> Array:
	var out: Array = []
	for t in TEMPLATES:
		if str(t.get("mission_type", "")).begins_with(mission_type):
			out.append(t)
	return out


# Returns the broad type category for spawn weight rolling:
# hunt_capture / hunt_eliminate / hunt_rescue all count as "hunt"
static func get_type_category(mission_type: String) -> String:
	if mission_type.begins_with("hunt"):
		return "hunt"
	return mission_type
