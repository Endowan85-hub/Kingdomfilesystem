extends RefCounted
class_name ProvinceNameLibrary

# Biome-aware province name pools.
# assign_names() shuffles each pool per-seed so every map generation
# produces a different arrangement.

const NAMES: Dictionary = {
	"plains": [
		"Aldenmoor", "Ambervale", "Aurelian Fields", "Brightmantle", "Caeldon",
		"Crownsfield", "Dawnmere", "Dawnwatch", "Eldenmoor", "Embervale",
		"Farenholt", "Galenmere", "Gildenfeld", "Glorymarch", "Goldenfen",
		"Grandholm", "Hearthmere", "Highmeadow", "Ironvale", "Kellenmoor",
		"Kingsvale", "Larkmoor", "Lightmere", "Longbarrow", "Lordsmead",
		"Noblecross", "Oldenmoor", "Peregrine", "Queensvale", "Ravensmead",
		"Silverfeld", "Solenmere", "Stormvale", "Sunbarrow", "Sundering",
		"Thornfield", "Tumblewick", "Valdenmoor", "Veilmoor", "Windbarrow",
	],
	"forest": [
		"Aldenbough", "Ancientwood", "Ashenbough", "Canopymere", "Cedarmantle",
		"Crownwood", "Duskgrove", "Eldenbark", "Eldergrove", "Emberglen",
		"Emberhallow", "Eternalwood", "Faewood", "Feywild", "Gloomhaven",
		"Greatwood", "Grimhollow", "Ironbough", "Kingswood", "Lastwood",
		"Lichenmere", "Misthollow", "Moonshadow", "Nightgrove", "Oldmantle",
		"Owlmere", "Ravenbough", "Rootmere", "Shadowmantle", "Shadeholm",
		"Silentgrove", "Silverleaf", "Starwood", "Thornhollow", "Twilightwood",
		"Veilgrove", "Verdanmere", "Witchwood", "Wraithwood", "Wyrmwood",
	],
	"mountain": [
		"Aldercrag", "Anvilspire", "Ashenpeak", "Azorath", "Blackspire",
		"Citadelcrag", "Coldspire", "Crownspire", "Deepvein", "Doomcrag",
		"Dreadspire", "Eaglerest", "Eternalpeak", "Forgespire", "Galecrag",
		"Giantfall", "Glorycrag", "Grandspire", "Greyspire", "Hammerfall",
		"Highkeep", "Ironspire", "Jadecrag", "Kingspass", "Lordskeep",
		"Mightypeak", "Mistcrag", "Oldspire", "Queenspass", "Ruinspire",
		"Scarpfall", "Shatterpeak", "Skullpass", "Stormspire", "Sunspire",
		"Thundervein", "Titanfall", "Tombpeak", "Valorspire", "Warcrag",
	],
	"desert": [
		"Aldersand", "Amber Waste", "Ashen Crown", "Aurum Flats", "Blazegate",
		"Bonedrift", "Bronzerock", "Cauldron", "Cinderfall", "Crownrock",
		"Deadwater", "Dryscar", "Emberveil", "Emberglass", "Eternalsand",
		"Gilded Waste", "Glasswater", "Goldenrock", "Grandflat", "Heatmaw",
		"Ironflat", "Jadestone", "Kiln's End", "Kingsdrift", "Mirestone",
		"Noonrock", "Oldburn", "Parched Vale", "Queenssand", "Redcrag",
		"Ruindrift", "Sandmaw", "Sunblight", "Sunglass", "Suncrack",
		"Thornrock", "Valorrock", "Voidmere", "Wastemark", "Yellowrock",
	],
	"tundra": [
		"Alderfrost", "Bitterkeep", "Blackice", "Boreal Crown", "Coldwatch",
		"Crownfrost", "Crystalmere", "Deepchill", "Driftholm", "Edgeice",
		"Eternalfrost", "Frostmantle", "Frostveil", "Galewatch", "Glacialkeep",
		"Gloryice", "Grandchill", "Grimfrost", "Hailgate", "Icebreak",
		"Icemantle", "Ironsnow", "Kingswatch", "Lostwatch", "Midwinter",
		"Northwatch", "Nullchill", "Oldice", "Permafrost", "Rimegate",
		"Shatterfrost", "Silentsnow", "Snowmaw", "Splitice", "Stormwatch",
		"Thunderice", "Titanfrost", "Tombfrost", "Whitecrag", "Wintermaw",
	],
	"swamp": [
		"Ashfen", "Blackwater", "Blightfen", "Bogmaw", "Bonefog",
		"Brackenmere", "Crestfen", "Darkfen", "Deepfen", "Dreadmire",
		"Eldenbog", "Embermire", "Festermere", "Foghollow", "Gloomfen",
		"Grimfen", "Hazewood", "Inkwater", "Jadebog", "Lastfen",
		"Leechwater", "Lichenbog", "Miremantle", "Murkmere", "Nettlebog",
		"Oldfen", "Oozegate", "Pesthollow", "Rotmere", "Shroudfen",
		"Sinkhollow", "Sludgemere", "Solemire", "Tanglebog", "Umbrabog",
		"Veilfen", "Verdantbog", "Waterrot", "Witchfen", "Writhefog",
	],
	"coast": [
		"Anchorfall", "Baywatch", "Brinecrest", "Brinefall", "Cliffgate",
		"Coralhold", "Coralcrest", "Crashwater", "Crowncove", "Crystalport",
		"Deepport", "Driftgate", "Eastreach", "Eternaltide", "Gloryport",
		"Grandcove", "Gullcrest", "Harborholm", "Ironport", "Jetsam Cove",
		"Kelp Harbor", "Kingsreach", "Lightport", "Mistcove", "Northreach",
		"Oldshore", "Pearlcove", "Queensport", "Reefgate", "Saltmaw",
		"Seagate", "Shipwreck Cove", "Siltport", "Solentide", "Stormcove",
		"Tidebreak", "Tidemark", "Undertow", "Valorport", "Wreckhaven",
	],
}

const FALLBACK: Array = [
	"Aldenmere", "Brighthold", "Crownfall", "Dawngate", "Embervale",
	"Farwatch", "Gloryhold", "Ironmere", "Kingsveil", "Lastwatch",
	"Moonshard", "Nightfall", "Oldwick", "Queensmere", "Ruingate",
	"Silvergate", "Thornhold", "Valorhold", "Veilmere", "Wraithgate",
]


static func assign_names(provinces: Array, rng: RandomNumberGenerator) -> void:
	# Build a shuffled pool per biome
	var pools: Dictionary = {}
	for biome in NAMES.keys():
		var pool: Array = NAMES[biome].duplicate()
		_shuffle(pool, rng)
		pools[biome] = pool

	var fallback: Array = FALLBACK.duplicate()
	_shuffle(fallback, rng)
	var fallback_idx: int = 0

	for item in provinces:
		var p: ProvinceData = item as ProvinceData
		if p == null:
			continue
		var biome: String = str(p.biome) if p.biome != "" else "plains"
		if pools.has(biome) and not pools[biome].is_empty():
			p.display_name = pools[biome].pop_front()
		else:
			if fallback_idx < fallback.size():
				p.display_name = fallback[fallback_idx]
				fallback_idx += 1
			else:
				p.display_name = "Province %d" % int(p.id)


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
