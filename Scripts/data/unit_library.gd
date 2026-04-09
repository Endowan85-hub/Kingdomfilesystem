# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: UnitLibrary
#
# Role:
# Defines all recruitable unit types as static templates.
# Provides factory method to spawn a UnitData instance from a template.
# This is the single source of truth for unit stats, cp_cost, biome
# availability, damage type, and promotion paths.
#
# Allowed Interactions:
# - UnitData (creates instances)
# - GameState (called during recruitment to spawn units)
# - RecruitPanel (reads biome to filter available units)
#
# Forbidden Responsibilities:
# - Must not modify GameState directly
# - Must not queue orders
# - Must not interact with UI directly
#
# Game Phase:
# Both (read-only reference; spawning occurs during Execution Phase)
#
# Notes:
# - biome: Array of biome strings this unit can be recruited in.
#   Empty array means available everywhere (generic/neutral units).
# - damage_type: "slash" | "pierce" | "blunt"
# - tier: 1 = recruit, 2 = veteran, 3 = elite
# - promotes_to: unit_type string of promotion target ("" = none)
# - cp_cost: 5 = light, 7 = medium, 10 = heavy, 15 = elite
#
# Stat Audit — March 2026
# Stats are role-based with a fixed power budget per tier:
#   T1 budget: 30  (ATK + DEF + HP/5)
#   T2 budget: 43
#   T3 budget: 56
#
# Role profiles:
#   frontline     ATK 11/16/21  DEF 10/14/18  HP 45/65/84  — anchor, balanced
#   tank          ATK  8/12/15  DEF 13/18/24  HP 45/65/84  — wall, high def
#   ranged        ATK 17/25/32  DEF  5/ 7/10  HP 40/56/72  — glass cannon
#   shock         ATK 15/22/28  DEF  7/10/13  HP 41/58/76  — burst damage
#   cavalry       ATK 15/21/28  DEF  6/ 9/11  HP 45/65/80  — mobile, high risk
#   skirmisher    ATK 15/21/28  DEF  6/ 9/11  HP 45/65/80  — same as cavalry
#   anti_cav_pike ATK 10/14/18  DEF 11/16/21  HP 45/65/84  — defensive counter
#
# Damage type distribution T1: slash 42% / pierce 38% / blunt 21%
# Two new blunt shock lines added: Desert (Dust Crusher) and Coast (Dockhand Brawler)
# ==================================================
extends RefCounted
class_name UnitLibrary

const UnitData = preload("res://Scripts/data/unit_data.gd")

# --------------------------------------------------
# Unit Templates
# --------------------------------------------------
const UNIT_TEMPLATES: Array = [

	# ================================================
	# PLAINS
	# Balanced military tradition — combined arms
	# ================================================

	# Spearman Line (anti-cavalry pierce)
	{
		"unit_type": "Militia Spearman",
		"biome": ["plains"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 70,
		"upkeep_cost": 10,
		"speed": 3,
		"accuracy": 72,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 10,
		"defense": 11,
		"hp": 45,
		"skills": ["Brace"],
		"traits": ["Anti-Cavalry"],
		"promotes_to": "Veteran Spearman"
	},
	{
		"unit_type": "Veteran Spearman",
		"biome": ["plains"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 130,
		"upkeep_cost": 14,
		"speed": 3,
		"accuracy": 74,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 14,
		"defense": 16,
		"hp": 65,
		"skills": ["Brace", "Shield Wall"],
		"traits": ["Anti-Cavalry"],
		"promotes_to": "Elite Phalanx Guard"
	},
	{
		"unit_type": "Elite Phalanx Guard",
		"biome": ["plains"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 260,
		"upkeep_cost": 20,
		"speed": 4,
		"accuracy": 77,
		"evasion": 8,
		"damage_type": "pierce",
		"attack": 18,
		"defense": 21,
		"hp": 84,
		"skills": ["Brace", "Shield Wall", "Phalanx Lock"],
		"traits": ["Anti-Cavalry", "Stalwart"],
		"promotes_to": ""
	},

	# Swordsman Line (frontline slash)
	{
		"unit_type": "Militia Swordsman",
		"biome": ["plains"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 75,
		"evasion": 8,
		"damage_type": "slash",
		"attack": 11,
		"defense": 10,
		"hp": 45,
		"skills": ["Strike"],
		"traits": [],
		"promotes_to": "Veteran Infantry"
	},
	{
		"unit_type": "Veteran Infantry",
		"biome": ["plains"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 140,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 77,
		"evasion": 9,
		"damage_type": "slash",
		"attack": 16,
		"defense": 14,
		"hp": 65,
		"skills": ["Strike", "Counter"],
		"traits": [],
		"promotes_to": "Royal Guard"
	},
	{
		"unit_type": "Royal Guard",
		"biome": ["plains"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 280,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 80,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 21,
		"defense": 18,
		"hp": 84,
		"skills": ["Strike", "Counter", "Blade Fury"],
		"traits": ["Disciplined"],
		"promotes_to": ""
	},

	# Crossbow Line (ranged pierce — glass cannon)
	{
		"unit_type": "Militia Crossbowman",
		"biome": ["plains"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 90,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Volley"],
		"traits": ["Ranged"],
		"promotes_to": "Veteran Crossbowman"
	},
	{
		"unit_type": "Veteran Crossbowman",
		"biome": ["plains"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 160,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Volley", "Armor Pierce"],
		"traits": ["Ranged"],
		"promotes_to": "Master Arbalest"
	},
	{
		"unit_type": "Master Arbalest",
		"biome": ["plains"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 300,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Volley", "Armor Pierce", "Overload Shot"],
		"traits": ["Ranged", "Armor Piercing"],
		"promotes_to": ""
	},

	# Cavalry Line (mobility slash — high risk)
	{
		"unit_type": "Light Rider",
		"biome": ["plains"],
		"tier": 1,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 8,
		"accuracy": 65,
		"evasion": 15,
		"damage_type": "slash",
		"attack": 15,
		"defense": 6,
		"hp": 45,
		"skills": ["Charge"],
		"traits": ["Mounted", "Swift"],
		"promotes_to": "Cavalry"
	},
	{
		"unit_type": "Cavalry",
		"biome": ["plains"],
		"tier": 2,
		"cp_cost": 10,
		"gold_cost": 250,
		"upkeep_cost": 20,
		"speed": 8,
		"accuracy": 67,
		"evasion": 17,
		"damage_type": "slash",
		"attack": 21,
		"defense": 9,
		"hp": 65,
		"skills": ["Charge", "Trample"],
		"traits": ["Mounted", "Swift"],
		"promotes_to": "Elite Knight"
	},
	{
		"unit_type": "Elite Knight",
		"biome": ["plains"],
		"tier": 3,
		"cp_cost": 15,
		"gold_cost": 450,
		"upkeep_cost": 30,
		"speed": 9,
		"accuracy": 70,
		"evasion": 19,
		"damage_type": "slash",
		"attack": 28,
		"defense": 11,
		"hp": 80,
		"skills": ["Charge", "Trample", "Lance Charge"],
		"traits": ["Mounted", "Swift", "Terrifying"],
		"promotes_to": ""
	},

	# ================================================
	# FOREST
	# Mobility and ranged warfare
	# ================================================

	# Archer Line (ranged pierce — glass cannon)
	{
		"unit_type": "Hunter",
		"biome": ["forest"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Volley"],
		"traits": ["Ranged", "Forest Walker"],
		"promotes_to": "Ranger"
	},
	{
		"unit_type": "Ranger",
		"biome": ["forest"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Volley", "Pinning Shot"],
		"traits": ["Ranged", "Forest Walker", "Swift"],
		"promotes_to": "Master Ranger"
	},
	{
		"unit_type": "Master Ranger",
		"biome": ["forest"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 300,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Volley", "Pinning Shot", "Eagle Eye"],
		"traits": ["Ranged", "Forest Walker", "Swift", "Evasive"],
		"promotes_to": ""
	},

	# Skirmisher Line (slash — mobile harassment)
	{
		"unit_type": "Forest Skirmisher",
		"biome": ["forest"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 70,
		"upkeep_cost": 10,
		"speed": 7,
		"accuracy": 78,
		"evasion": 22,
		"damage_type": "slash",
		"attack": 15,
		"defense": 6,
		"hp": 45,
		"skills": ["Evade"],
		"traits": ["Swift", "Forest Walker"],
		"promotes_to": "Pathfinder"
	},
	{
		"unit_type": "Pathfinder",
		"biome": ["forest"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 130,
		"upkeep_cost": 14,
		"speed": 7,
		"accuracy": 80,
		"evasion": 24,
		"damage_type": "slash",
		"attack": 21,
		"defense": 9,
		"hp": 65,
		"skills": ["Evade", "Ambush"],
		"traits": ["Swift", "Forest Walker"],
		"promotes_to": "Shadow Ranger"
	},
	{
		"unit_type": "Shadow Ranger",
		"biome": ["forest"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 260,
		"upkeep_cost": 20,
		"speed": 8,
		"accuracy": 83,
		"evasion": 26,
		"damage_type": "slash",
		"attack": 28,
		"defense": 11,
		"hp": 80,
		"skills": ["Evade", "Ambush", "Shadow Strike"],
		"traits": ["Swift", "Forest Walker", "Evasive"],
		"promotes_to": ""
	},

	# Scout Rider Line (cavalry pierce — mobile)
	{
		"unit_type": "Forest Rider",
		"biome": ["forest"],
		"tier": 1,
		"cp_cost": 7,
		"gold_cost": 140,
		"upkeep_cost": 14,
		"speed": 8,
		"accuracy": 65,
		"evasion": 15,
		"damage_type": "pierce",
		"attack": 15,
		"defense": 6,
		"hp": 45,
		"skills": ["Scout"],
		"traits": ["Mounted", "Swift", "Forest Walker"],
		"promotes_to": "Scout Captain"
	},
	{
		"unit_type": "Scout Captain",
		"biome": ["forest"],
		"tier": 2,
		"cp_cost": 10,
		"gold_cost": 220,
		"upkeep_cost": 20,
		"speed": 8,
		"accuracy": 67,
		"evasion": 17,
		"damage_type": "pierce",
		"attack": 21,
		"defense": 9,
		"hp": 65,
		"skills": ["Scout", "Pursuit"],
		"traits": ["Mounted", "Swift", "Forest Walker"],
		"promotes_to": "Wild Hunt Commander"
	},
	{
		"unit_type": "Wild Hunt Commander",
		"biome": ["forest"],
		"tier": 3,
		"cp_cost": 15,
		"gold_cost": 400,
		"upkeep_cost": 30,
		"speed": 9,
		"accuracy": 70,
		"evasion": 19,
		"damage_type": "pierce",
		"attack": 28,
		"defense": 11,
		"hp": 80,
		"skills": ["Scout", "Pursuit", "Wild Charge"],
		"traits": ["Mounted", "Swift", "Forest Walker", "Inspiring"],
		"promotes_to": ""
	},

	# ================================================
	# MOUNTAIN
	# Defensive warfare — high durability
	# ================================================

	# Shield Guard Line (tank blunt — wall)
	{
		"unit_type": "Mountain Guard",
		"biome": ["mountain"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 90,
		"upkeep_cost": 10,
		"speed": 2,
		"accuracy": 60,
		"evasion": 5,
		"damage_type": "blunt",
		"attack": 8,
		"defense": 13,
		"hp": 45,
		"skills": ["Shield Wall"],
		"traits": ["Stalwart"],
		"promotes_to": "Veteran Shield Guard"
	},
	{
		"unit_type": "Veteran Shield Guard",
		"biome": ["mountain"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 170,
		"upkeep_cost": 14,
		"speed": 2,
		"accuracy": 62,
		"evasion": 6,
		"damage_type": "blunt",
		"attack": 12,
		"defense": 18,
		"hp": 65,
		"skills": ["Shield Wall", "Hold Ground"],
		"traits": ["Stalwart", "Resilient"],
		"promotes_to": "Iron Phalanx"
	},
	{
		"unit_type": "Iron Phalanx",
		"biome": ["mountain"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 320,
		"upkeep_cost": 20,
		"speed": 3,
		"accuracy": 65,
		"evasion": 8,
		"damage_type": "blunt",
		"attack": 15,
		"defense": 24,
		"hp": 84,
		"skills": ["Shield Wall", "Hold Ground", "Immovable"],
		"traits": ["Stalwart", "Resilient", "Anti-Cavalry"],
		"promotes_to": ""
	},

	# Hammer Infantry Line (shock blunt — anti-armor burst)
	{
		"unit_type": "Stonebreaker",
		"biome": ["mountain"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 100,
		"upkeep_cost": 10,
		"speed": 5,
		"accuracy": 68,
		"evasion": 10,
		"damage_type": "blunt",
		"attack": 15,
		"defense": 7,
		"hp": 41,
		"skills": ["Crush"],
		"traits": ["Armor Breaker"],
		"promotes_to": "War Hammer Guard"
	},
	{
		"unit_type": "War Hammer Guard",
		"biome": ["mountain"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 190,
		"upkeep_cost": 14,
		"speed": 5,
		"accuracy": 70,
		"evasion": 11,
		"damage_type": "blunt",
		"attack": 22,
		"defense": 10,
		"hp": 58,
		"skills": ["Crush", "Shatter"],
		"traits": ["Armor Breaker"],
		"promotes_to": "Titan Guard"
	},
	{
		"unit_type": "Titan Guard",
		"biome": ["mountain"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 360,
		"upkeep_cost": 20,
		"speed": 6,
		"accuracy": 73,
		"evasion": 12,
		"damage_type": "blunt",
		"attack": 28,
		"defense": 13,
		"hp": 76,
		"skills": ["Crush", "Shatter", "Earthquake Strike"],
		"traits": ["Armor Breaker", "Terrifying"],
		"promotes_to": ""
	},

	# Pike Line (anti-cavalry pierce — defensive counter)
	{
		"unit_type": "Mountain Pikeman",
		"biome": ["mountain"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 3,
		"accuracy": 72,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 10,
		"defense": 11,
		"hp": 45,
		"skills": ["Brace"],
		"traits": ["Anti-Cavalry"],
		"promotes_to": "Veteran Pikeman"
	},
	{
		"unit_type": "Veteran Pikeman",
		"biome": ["mountain"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 3,
		"accuracy": 74,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 14,
		"defense": 16,
		"hp": 65,
		"skills": ["Brace", "Repel"],
		"traits": ["Anti-Cavalry", "Stalwart"],
		"promotes_to": "Fortress Sentinel"
	},
	{
		"unit_type": "Fortress Sentinel",
		"biome": ["mountain"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 290,
		"upkeep_cost": 20,
		"speed": 4,
		"accuracy": 77,
		"evasion": 8,
		"damage_type": "pierce",
		"attack": 18,
		"defense": 21,
		"hp": 84,
		"skills": ["Brace", "Repel", "Sentinel Stance"],
		"traits": ["Anti-Cavalry", "Stalwart", "Disciplined"],
		"promotes_to": ""
	},

	# ================================================
	# DESERT
	# Mobility and raiding — aggressive shock
	# ================================================

	# Raider Line (cavalry slash — high risk mobile)
	{
		"unit_type": "Sand Raider",
		"biome": ["desert"],
		"tier": 1,
		"cp_cost": 7,
		"gold_cost": 130,
		"upkeep_cost": 14,
		"speed": 8,
		"accuracy": 65,
		"evasion": 15,
		"damage_type": "slash",
		"attack": 15,
		"defense": 6,
		"hp": 45,
		"skills": ["Raid"],
		"traits": ["Mounted", "Swift"],
		"promotes_to": "Veteran Raider"
	},
	{
		"unit_type": "Veteran Raider",
		"biome": ["desert"],
		"tier": 2,
		"cp_cost": 10,
		"gold_cost": 230,
		"upkeep_cost": 20,
		"speed": 8,
		"accuracy": 67,
		"evasion": 17,
		"damage_type": "slash",
		"attack": 21,
		"defense": 9,
		"hp": 65,
		"skills": ["Raid", "Overrun"],
		"traits": ["Mounted", "Swift"],
		"promotes_to": "Desert Warlord"
	},
	{
		"unit_type": "Desert Warlord",
		"biome": ["desert"],
		"tier": 3,
		"cp_cost": 15,
		"gold_cost": 420,
		"upkeep_cost": 30,
		"speed": 9,
		"accuracy": 70,
		"evasion": 19,
		"damage_type": "slash",
		"attack": 28,
		"defense": 11,
		"hp": 80,
		"skills": ["Raid", "Overrun", "Blood Frenzy"],
		"traits": ["Mounted", "Swift", "Terrifying"],
		"promotes_to": ""
	},

	# Caravan Guard Line (frontline slash — anchor)
	{
		"unit_type": "Caravan Guard",
		"biome": ["desert"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 75,
		"evasion": 8,
		"damage_type": "slash",
		"attack": 11,
		"defense": 10,
		"hp": 45,
		"skills": ["Shield Wall"],
		"traits": ["Resilient"],
		"promotes_to": "Veteran Guard"
	},
	{
		"unit_type": "Veteran Guard",
		"biome": ["desert"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 77,
		"evasion": 9,
		"damage_type": "slash",
		"attack": 16,
		"defense": 14,
		"hp": 65,
		"skills": ["Shield Wall", "Counter"],
		"traits": ["Resilient", "Stalwart"],
		"promotes_to": "Desert Captain"
	},
	{
		"unit_type": "Desert Captain",
		"biome": ["desert"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 280,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 80,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 21,
		"defense": 18,
		"hp": 84,
		"skills": ["Shield Wall", "Counter", "Commander's Resolve"],
		"traits": ["Resilient", "Stalwart", "Inspiring"],
		"promotes_to": ""
	},

	# Desert Archer Line (ranged pierce — glass cannon)
	{
		"unit_type": "Dune Archer",
		"biome": ["desert"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 85,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Volley"],
		"traits": ["Ranged", "Swift"],
		"promotes_to": "Veteran Archer"
	},
	{
		"unit_type": "Veteran Archer",
		"biome": ["desert"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 155,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Volley", "Harass"],
		"traits": ["Ranged", "Swift"],
		"promotes_to": "Sandstorm Sniper"
	},
	{
		"unit_type": "Sandstorm Sniper",
		"biome": ["desert"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 300,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Volley", "Harass", "Blinding Shot"],
		"traits": ["Ranged", "Swift", "Evasive"],
		"promotes_to": ""
	},

	# Dust Crusher Line (shock blunt — heavy weapon raiders)
	{
		"unit_type": "Dust Crusher",
		"biome": ["desert"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 100,
		"upkeep_cost": 10,
		"speed": 5,
		"accuracy": 68,
		"evasion": 10,
		"damage_type": "blunt",
		"attack": 15,
		"defense": 7,
		"hp": 41,
		"skills": ["Crush"],
		"traits": ["Armor Breaker"],
		"promotes_to": "Sand Breaker"
	},
	{
		"unit_type": "Sand Breaker",
		"biome": ["desert"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 190,
		"upkeep_cost": 14,
		"speed": 5,
		"accuracy": 70,
		"evasion": 11,
		"damage_type": "blunt",
		"attack": 22,
		"defense": 10,
		"hp": 58,
		"skills": ["Crush", "Shatter"],
		"traits": ["Armor Breaker"],
		"promotes_to": "Stone Fist"
	},
	{
		"unit_type": "Stone Fist",
		"biome": ["desert"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 360,
		"upkeep_cost": 20,
		"speed": 6,
		"accuracy": 73,
		"evasion": 12,
		"damage_type": "blunt",
		"attack": 28,
		"defense": 13,
		"hp": 76,
		"skills": ["Crush", "Shatter", "Earthquake Strike"],
		"traits": ["Armor Breaker", "Terrifying"],
		"promotes_to": ""
	},

	# ================================================
	# TUNDRA
	# High morale endurance fighters
	# ================================================

	# Frost Warrior Line (frontline slash — resilient anchor)
	{
		"unit_type": "Ice Warrior",
		"biome": ["tundra"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 85,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 75,
		"evasion": 8,
		"damage_type": "slash",
		"attack": 11,
		"defense": 10,
		"hp": 45,
		"skills": ["Endure"],
		"traits": ["Cold Resistant", "Resilient"],
		"promotes_to": "Veteran Frost Warrior"
	},
	{
		"unit_type": "Veteran Frost Warrior",
		"biome": ["tundra"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 160,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 77,
		"evasion": 9,
		"damage_type": "slash",
		"attack": 16,
		"defense": 14,
		"hp": 65,
		"skills": ["Endure", "Frost Strike"],
		"traits": ["Cold Resistant", "Resilient", "Stalwart"],
		"promotes_to": "Frost Champion"
	},
	{
		"unit_type": "Frost Champion",
		"biome": ["tundra"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 310,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 80,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 21,
		"defense": 18,
		"hp": 84,
		"skills": ["Endure", "Frost Strike", "Glacial Wrath"],
		"traits": ["Cold Resistant", "Resilient", "Stalwart", "Inspiring"],
		"promotes_to": ""
	},

	# Ice Archer Line (ranged pierce — glass cannon)
	{
		"unit_type": "Ice Archer",
		"biome": ["tundra"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Volley"],
		"traits": ["Ranged", "Cold Resistant"],
		"promotes_to": "Veteran Ice Archer"
	},
	{
		"unit_type": "Veteran Ice Archer",
		"biome": ["tundra"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Volley", "Chill Shot"],
		"traits": ["Ranged", "Cold Resistant"],
		"promotes_to": "Blizzard Ranger"
	},
	{
		"unit_type": "Blizzard Ranger",
		"biome": ["tundra"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 290,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Volley", "Chill Shot", "Blizzard Barrage"],
		"traits": ["Ranged", "Cold Resistant", "Evasive"],
		"promotes_to": ""
	},

	# Northern Raider Line (shock slash — aggressive melee)
	{
		"unit_type": "Northern Raider",
		"biome": ["tundra"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 90,
		"upkeep_cost": 10,
		"speed": 5,
		"accuracy": 68,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 15,
		"defense": 7,
		"hp": 41,
		"skills": ["Berserk"],
		"traits": ["Cold Resistant"],
		"promotes_to": "Veteran Raider (Tundra)"
	},
	{
		"unit_type": "Veteran Raider (Tundra)",
		"biome": ["tundra"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 170,
		"upkeep_cost": 14,
		"speed": 5,
		"accuracy": 70,
		"evasion": 11,
		"damage_type": "slash",
		"attack": 22,
		"defense": 10,
		"hp": 58,
		"skills": ["Berserk", "Savage Blow"],
		"traits": ["Cold Resistant", "Resilient"],
		"promotes_to": "War Chief"
	},
	{
		"unit_type": "War Chief",
		"biome": ["tundra"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 320,
		"upkeep_cost": 20,
		"speed": 6,
		"accuracy": 73,
		"evasion": 12,
		"damage_type": "slash",
		"attack": 28,
		"defense": 13,
		"hp": 76,
		"skills": ["Berserk", "Savage Blow", "War Cry"],
		"traits": ["Cold Resistant", "Resilient", "Terrifying", "Inspiring"],
		"promotes_to": ""
	},

	# ================================================
	# SWAMP
	# Ambush and terrain control
	# ================================================

	# Bog Fighter Line (tank blunt — durable wall)
	{
		"unit_type": "Bog Fighter",
		"biome": ["swamp"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 75,
		"upkeep_cost": 10,
		"speed": 2,
		"accuracy": 60,
		"evasion": 5,
		"damage_type": "blunt",
		"attack": 8,
		"defense": 13,
		"hp": 45,
		"skills": ["Endure"],
		"traits": ["Swamp Walker", "Resilient"],
		"promotes_to": "Veteran Bog Fighter"
	},
	{
		"unit_type": "Veteran Bog Fighter",
		"biome": ["swamp"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 145,
		"upkeep_cost": 14,
		"speed": 2,
		"accuracy": 62,
		"evasion": 6,
		"damage_type": "blunt",
		"attack": 12,
		"defense": 18,
		"hp": 65,
		"skills": ["Endure", "Mire Strike"],
		"traits": ["Swamp Walker", "Resilient", "Stalwart"],
		"promotes_to": "Mire Champion"
	},
	{
		"unit_type": "Mire Champion",
		"biome": ["swamp"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 280,
		"upkeep_cost": 20,
		"speed": 3,
		"accuracy": 65,
		"evasion": 8,
		"damage_type": "blunt",
		"attack": 15,
		"defense": 24,
		"hp": 84,
		"skills": ["Endure", "Mire Strike", "Bog Crush"],
		"traits": ["Swamp Walker", "Resilient", "Stalwart"],
		"promotes_to": ""
	},

	# Reed Archer Line (ranged pierce — glass cannon)
	{
		"unit_type": "Reed Archer",
		"biome": ["swamp"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Volley"],
		"traits": ["Ranged", "Swamp Walker"],
		"promotes_to": "Veteran Reed Archer"
	},
	{
		"unit_type": "Veteran Reed Archer",
		"biome": ["swamp"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 150,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Volley", "Ambush Shot"],
		"traits": ["Ranged", "Swamp Walker", "Evasive"],
		"promotes_to": "Marsh Sniper"
	},
	{
		"unit_type": "Marsh Sniper",
		"biome": ["swamp"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 290,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Volley", "Ambush Shot", "Death from the Reeds"],
		"traits": ["Ranged", "Swamp Walker", "Evasive"],
		"promotes_to": ""
	},

	# Ambusher Line (skirmisher slash — mobile harassment)
	{
		"unit_type": "Swamp Ambusher",
		"biome": ["swamp"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 70,
		"upkeep_cost": 10,
		"speed": 7,
		"accuracy": 78,
		"evasion": 22,
		"damage_type": "slash",
		"attack": 15,
		"defense": 6,
		"hp": 45,
		"skills": ["Ambush"],
		"traits": ["Swift", "Swamp Walker"],
		"promotes_to": "Veteran Ambusher"
	},
	{
		"unit_type": "Veteran Ambusher",
		"biome": ["swamp"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 140,
		"upkeep_cost": 14,
		"speed": 7,
		"accuracy": 80,
		"evasion": 24,
		"damage_type": "slash",
		"attack": 21,
		"defense": 9,
		"hp": 65,
		"skills": ["Ambush", "Shadow Strike"],
		"traits": ["Swift", "Swamp Walker", "Evasive"],
		"promotes_to": "Mire Stalker"
	},
	{
		"unit_type": "Mire Stalker",
		"biome": ["swamp"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 270,
		"upkeep_cost": 20,
		"speed": 8,
		"accuracy": 83,
		"evasion": 26,
		"damage_type": "slash",
		"attack": 28,
		"defense": 11,
		"hp": 80,
		"skills": ["Ambush", "Shadow Strike", "Phantom Step"],
		"traits": ["Swift", "Swamp Walker", "Evasive"],
		"promotes_to": ""
	},

	# ================================================
	# COAST
	# Flexible marine forces
	# ================================================

	# Marine Line (frontline slash — balanced anchor)
	{
		"unit_type": "Marine",
		"biome": ["coast"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 85,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 75,
		"evasion": 8,
		"damage_type": "slash",
		"attack": 11,
		"defense": 10,
		"hp": 45,
		"skills": ["Strike"],
		"traits": ["Seafarer"],
		"promotes_to": "Veteran Marine"
	},
	{
		"unit_type": "Veteran Marine",
		"biome": ["coast"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 160,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 77,
		"evasion": 9,
		"damage_type": "slash",
		"attack": 16,
		"defense": 14,
		"hp": 65,
		"skills": ["Strike", "Boarding Rush"],
		"traits": ["Seafarer", "Resilient"],
		"promotes_to": "Harbor Guard"
	},
	{
		"unit_type": "Harbor Guard",
		"biome": ["coast"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 300,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 80,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 21,
		"defense": 18,
		"hp": 84,
		"skills": ["Strike", "Boarding Rush", "Tidal Bulwark"],
		"traits": ["Seafarer", "Resilient", "Stalwart"],
		"promotes_to": ""
	},

	# Harpoon Line (ranged pierce — glass cannon)
	{
		"unit_type": "Harpoon Fighter",
		"biome": ["coast"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 90,
		"upkeep_cost": 10,
		"speed": 4,
		"accuracy": 88,
		"evasion": 5,
		"damage_type": "pierce",
		"attack": 17,
		"defense": 5,
		"hp": 40,
		"skills": ["Harpoon Throw"],
		"traits": ["Ranged", "Seafarer"],
		"promotes_to": "Veteran Harpooner"
	},
	{
		"unit_type": "Veteran Harpooner",
		"biome": ["coast"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 170,
		"upkeep_cost": 14,
		"speed": 4,
		"accuracy": 90,
		"evasion": 6,
		"damage_type": "pierce",
		"attack": 25,
		"defense": 7,
		"hp": 56,
		"skills": ["Harpoon Throw", "Reel In"],
		"traits": ["Ranged", "Seafarer"],
		"promotes_to": "Leviathan Hunter"
	},
	{
		"unit_type": "Leviathan Hunter",
		"biome": ["coast"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 320,
		"upkeep_cost": 20,
		"speed": 5,
		"accuracy": 92,
		"evasion": 7,
		"damage_type": "pierce",
		"attack": 32,
		"defense": 10,
		"hp": 72,
		"skills": ["Harpoon Throw", "Reel In", "Leviathan Strike"],
		"traits": ["Ranged", "Seafarer", "Armor Piercing"],
		"promotes_to": ""
	},

	# Boarding Infantry Line (shock slash — aggressive close combat)
	{
		"unit_type": "Boarding Infantry",
		"biome": ["coast"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 80,
		"upkeep_cost": 10,
		"speed": 5,
		"accuracy": 68,
		"evasion": 10,
		"damage_type": "slash",
		"attack": 15,
		"defense": 7,
		"hp": 41,
		"skills": ["Boarding Rush"],
		"traits": ["Seafarer", "Swift"],
		"promotes_to": "Veteran Boarding Guard"
	},
	{
		"unit_type": "Veteran Boarding Guard",
		"biome": ["coast"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 155,
		"upkeep_cost": 14,
		"speed": 5,
		"accuracy": 70,
		"evasion": 11,
		"damage_type": "slash",
		"attack": 22,
		"defense": 10,
		"hp": 58,
		"skills": ["Boarding Rush", "Cutlass Flurry"],
		"traits": ["Seafarer", "Swift"],
		"promotes_to": "Sea Captain Guard"
	},
	{
		"unit_type": "Sea Captain Guard",
		"biome": ["coast"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 290,
		"upkeep_cost": 20,
		"speed": 6,
		"accuracy": 73,
		"evasion": 12,
		"damage_type": "slash",
		"attack": 28,
		"defense": 13,
		"hp": 76,
		"skills": ["Boarding Rush", "Cutlass Flurry", "Captain's Command"],
		"traits": ["Seafarer", "Swift", "Inspiring"],
		"promotes_to": ""
	},

	# Dockhand Brawler Line (shock blunt — dock brawlers, tight quarters)
	{
		"unit_type": "Dockhand Brawler",
		"biome": ["coast"],
		"tier": 1,
		"cp_cost": 5,
		"gold_cost": 100,
		"upkeep_cost": 10,
		"speed": 5,
		"accuracy": 68,
		"evasion": 10,
		"damage_type": "blunt",
		"attack": 15,
		"defense": 7,
		"hp": 41,
		"skills": ["Crush"],
		"traits": ["Armor Breaker", "Seafarer"],
		"promotes_to": "Harbor Crusher"
	},
	{
		"unit_type": "Harbor Crusher",
		"biome": ["coast"],
		"tier": 2,
		"cp_cost": 7,
		"gold_cost": 190,
		"upkeep_cost": 14,
		"speed": 5,
		"accuracy": 70,
		"evasion": 11,
		"damage_type": "blunt",
		"attack": 22,
		"defense": 10,
		"hp": 58,
		"skills": ["Crush", "Shatter"],
		"traits": ["Armor Breaker", "Seafarer"],
		"promotes_to": "Tidal Breaker"
	},
	{
		"unit_type": "Tidal Breaker",
		"biome": ["coast"],
		"tier": 3,
		"cp_cost": 10,
		"gold_cost": 360,
		"upkeep_cost": 20,
		"speed": 6,
		"accuracy": 73,
		"evasion": 12,
		"damage_type": "blunt",
		"attack": 28,
		"defense": 13,
		"hp": 76,
		"skills": ["Crush", "Shatter", "Tidal Slam"],
		"traits": ["Armor Breaker", "Seafarer", "Terrifying"],
		"promotes_to": ""
	},
]

# --------------------------------------------------
# Lookup
# --------------------------------------------------

static func get_template(unit_type: String) -> Dictionary:
	for tpl in UNIT_TEMPLATES:
		if str(tpl["unit_type"]) == unit_type:
			return tpl
	return {}


static func get_all_types() -> Array[String]:
	var out: Array[String] = []
	for tpl in UNIT_TEMPLATES:
		out.append(str(tpl["unit_type"]))
	return out


static func get_types_for_biome(biome: String) -> Array[String]:
	var out: Array[String] = []
	for tpl in UNIT_TEMPLATES:
		var b = tpl.get("biome", [])
		if (b as Array).is_empty() or (b as Array).has(biome):
			# Only show tier 1 units for recruitment (no leader level context)
			if int(tpl.get("tier", 1)) == 1:
				out.append(str(tpl["unit_type"]))
	return out


# Returns recruitable unit types for a biome gated by leader level.
# Tier unlock thresholds:
#   Tier 1 (recruit):  always available
#   Tier 2 (veteran):  leader level >= 5
#   Tier 3 (elite):    leader level >= 10
static func get_types_for_biome_at_leader_level(biome: String, leader_level: int) -> Array[String]:
	var max_tier: int = 1
	if leader_level >= 10:
		max_tier = 3
	elif leader_level >= 5:
		max_tier = 2
	var out: Array[String] = []
	for tpl in UNIT_TEMPLATES:
		var b = tpl.get("biome", [])
		if (b as Array).is_empty() or (b as Array).has(biome):
			if int(tpl.get("tier", 1)) <= max_tier:
				out.append(str(tpl["unit_type"]))
	return out


static func is_valid_type(unit_type: String) -> bool:
	for tpl in UNIT_TEMPLATES:
		if str(tpl["unit_type"]) == unit_type:
			return true
	return false


static func get_gold_cost(unit_type: String) -> int:
	var tpl: Dictionary = get_template(unit_type)
	return int(tpl.get("gold_cost", 0))


static func get_promotion(unit_type: String) -> String:
	var tpl: Dictionary = get_template(unit_type)
	return str(tpl.get("promotes_to", ""))


# --------------------------------------------------
# Sigil Tag Inference
# --------------------------------------------------
# Infers allowed_tags for a unit based on its template's damage_type and traits.
# Tags must match sigil categories defined in SigilLibrary.
# Rules:
#   damage_type "slash"  → ["slash", "melee"]
#   damage_type "pierce" + Ranged trait → ["pierce", "ranged"]
#   damage_type "pierce" (no Ranged)   → ["pierce", "melee"]
#   damage_type "blunt"  → ["blunt", "melee"]
#   Mounted trait        → adds "cavalry"
#   Anti-Cavalry trait   → adds "anti_cav"
#   Armor Breaker trait  → adds "armor_breaker"
static func get_allowed_tags(unit_type: String) -> Array[String]:
	var tpl: Dictionary = get_template(unit_type)
	if tpl.is_empty():
		return []

	var tags: Array[String] = []
	var dtype: String = str(tpl.get("damage_type", "slash"))
	var traits_arr: Array = tpl.get("traits", [])
	var has_ranged: bool = (traits_arr as Array).has("Ranged")
	var has_mounted: bool = (traits_arr as Array).has("Mounted")
	var has_anti_cav: bool = (traits_arr as Array).has("Anti-Cavalry")
	var has_armor_breaker: bool = (traits_arr as Array).has("Armor Breaker")

	tags.append(dtype)
	if has_ranged:
		tags.append("ranged")
	else:
		tags.append("melee")
	if has_mounted:
		tags.append("cavalry")
	if has_anti_cav:
		tags.append("anti_cav")
	if has_armor_breaker:
		tags.append("armor_breaker")

	return tags


# --------------------------------------------------
# Factory
# --------------------------------------------------

# --------------------------------------------------
# UNIT NAME POOL
# Personal names assigned at recruitment. Pool is large enough
# that collisions within a single army are uncommon.
# Seeded by unit_id so names are deterministic across saves.
# --------------------------------------------------
const UNIT_NAMES: Array[String] = [
	"Aldric", "Vorn", "Brant", "Kael", "Dorn", "Rook", "Gareth", "Cato",
	"Oswin", "Hadrin", "Jorin", "Alaric", "Draven", "Finn", "Wulf", "Calder",
	"Brek", "Torvin", "Hask", "Edric", "Renn", "Corvin", "Arval", "Thane",
	"Berin", "Orik", "Davan", "Sylk", "Fen", "Rowan", "Holt", "Cass",
	"Iver", "Pell", "Stenn", "Varr", "Dex", "Orm", "Keld", "Aren",
	"Tavish", "Bael", "Coran", "Drask", "Hann", "Ferric", "Orin", "Vex",
	"Caric", "Zael", "Tarn", "Gryn", "Selk", "Ivel", "Brynn", "Merin",
	"Garn", "Aldrin", "Breck", "Torren", "Kavin", "Daven", "Osric", "Halden",
	"Wren", "Corin", "Edran", "Valdric", "Sorn", "Balen", "Harwin", "Cavel",
	"Drust", "Aldran", "Roran", "Kelvin", "Boran", "Torval", "Aiden", "Garwin",
	"Eldric", "Harlan", "Davrin", "Orrin", "Keldan", "Brogen", "Cavin", "Torkin",
	"Aldwin", "Harvin", "Dorin", "Kelron", "Brogan", "Cavrin", "Gordin", "Aldvan",
]

static func _generate_unit_name(unit_id: int) -> String:
	# Use unit_id as seed for deterministic name selection.
	# XOR shuffle spreads ids across the pool to avoid sequential clustering.
	var idx: int = (unit_id * 2654435761) % UNIT_NAMES.size()
	return UNIT_NAMES[absi(idx)]

static func create_unit(unit_type: String, unit_id: int) -> UnitData:
	var tpl: Dictionary = get_template(unit_type)
	if tpl.is_empty():
		push_warning("UnitLibrary: unknown unit_type '%s'" % unit_type)
		return null

	var u := UnitData.new()
	u.unit_id = unit_id
	u.unit_type = unit_type
	u.level = 1
	u.xp = 0
	u.xp_to_next_level = 100
	u.attack = int(tpl.get("attack", 3))
	u.defense = int(tpl.get("defense", 3))
	u.max_hp = int(tpl.get("hp", 10))
	u.hp = u.max_hp
	u.cp_cost = int(tpl.get("cp_cost", 5))
	u.upkeep_cost = int(tpl.get("upkeep_cost", 10))
	u.damage_type = str(tpl.get("damage_type", "slash"))
	u.tier = int(tpl.get("tier", 1))
	u.speed = int(tpl.get("speed", 4))
	u.accuracy = int(tpl.get("accuracy", 75))
	u.evasion = int(tpl.get("evasion", 8))
	u.skills = _copy_string_array(tpl.get("skills", []))
	u.traits = _copy_string_array(tpl.get("traits", []))
	u.allowed_tags = get_allowed_tags(unit_type)
	u.unit_name = _generate_unit_name(unit_id)
	u.owner_leader_id = -1
	u.province_id = -1
	return u


static func _copy_string_array(src) -> Array[String]:
	var out: Array[String] = []
	if src is Array:
		for item in src:
			out.append(str(item))
	return out
