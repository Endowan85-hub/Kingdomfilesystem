# Unit Sprite Naming Guide

## Folder Structure

Each unit lives under:
```
Art/units/{key}/sprites/
```

---

## File Naming Convention

Drop these files into the unit's `sprites/` folder.
Replace `{key}` with the unit's folder key from the table below.
Replace `{dir}` with a direction code: `s n e w se sw ne nw`

| File Pattern | Purpose |
|---|---|
| `unit_{key}_s.png` | Static south |
| `unit_{key}_n.png` | Static north |
| `unit_{key}_e.png` | Static east |
| `unit_{key}_w.png` | Static west |
| `unit_{key}_se.png` | Static south-east |
| `unit_{key}_sw.png` | Static south-west |
| `unit_{key}_ne.png` | Static north-east |
| `unit_{key}_nw.png` | Static north-west |
| `unit_{key}_idle_{dir}_f0.png` ... `_f7.png` | Idle animation frames (up to 8) |
| `unit_{key}_walk_{dir}_f0.png` ... `_f3.png` | Walk animation frames (up to 4) |
| `unit_{key}_{attack}_{dir}_f0.png` ... `_f3.png` | Attack animation frames (up to 4) |

### Attack Animation Names by Unit Type

| Attack Anim Name | Units |
|---|---|
| `sword_slash` | Militia Swordsman, Mountain Guard, Stonebreaker, Sand Raider, Caravan Guard, Dust Crusher, Ice Warrior, Northern Raider, Bog Fighter, Swamp Ambusher, Marine, Boarding Infantry, Dockhand Brawler, Forest Skirmisher, Light Rider, Forest Rider |
| `spear_thrust` | Militia Spearman, Mountain Pikeman, Harpoon Fighter |
| `bow_shoot` | Militia Crossbowman, Dune Archer, Ice Archer, Reed Archer, Hunter |

### Example — Mountain Pikeman facing south-east:
```
Art/units/mountain_pikeman/sprites/
	unit_mountain_pikeman_se.png
	unit_mountain_pikeman_idle_se_f0.png  ...  _f7.png
	unit_mountain_pikeman_walk_se_f0.png  ...  _f3.png
	unit_mountain_pikeman_spear_thrust_se_f0.png  ...  _f3.png
```

### Example — Militia Spearman facing south-east:
```
Art/units/militia_spearman/sprites/
	unit_militia_spearman_se.png
	unit_militia_spearman_idle_se_f0.png  ...  _f7.png
	unit_militia_spearman_walk_se_f0.png  ...  _f3.png
	unit_militia_spearman_spear_thrust_se_f0.png  ...  _f3.png
```

---

## PixelLab Generation Settings

| Setting | Value |
|---|---|
| Generation Mode | Pro |
| Character Type | Humanoid |
| Camera View | Low Top-Down |
| Character Size | 112px (Custom) |
| Expected Canvas Output | ~216x216 |

After downloading from PixelLab, run the normalize script before dropping into the Art folder:
```
python tools/normalize_sprites.py
```
This pads all sprites to a consistent 256x256 canvas with feet anchored at the same position.

---

## All 24 Tier 1 Units

| In-Game Name | Folder Key | Terrain |
|---|---|---|
| Militia Spearman | `militia_spearman` | Plains |
| Militia Swordsman | `militia_swordsman` | Plains |
| Militia Crossbowman | `militia_crossbowman` | Plains |
| Light Rider | `light_rider` | Plains |
| Hunter | `hunter` | Forest |
| Forest Skirmisher | `forest_skirmisher` | Forest |
| Forest Rider | `forest_rider` | Forest |
| Mountain Guard | `mountain_guard` | Mountain |
| Stonebreaker | `stonebreaker` | Mountain |
| Mountain Pikeman | `mountain_pikeman` | Mountain |
| Sand Raider | `sand_raider` | Desert |
| Caravan Guard | `caravan_guard` | Desert |
| Dune Archer | `dune_archer` | Desert |
| Dust Crusher | `dust_crusher` | Desert |
| Ice Warrior | `ice_warrior` | Tundra |
| Ice Archer | `ice_archer` | Tundra |
| Northern Raider | `northern_raider` | Tundra |
| Bog Fighter | `bog_fighter` | Swamp |
| Reed Archer | `reed_archer` | Swamp |
| Swamp Ambusher | `swamp_ambusher` | Swamp |
| Marine | `marine` | Coast |
| Harpoon Fighter | `harpoon_fighter` | Coast |
| Boarding Infantry | `boarding_infantry` | Coast |
| Dockhand Brawler | `dockhand_brawler` | Coast |

---

## Direction Code Reference

| Long Name | Short Code (used in filenames) |
|---|---|
| south | `s` |
| north | `n` |
| east | `e` |
| west | `w` |
| south-east | `se` |
| south-west | `sw` |
| north-east | `ne` |
| north-west | `nw` |
