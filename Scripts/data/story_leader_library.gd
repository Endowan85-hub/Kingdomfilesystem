# ==================================================
# SYSTEM CONTRACT
# --------------------------------------------------
# System: StoryLeaderLibrary
#
# Role:
# Provides the authored strategic-layer story leader roster and assigns those
# leaders to their matching named factions for a generated campaign.
# Each story leader corresponds to one of the 15 great houses of the realm.
#
# Allowed Interactions:
# - GameState initialization
# - MapData / ProvinceData / FactionData (read-only)
# - LeaderData template generation
#
# Forbidden Responsibilities:
# - Must not mutate GameState directly
# - Must not queue orders
# - Must not interact with UI
# - Must not execute turn logic
#
# Game Phase:
# Planning Phase (campaign initialization)
#
# Notes:
# - Each story leader is tied to a faction by faction_key, which maps to
#   FactionData.faction_key set during map generation.
# - Stats reflect each leader's lore role on a 1-10 scale.
# - unit_archetype is metadata for future tactical layer use.
# - ai_playstyle drives AIPlanner behavior per faction.
# - Reserve generals are authored templates used for mission/story growth.
# - Reserve pool target increased for 40-province campaigns and long-form
#   mission recruitment pacing.
# ==================================================
class_name StoryLeaderLibrary
extends RefCounted

const STORY_ROSTER: Array = [
	{"story_id":"house_counsel","display_name":"The Unifier","faction_key":"house_counsel","leadership":22,"attack":12,"defense":16,"damage_type":"blunt","speed":4,"accuracy":68,"evasion":8,"traits":["Strategist","Inspiring","Diplomat"],"unit_archetype":"Grand Strategist","ai_playstyle":"diplomatic"},
	{"story_id":"house_war","display_name":"The General","faction_key":"house_war","leadership":20,"attack":24,"defense":18,"damage_type":"slash","speed":5,"accuracy":75,"evasion":10,"traits":["Brave","Inspiring","Disciplined"],"unit_archetype":"High Marshal","ai_playstyle":"aggressive"},
	{"story_id":"house_crown","display_name":"The Heir","faction_key":"house_crown","leadership":18,"attack":16,"defense":18,"damage_type":"slash","speed":5,"accuracy":73,"evasion":12,"traits":["Inspiring","Guardian","Noble"],"unit_archetype":"Banner Lord","ai_playstyle":"balanced"},
	{"story_id":"house_coin","display_name":"The Merchant","faction_key":"house_coin","leadership":16,"attack":12,"defense":14,"damage_type":"pierce","speed":3,"accuracy":65,"evasion":8,"traits":["Greedy","Strategist","Resourceful"],"unit_archetype":"Guildmaster","ai_playstyle":"economic"},
	{"story_id":"house_people","display_name":"The Revolutionary","faction_key":"house_people","leadership":18,"attack":18,"defense":14,"damage_type":"pierce","speed":5,"accuracy":72,"evasion":12,"traits":["Brave","Inspiring","Ruthless"],"unit_archetype":"Free Militia Commander","ai_playstyle":"expansionist"},
	{"story_id":"house_faith","display_name":"The Traditionalist","faction_key":"house_faith","leadership":16,"attack":14,"defense":20,"damage_type":"blunt","speed":3,"accuracy":68,"evasion":8,"traits":["Guardian","Disciplined","Unyielding"],"unit_archetype":"Templar Commander","ai_playstyle":"defensive"},
	{"story_id":"house_shadows","display_name":"The Spymaster","faction_key":"house_shadows","leadership":18,"attack":16,"defense":14,"damage_type":"slash","speed":7,"accuracy":78,"evasion":20,"traits":["Scout","Cunning","Strategist"],"unit_archetype":"Shadow Blade","ai_playstyle":"opportunist"},
	{"story_id":"house_diplomacy","display_name":"The Diplomat","faction_key":"house_diplomacy","leadership":20,"attack":10,"defense":16,"damage_type":"blunt","speed":3,"accuracy":60,"evasion":6,"traits":["Inspiring","Diplomat","Wise"],"unit_archetype":"Banner Guard Commander","ai_playstyle":"diplomatic"},
	{"story_id":"house_frontier","display_name":"The Warden","faction_key":"house_frontier","leadership":18,"attack":18,"defense":20,"damage_type":"pierce","speed":6,"accuracy":82,"evasion":15,"traits":["Scout","Guardian","Disciplined"],"unit_archetype":"Master Ranger Warden","ai_playstyle":"defensive"},
	{"story_id":"house_law","display_name":"The Lawkeeper","faction_key":"house_law","leadership":18,"attack":14,"defense":18,"damage_type":"blunt","speed":4,"accuracy":70,"evasion":8,"traits":["Disciplined","Unyielding","Guardian"],"unit_archetype":"Justiciar Supreme","ai_playstyle":"balanced"},
	{"story_id":"house_strategy","display_name":"The Strategist","faction_key":"house_strategy","leadership":22,"attack":14,"defense":16,"damage_type":"slash","speed":4,"accuracy":72,"evasion":8,"traits":["Strategist","Disciplined","Wise"],"unit_archetype":"Grand Tactician","ai_playstyle":"calculated"},
	{"story_id":"house_roads","display_name":"The Builder","faction_key":"house_roads","leadership":16,"attack":12,"defense":22,"damage_type":"blunt","speed":3,"accuracy":62,"evasion":5,"traits":["Disciplined","Resourceful","Guardian"],"unit_archetype":"Siege Engineer Commander","ai_playstyle":"fortify"},
	{"story_id":"house_blood","display_name":"The Pretender","faction_key":"house_blood","leadership":16,"attack":20,"defense":16,"damage_type":"slash","speed":6,"accuracy":78,"evasion":15,"traits":["Brave","Ruthless","Ambitious"],"unit_archetype":"Crimson Champion","ai_playstyle":"aggressive"},
	{"story_id":"house_provinces","display_name":"The Governor","faction_key":"house_provinces","leadership":16,"attack":14,"defense":16,"damage_type":"pierce","speed":5,"accuracy":70,"evasion":12,"traits":["Strategist","Resourceful","Cautious"],"unit_archetype":"Provincial Knight Commander","ai_playstyle":"economic"},
	{"story_id":"house_outsider","display_name":"The Khan","faction_key":"house_outsider","leadership":20,"attack":26,"defense":16,"damage_type":"slash","speed":8,"accuracy":75,"evasion":18,"traits":["Brave","Ruthless","Terrifying"],"unit_archetype":"Horse Reaver Warlord","ai_playstyle":"conquest"},
]

const RESERVE_NAME_BANK: Dictionary = {
	"house_counsel": ["Marshal Rowan", "Advisor Sel", "Warden Ilex", "Chancellor Mirel", "Standard Bearer Oren", "Mediator Thane", "Keeper Elsin", "Marchesa Vale", "Hall Regent Corin", "Pledge Captain Lyra", "Banner Judge Rhos", "Steward Cass"],
	"house_war": ["Captain Voss", "Iron Talon", "Red Banner", "Siegebreaker Dorn", "Ash Pike", "Marshal Korr", "War Sister Tessa", "Line Captain Brant", "Macehand Orik", "Banner Spear Yune", "Drumlord Hask", "Iron Standard Vale"],
	"house_crown": ["Sir Aurel", "Lady Maren", "Crown Bastion", "Shieldknight Pell", "Lord Sevran", "Lady Cerys", "Gold Mantle Rowan", "Oath Captain Varen", "Duke's Blade Iven", "White Banner Elra", "High Squire Cato", "Palace Guard Mire"],
	"house_coin": ["Factor Pell", "Portmaster Renn", "Guild Spear", "Ledger Knight Soren", "Broker Hale", "Quartermaster Nyx", "Harbor Marshal Tovin", "Mint Captain Orla", "Customs Lance Perrin", "Trade Guard Mera", "Vault Warden Selk", "Contract Blade Joren"],
	"house_people": ["Torchbearer Nia", "Captain Kesh", "Field Tribune", "Freeblade Orin", "Banner Voice Lysa", "Commons Guard Hett", "March Speaker Dain", "Red Sash Bria", "Uprising Captain Sol", "Plowshield Korrin", "Drumfire Taren", "Street Marshal Iri"],
	"house_faith": ["Abbot-Commander Sol", "Shield Sister Yve", "Pillar Warden", "Canon Spear Hadrin", "Monastery Guard Elow", "Sanctum Pike Brann", "Reliquary Knight Sera", "Temple March Aven", "Chapel Bastion Voss", "Penance Captain Mira", "Litany Blade Cor", "Vigil Sister Nessa"],
	"house_shadows": ["Whisper Kade", "Veil Captain", "Night Courier", "Shade Marshal Ren", "Knifehand Sable", "Lantern Ghost Mira", "Velvet Fang Orr", "Maskrunner Thane", "Silent Spur Ilex", "Dusk Pike Venn", "Cinder Cloak Seri", "Nocturne Vale"],
	"house_diplomacy": ["Envoy Serin", "Banner Steward", "Peacewarden", "Treaty Lance Corin", "Court Marshal Lera", "Concord Guard Pell", "Parley Blade Soren", "Olive Standard Mira", "Harbor Envoy Taren", "Silver Tongue Voss", "Accord Captain Ilya", "Grace Pike Deren"],
	"house_frontier": ["Pine Watcher", "Ridge Captain", "Ash Ranger", "Stone Trail Varr", "Wolf Banner Cira", "Huntmarshal Orren", "Northwatch Pell", "Frost Path Lysa", "Timber Guard Noll", "Highpass Mira", "Cairn Spear Dain", "Thorn Scout Veya"],
	"house_law": ["Justiciar Hume", "Chain Marshal", "Court Blade", "Edict Spear Varn", "Ward Captain Sel", "Sentence Pike Ivor", "High Bailiff Mara", "Black Robe Cato", "Tribunal Guard Neris", "Scale Banner Dorn", "Codekeeper Pell", "Judgment Lance Orla"],
	"house_strategy": ["Analyst Doran", "Mapmaster Vela", "Siege Scholar", "Compass Knight Orris", "Table Marshal Nyra", "Cipher Spear Tal", "Master of Lines Eren", "Planward Cira", "Engine Captain Solm", "Grey Banner Cass", "Route Reader Pell", "Tactician Voss"],
	"house_roads": ["Bridge Captain", "Stone Surveyor", "Road Marshal", "Paver Knight Toma", "Rampart Foreman Sera", "Causeway Spear Brin", "Span Guard Elric", "Milestone Mira", "Iron Cart Hask", "Gate Captain Noll", "Wall Clerk Rowan", "Quarry Blade Pell"],
	"house_blood": ["Crimson Fang", "Duel Captain", "Scar Standard", "Red Spur Kalen", "Bloodguard Sira", "Champion Varek", "Ruin Blade Hett", "War Cry Mera", "Gore Pike Dax", "Ashen Fang Cor", "Razor Banner Iven", "Dread Lance Nyx"],
	"house_provinces": ["Provost Hale", "March Steward", "Tax Lance", "Granary Guard Lorn", "Collector Veya", "County Pike Bran", "Civic Captain Elra", "Storehouse Pell", "Harvest Marshal Tovin", "Toll Blade Mira", "Ward Taxer Joss", "Field Bailiff Ren"],
	"house_outsider": ["Rider Qara", "Steppe Banner", "Storm Hoof", "Dust Reaver Norn", "Sky Lance Tora", "Wind Spur Kesh", "Horse Archer Siva", "Raider Varr", "Nomad Pike Reka", "Thunder Mane Orr", "Falcon Banner Nira", "Steppe Wolf Dain"],
}

const EXTRA_GENERAL_TARGET: int = 200
const RESERVE_NAME_FALLBACK_TITLES: Array[String] = [
	"Captain",
	"Marshal",
	"Warden",
	"Banner",
	"Lance",
	"Guard",
	"Steward",
	"Knight",
]

static func build_templates(map_data: MapData) -> Array:
	var out: Array = []
	if map_data == null:
		return out
	var ctx: Dictionary = _build_context(map_data)
	var key_to_faction: Dictionary = ctx["key_to_faction"] as Dictionary
	var owned_by_faction: Dictionary = ctx["owned_by_faction"] as Dictionary
	var faction_cursor: Dictionary = {}
	for base in STORY_ROSTER:
		var fkey: String = str(base.get("faction_key", ""))
		var faction: FactionData = key_to_faction.get(fkey, null) as FactionData
		if faction == null:
			for item_f in map_data.factions:
				var f: FactionData = item_f as FactionData
				if f == null:
					continue
				if not (owned_by_faction.get(int(f.id), []) as Array).is_empty():
					faction = f
					break
		if faction == null:
			continue
		var fid: int = int(faction.id)
		var owned: Array = owned_by_faction.get(fid, [])
		if owned.is_empty():
			continue
		var cursor: int = int(faction_cursor.get(fid, 0))
		var province_id: int = int(owned[cursor % owned.size()])
		faction_cursor[fid] = cursor + 1
		var tpl: Dictionary = base.duplicate(true)
		tpl["faction_id"] = fid
		tpl["province_id"] = province_id
		out.append(tpl)
	return out


static func build_starting_extra_general_templates(map_data: MapData, per_faction: int = 1) -> Array:
	var out: Array = []
	if map_data == null or per_faction <= 0:
		return out
	var ctx: Dictionary = _build_context(map_data)
	var owned_by_faction: Dictionary = ctx["owned_by_faction"] as Dictionary
	var key_by_faction_id: Dictionary = ctx["key_by_faction_id"] as Dictionary
	for item_f in map_data.factions:
		var faction: FactionData = item_f as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		var owned: Array = owned_by_faction.get(fid, [])
		if owned.is_empty():
			continue
		var fkey: String = str(key_by_faction_id.get(fid, ""))
		for i in range(per_faction):
			var province_id: int = int(owned[(i + owned.size() - 1) % owned.size()])
			out.append(_make_reserve_template(fkey, fid, province_id, i, true))
	return out


static func build_mission_general_pool(map_data: MapData, total_target: int = EXTRA_GENERAL_TARGET) -> Dictionary:
	var out: Dictionary = {}
	if map_data == null or total_target <= 0:
		return out
	var ctx: Dictionary = _build_context(map_data)
	var key_by_faction_id: Dictionary = ctx["key_by_faction_id"] as Dictionary
	var owned_by_faction: Dictionary = ctx["owned_by_faction"] as Dictionary
	var faction_ids: Array[int] = []
	for item_f in map_data.factions:
		var faction: FactionData = item_f as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		if (owned_by_faction.get(fid, []) as Array).is_empty():
			continue
		out[fid] = []
		faction_ids.append(fid)
	if faction_ids.is_empty():
		return out
	var cursor_by_faction: Dictionary = {}
	for n in range(total_target):
		var fid: int = int(faction_ids[n % faction_ids.size()])
		var fkey: String = str(key_by_faction_id.get(fid, ""))
		var local_index: int = int(cursor_by_faction.get(fid, 0))
		cursor_by_faction[fid] = local_index + 1
		var templates: Array = out.get(fid, []) as Array
		templates.append(_make_reserve_template(fkey, fid, -1, local_index, false))
		out[fid] = templates
	# Shuffle each faction pool so claim order is random each game
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for fid in out.keys():
		var pool: Array = out[fid] as Array
		for i in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
		out[fid] = pool
	return out


static func _build_context(map_data: MapData) -> Dictionary:
	var key_to_faction: Dictionary = {}
	var key_by_faction_id: Dictionary = {}
	var owned_by_faction: Dictionary = {}
	for item_f in map_data.factions:
		var faction: FactionData = item_f as FactionData
		if faction == null:
			continue
		var fid: int = int(faction.id)
		owned_by_faction[fid] = []
		var fkey: String = ""
		if faction.get("faction_key") != null:
			fkey = str(faction.get("faction_key"))
		if fkey != "":
			key_to_faction[fkey] = faction
			key_by_faction_id[fid] = fkey
	for item_p in map_data.provinces:
		var province: ProvinceData = item_p as ProvinceData
		if province == null:
			continue
		var owner_id: int = int(province.owner_id)
		if owned_by_faction.has(owner_id):
			(owned_by_faction[owner_id] as Array).append(int(province.id))
	return {
		"key_to_faction": key_to_faction,
		"key_by_faction_id": key_by_faction_id,
		"owned_by_faction": owned_by_faction,
	}


static func _make_reserve_template(faction_key: String, faction_id: int, province_id: int,
		ordinal: int, early_game: bool) -> Dictionary:
	var display_name: String = _make_reserve_display_name(faction_key, ordinal)
	var base_story: Dictionary = _find_story_base_by_key(faction_key)
	var leadership: int = clampi(int(base_story.get("leadership", 16)) - (0 if early_game else 2) + (ordinal % 3), 12, 22)
	var attack: int = clampi(int(base_story.get("attack", 14)) - (2 if early_game else 0) + ((ordinal + 1) % 3), 10, 22)
	var defense: int = clampi(int(base_story.get("defense", 14)) - (0 if early_game else 2), 10, 22)
	var damage_type: String = str(base_story.get("damage_type", "slash"))
	var speed: int = int(base_story.get("speed", 4))
	var accuracy: int = int(base_story.get("accuracy", 72))
	var evasion: int = int(base_story.get("evasion", 10))
	return {
		"story_id": "%s_reserve_%02d" % [faction_key, ordinal + 1],
		"display_name": display_name,
		"faction_key": faction_key,
		"faction_id": faction_id,
		"province_id": province_id,
		"leadership": leadership,
		"attack": attack,
		"defense": defense,
		"damage_type": damage_type,
		"speed": speed,
		"accuracy": accuracy,
		"evasion": evasion,
		"traits": _build_reserve_traits(base_story, early_game, ordinal),
		"unit_archetype": str(base_story.get("unit_archetype", "Field Captain")),
		"ai_playstyle": str(base_story.get("ai_playstyle", "balanced")),
		"is_reserve_general": true,
		"spawn_phase": "starting" if early_game else "mission_pool",
	}


static func _make_reserve_display_name(faction_key: String, ordinal: int) -> String:
	var names: Array = RESERVE_NAME_BANK.get(faction_key, ["Reserve Captain"]) as Array
	if ordinal < names.size():
		return str(names[ordinal])
	var base_name: String = str(names[ordinal % names.size()])
	var title: String = str(RESERVE_NAME_FALLBACK_TITLES[ordinal % RESERVE_NAME_FALLBACK_TITLES.size()])
	var wing: int = int(ordinal / names.size()) + 1
	return "%s %s %d" % [title, base_name, wing]


static func _build_reserve_traits(base_story: Dictionary, early_game: bool, ordinal: int) -> Array:
	var out: Array = []
	for item in base_story.get("traits", []):
		var s: String = str(item)
		if s == "":
			continue
		if not out.has(s):
			out.append(s)
		if out.size() >= 2:
			break
	if early_game and not out.has("Disciplined"):
		out.append("Disciplined")
	elif not early_game and ordinal % 3 == 0 and not out.has("Resourceful"):
		out.append("Resourceful")
	return out


static func _find_story_base_by_key(faction_key: String) -> Dictionary:
	for base in STORY_ROSTER:
		if str(base.get("faction_key", "")) == faction_key:
			return base
	return STORY_ROSTER[0] as Dictionary
