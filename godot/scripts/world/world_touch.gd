extends RefCounted
class_name WorldTouch

## What the world does when a god pokes it.
##
## The player had exactly two things to click: a villager and a card. Everything
## else -- every tree, rock, pond and bare patch of dirt -- was scenery that
## swallowed the click and panned the camera. This is the table that makes the
## world answer back, and it is the spine of the desert opening: a plot arrives
## as bare dirt, and the only way it becomes a village is that somebody touched
## every tile of it.
##
## THE RULES, and they are what keep this from being a clicker:
##
##   - Every touch is FREE and pays FAITH to whoever is near. The world is the
##     resource, not the purse; Faith is spent on miracles and land.
##   - One shared cooldown, so the limit is what is left to touch rather than
##     how fast a mouse can be moved.
##   - Nothing is created out of nothing. A tree gives apples because it has
##     apples; a rock breaks into stone and is gone. The one exception is grass
##     on dirt, which is the god doing the one thing a god is for.

## Seconds between touches. Short enough to feel like drumming your fingers
## across a hillside, long enough that a macro is not a strategy.
const COOLDOWN := 0.45

## How far a touch is felt. Villagers inside this see it and gain faith.
const WITNESS_RANGE := 7.0
const FAITH_PER_TOUCH := 1.5

## PROPS. `gives` goes to the village store, `spawns` is left on the ground for
## somebody to walk over and pick up, `consumes` removes what was touched.
const PROPS := {
	"Nature/tree": {"verb": "Apples fall.", "spawns": "Nature/apples",
					"fx": "bounty", "sfx": "pick"},
	"Nature/pine": {"verb": "Cones and needles.", "gives": {"wood": 1},
					"fx": "grove", "sfx": "pick"},
	"Nature/bush": {"verb": "Berries.", "spawns": "Nature/apples",
					"fx": "bounty", "sfx": "pick"},
	"Nature/rock": {"verb": "The stone splits.", "gives": {"stone": 2},
					"consumes": true, "fx": "chips", "sfx": "chop"},
	"Nature/stump": {"verb": "Firewood.", "gives": {"wood": 2},
					 "consumes": true, "fx": "chips", "sfx": "chop"},
	"Nature/log": {"verb": "Firewood.", "gives": {"wood": 2},
				   "consumes": true, "fx": "chips", "sfx": "chop"},
	"Nature/crop_row": {"verb": "The ears ripen.", "gives": {"food": 2},
						"fx": "bounty", "sfx": "pick"},
	"Nature/flowers": {"verb": "They open.", "fun": 0.10,
					   "fx": "revel", "sfx": "chat"},
	"Nature/tall_grass": {"verb": "It sways.", "fun": 0.05,
						  "fx": "grove", "sfx": "chat"},
	"Nature/reeds": {"verb": "Reeds for thatch.", "gives": {"wood": 1},
					 "fx": "grove", "sfx": "pick"},
	"Nature/apples": {"verb": "Ripe already.", "fx": "feast", "sfx": "pick"},
}

## TILES, by the code letter in the world document.
##
## Dirt to grass is the first verb the player will ever use and the whole
## opening rests on it. Grass then grows things, but only where there is room --
## a meadow you can fill with one held mouse button is not a decision.
const TILES = {
	"D": {"verb": "Green spreads.", "becomes": "G",
		  "fx": "grove", "sfx": "pick"},
	"A": {"verb": "Green spreads.", "becomes": "G",
		  "fx": "grove", "sfx": "pick"},
	"C": {"verb": "Green spreads.", "becomes": "G",
		  "fx": "grove", "sfx": "pick"},
	"G": {"verb": "Something takes root.", "grows": true,
		  "fx": "grove", "sfx": "pick"},
	"W": {"verb": "The water turns.", "gives": {"food": 1}, "fun": 0.12,
		  "fx": "revel", "sfx": "miracle"},
	"S": {"verb": "The stone splits.", "gives": {"stone": 1},
		  "fx": "chips", "sfx": "chop"},
}

## What grass grows, and how often. Trees first because wood is what the
## village is always short of, and because a treeless plot cannot be built on.
const SEEDS := [["Nature/tree", 46], ["Nature/bush", 22],
				["Nature/flowers", 16], ["Nature/tall_grass", 16]]


static func prop_action(id: String) -> Dictionary:
	return PROPS.get(id, {})


static func tile_action(ch: String) -> Dictionary:
	return TILES.get(ch, {})


## Which plant this patch of grass grows. Seeded from the CELL, so the same
## square always grows the same thing -- a player who clicks, sees a bush and
## wishes it were a tree cannot reroll it by clicking the next one twice.
static func seed_for(cell: Vector2i) -> String:
	var total := 0
	for s in SEEDS:
		total += int(s[1])
	var h: int = absi(cell.x * 73856093 ^ cell.y * 19349663) % total
	for s in SEEDS:
		h -= int(s[1])
		if h < 0:
			return String(s[0])
	return String(SEEDS[0][0])
