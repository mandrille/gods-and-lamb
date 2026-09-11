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
## Raised from 1.5 the day witness BANDS came in, and the two belong in one
## breath. Banding thins the payout by distance, and the three annuli are
## 6.25%, 29.75% and 64% of a disc -- so a crowd spread evenly through the
## radius collects 0.583 of the flat rate. Holding the old expectation exactly
## would want 2.57; 2.4 because players click near people rather than uniformly,
## and the honest correction is to the crowd they actually have.
##
## Changing one of these without the other reads as a nerf nobody chose.
const FAITH_PER_TOUCH := 2.4

## PROPS. `gives` goes to the village store, `spawns` is left on the ground for
## somebody to walk over and pick up, `consumes` removes what was touched.
const PROPS := {
	"Nature/tree": {"verb": "Apples fall.", "spawns": "Nature/apples",
					"fruit": true, "fx": "bounty", "sfx": "pick"},
	"Nature/pine": {"verb": "Cones and needles.", "gives": {"wood": 1},
					"fx": "grove", "sfx": "pick"},
	"Nature/bush": {"verb": "Berries.", "spawns": "Nature/apples",
					"fruit": true, "count": 2, "reach": 1,
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

## GREENING IS A TIDE, not a tile.
##
## One tile per touch was arithmetic rather than a verb: a starting plot is
## roughly 1600 flat tiles and the shared cooldown is 0.45s, so greening it by
## hand was twelve minutes of tapping the same square of desert.
##
## So a touch lays down a 4x4 block AT ONCE, and that block then keeps
## spreading on its own -- a couple of rows at a time, ragged, taking a random
## part of each new edge -- out to 16x16. The player does not fill in a grid;
## they start something and watch it run, which is the only version of this
## that is a god doing something to a place.
##
## The randomness is a hash of the CELL AND THE STEP, never a die roll: the same
## square always takes at the same moment, so a spread that is interrupted and
## resumed looks the same as one that was not, and nothing about the shape can
## be rerolled by clicking again.
const SEED_SIZE := 4
const TIDE_MAX := 16
## Seconds between one step of the spread and the next. Slow enough to watch.
const TIDE_STEP := 0.85
## How much of what is newly in reach takes on each step. Under 1.0 is what
## makes the edge ragged instead of a growing rectangle.
const TIDE_TAKE := 0.62
## How many spreads may run at once. Past this the oldest is finished off in one
## go rather than abandoned -- a click that quietly did nothing is worse than a
## click that resolves early.
const TIDE_MAX_LIVE := 10


## The square of `size` tiles centred on `cell`. Even sizes cannot be centred
## exactly, so they lean up and left, which is where the click was.
static func block(cell: Vector2i, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var lo := -(size / 2)
	for dy in range(lo, lo + size):
		for dx in range(lo, lo + size):
			out.append(cell + Vector2i(dx, dy))
	return out


## Whether this square takes on this step. Deterministic in both.
static func takes(cell: Vector2i, step: int, chance: float) -> bool:
	if chance >= 1.0:
		return true
	var h: int = absi((cell.x * 73856093) ^ (cell.y * 19349663)
					  ^ ((step + 1) * 83492791))
	return float(h % 1000) < chance * 1000.0


## HOW MANY APPLES A TREE GIVES, and how far they land from the trunk.
##
## A tree used to drop one heap on one neighbouring tile, which is a tree
## producing an item rather than a tree fruiting. Several, scattered under the
## canopy, is the difference -- and every one of them is food a villager will
## walk over and eat, so the number is a real quantity and not decoration.
## HOW MANY HEAPS ONE TREE MAY HAVE LYING UNDER IT AT ONCE.
##
## There was no cap at all -- five heaps a click, a 0.45 s cooldown, no per-tree
## limit and no global prop limit -- so the whole island could be carpeted in
## fruit in under a minute. A tree that is already loaded now refuses, which
## also makes a click on a bare tree mean something again.
const FRUIT_HELD := 6
const FRUIT := 5
const FRUIT_REACH := 2


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
