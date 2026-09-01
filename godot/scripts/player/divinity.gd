extends Node
class_name Divinity

## Everything the player can do, and the Faith it costs.
##
## The design rule this whole file exists to respect: THE GOD CANNOT GIVE
## ORDERS. There is no build button and no harvest button. What the god has is
## approval -- bless a follower who just did something and they will do it more,
## punish them and they will do it less -- plus miracles that change the WORLD
## and let the villagers react to it. Every power below is one of those two
## shapes, and anything that would amount to direct control does not belong
## here no matter how convenient it would be.
##
## Faith comes from the villagers, not from a timer. A god with no followers
## earns nothing, which is what makes the population cap a real constraint
## rather than a number on a panel.

signal faith_changed(amount: float)
signal card_drawn(card: Dictionary)
## Emitted whenever the HAND changes for any reason -- drawn, played, spent.
## The HUD listens to this rather than to card_drawn alone, because a card
## played by anything other than its own button would otherwise leave a dead
## button on screen that casts an empty index.
signal hand_changed()
signal miracle_cast(id: String, at: Vector3)
signal judged(who, good: bool)          ## bless or punish landed on a follower
signal smote(at: Vector3, radius: float, destroyed: int)
signal island_bought(slot: Vector2i)
signal notice(text: String)             ## one line for the player, for the HUD

## Faith per second per follower, scaled by how devout and how content they
## are. Small: the numbers below are balanced against minutes, not seconds.
const FAITH_PER_FOLLOWER := 0.22
const PRAYER_BONUS := 6.0               ## a completed prayer is worth real Faith
const WORK_BONUS := 1.5

const BLESS_COST := 8.0
const SMITE_COST := 14.0

## A new card every this many seconds (item 8).
const DRAW_SECONDS := 10.0
const HAND_MAX := 5

## The deck. `icon` names a glyph in scripts/ui/icons.gd -- NOT an emoji:
## Godot's default font has none, so an emoji card renders as a hollow box on
## any machine without an emoji font installed.
##
## `target` says what the card needs before it can be played:
##   "none"    cast immediately, affects the whole village
##   "ground"  the player picks a spot
##   "folk"    the player picks a villager
const DECK := [
	{"id": "grove", "name": "Grove", "icon": "tree", "target": "ground",
	 "desc": "Trees rise from bare ground."},
	{"id": "bounty", "name": "Bounty", "icon": "wheat", "target": "none",
	 "desc": "The granary fills."},
	{"id": "rain", "name": "Rain", "icon": "rain", "target": "none",
	 "desc": "Everyone is washed clean, and the crops drink."},
	{"id": "feast", "name": "Feast", "icon": "apple", "target": "none",
	 "desc": "Nobody goes hungry tonight."},
	{"id": "mend", "name": "Mend", "icon": "heart", "target": "folk",
	 "desc": "Health and vigour restored."},
	{"id": "fertility", "name": "Fertility", "icon": "sprout", "target": "none",
	 "desc": "A new villager, if there is room."},
	{"id": "revel", "name": "Revel", "icon": "confetti", "target": "none",
	 "desc": "Spirits lift across the island."},
	{"id": "calm", "name": "Calm", "icon": "dove", "target": "none",
	 "desc": "Grudges soften. Old wounds cool."},
]

var faith := 25.0
var hand: Array[Dictionary] = []
var _draw_timer := DRAW_SECONDS
var rng := RandomNumberGenerator.new()

## Injected by the scene root. Untyped because Divinity is built before some of
## them exist and a typed null is not more honest than an untyped one.
var host = null                          ## ValeRoot
var village = null
var islands = null
var builder = null
var grid = null


func _init() -> void:
	rng.seed = 20260901


func _process(delta: float) -> void:
	if host == null:
		return
	var folk: Array = host.folk
	# Faith is EARNED, per follower, weighted by their own faith and mood. A
	# miserable village is a poor one, which is the pressure that makes
	# blessing worth spending on.
	var income := 0.0
	for f in folk:
		if not is_instance_valid(f) or f.brain == null:
			continue
		var devotion: float = float(f.brain.stats["faith"])
		var mood: float = (f.brain.mood() + 1.0) * 0.5
		income += FAITH_PER_FOLLOWER * (0.35 + devotion * 0.65) * (0.4 + mood * 0.6)
	if income > 0.0:
		add_faith(income * delta)

	_draw_timer -= delta
	if _draw_timer <= 0.0:
		_draw_timer = DRAW_SECONDS
		draw_card()


func add_faith(amount: float) -> void:
	faith = maxf(0.0, faith + amount)
	faith_changed.emit(faith)


func can_afford(cost: float) -> bool:
	return faith >= cost


## --- cards ------------------------------------------------------------------

func draw_card() -> void:
	if hand.size() >= HAND_MAX:
		# A full hand stops drawing rather than discarding the oldest. Silently
		# binning a card the player was saving is the kind of thing they notice
		# only as "the game ate my miracle".
		notice.emit("Your hand is full.")
		return
	var card: Dictionary = DECK[rng.randi_range(0, DECK.size() - 1)].duplicate()
	hand.append(card)
	card_drawn.emit(card)
	hand_changed.emit()


## Play `index` from the hand. `at` is a world point for "ground" cards and
## `who` a Follower for "folk" cards; both are ignored otherwise.
func play(index: int, at := Vector3.ZERO, who = null) -> bool:
	if index < 0 or index >= hand.size():
		return false
	var card: Dictionary = hand[index]
	var kind := String(card["target"])
	if kind == "folk" and (who == null or not is_instance_valid(who)):
		notice.emit("%s needs a villager." % card["name"])
		return false
	if not _cast(String(card["id"]), at, who):
		return false
	hand.remove_at(index)
	hand_changed.emit()
	miracle_cast.emit(String(card["id"]), at)
	return true


func _cast(id: String, at: Vector3, who) -> bool:
	match id:
		"grove":
			var n := _grow_trees(at, 3)
			if n == 0:
				notice.emit("No open ground there.")
				return false
			_remember_all("The trees came from nowhere.", 0.5)
			notice.emit("A grove rises.")
		"bounty":
			village.give({"food": 8, "wood": 4})
			_remember_all("The stores filled themselves.", 0.55)
			notice.emit("The granary fills.")
		"rain":
			for f in host.folk:
				f.brain.stats["hygiene"] = 1.0
				f.brain.stats["health"] = minf(1.0,
					float(f.brain.stats["health"]) + 0.2)
			village.give({"food": 4})
			_remember_all("Rain, exactly when it was needed.", 0.45)
			notice.emit("Rain falls.")
		"feast":
			for f in host.folk:
				f.brain.stats["hunger"] = 1.0
				f.brain.stats["fun"] = minf(1.0,
					float(f.brain.stats["fun"]) + 0.3)
			# And it LEAVES something. A miracle that only plays a particle
			# burst is one the player has to take on trust; heaps of fruit on
			# the grass, which villagers then walk over and pick up, is one
			# they can watch work.
			var heaps := _scatter_prop("Nature/apples", at, 5)
			_remember_all("We ate until we could not.", 0.7)
			notice.emit("A feast. %d baskets left over." % heaps
						if heaps > 0 else "A feast.")
		"mend":
			who.brain.stats["health"] = 1.0
			who.brain.stats["energy"] = 1.0
			who.brain.memories.add(Memories.KIND_MIRACLE,
				"I was made whole again.", 0.9, "", 1.4)
			who.brain.think_aloud()
			notice.emit("%s is mended." % who.brain.name)
		"fertility":
			if not village.has_room():
				notice.emit("There is no room for another villager.")
				return false
			if not host.spawn_villager():
				notice.emit("Nowhere for them to stand.")
				return false
			_remember_all("A new face among us.", 0.6)
			notice.emit("A villager is born.")
		"revel":
			for f in host.folk:
				f.brain.stats["fun"] = 1.0
				f.brain.stats["social"] = minf(1.0,
					float(f.brain.stats["social"]) + 0.5)
			_remember_all("What a night that was.", 0.6)
			notice.emit("The island celebrates.")
		"calm":
			# Cools every grudge without erasing the events. Memories are the
			# record; heat is how much they still sting. Deleting the entries
			# would rewrite history, and the panel would suddenly claim two
			# people who fought this morning had never met.
			for f in host.folk:
				for e in f.brain.memories.entries:
					if float(e["valence"]) < 0.0:
						e["heat"] = float(e["heat"]) * 0.25
			notice.emit("Old wounds cool.")
		_:
			return false
	return true


func _remember_all(text: String, valence: float) -> void:
	for f in host.folk:
		if is_instance_valid(f) and f.brain != null:
			f.brain.memories.add(Memories.KIND_MIRACLE, text, valence, "",
				1.0 + f.brain.personality.devotion)


## --- judgement --------------------------------------------------------------

## Approve of what this follower just did. The ONLY way the god steers work.
func bless(who) -> bool:
	if who == null or not is_instance_valid(who) or who.brain == null:
		return false
	if not can_afford(BLESS_COST):
		notice.emit("Not enough Faith to bless.")
		return false
	add_faith(-BLESS_COST)
	who.brain.bless(1.0)
	# Blessing an act nobody performed is legal but useless, and saying so is
	# how the player learns the mechanic is about TIMING.
	if who.brain.last_action == "":
		notice.emit("%s felt the warmth, but had done nothing to earn it."
			% who.brain.name)
	else:
		notice.emit("%s is blessed for %s."
			% [who.brain.name, who.brain.last_action])
	judged.emit(who, true)
	return true


func punish(who) -> bool:
	if who == null or not is_instance_valid(who) or who.brain == null:
		return false
	if not can_afford(BLESS_COST):
		notice.emit("Not enough Faith to punish.")
		return false
	add_faith(-BLESS_COST)
	who.brain.punish(1.0)
	notice.emit("%s is struck down%s." % [who.brain.name,
		"" if who.brain.last_action == "" else " for " + who.brain.last_action])
	judged.emit(who, false)
	return true


## --- wrath ------------------------------------------------------------------

## Destroy what stands in a circle: burn the trees, flatten the buildings.
##
## Area punishment (item 10). Everyone who can see it remembers it, and their
## opinion of the god drops whether or not they were the target -- which is the
## point. A god who levels a wood to make a point has made it to everybody.
func smite(at: Vector3, radius := 2.5) -> bool:
	if not can_afford(SMITE_COST):
		notice.emit("Not enough Faith to strike.")
		return false
	add_faith(-SMITE_COST)
	var destroyed := 0
	for entry in builder.placed_props.duplicate():
		var node = entry.get("node")
		if not is_instance_valid(node):
			continue
		var aid := String(entry["id"])
		# Bridges are spared on purpose: destroying one can strand an island
		# with villagers on it, and "the game let me make part of the map
		# unreachable" is a bug the player experiences as a bug.
		if aid == "Buildings/bridge":
			continue
		if node.position.distance_to(at) > radius:
			continue
		builder.remove_prop(entry)
		destroyed += 1
	if destroyed == 0:
		notice.emit("Nothing there to destroy.")
	else:
		notice.emit("%d things are destroyed." % destroyed)
		for f in host.folk:
			if not is_instance_valid(f) or f.brain == null:
				continue
			var near: bool = f.position.distance_to(at) < radius * 4.0
			f.brain.memories.add(Memories.KIND_LOSS,
				"I saw it all torn apart." if near
					else "Something was destroyed today.",
				-0.8 if near else -0.4, "",
				1.0 + f.brain.personality.devotion)
			f.brain.stats["faith"] = maxf(0.0,
				float(f.brain.stats["faith"]) - (0.35 if near else 0.15))
			f.brain.think_aloud()
	smote.emit(at, radius, destroyed)
	# The grid changes when props do: a felled tree opens a tile, and a
	# flattened cottage opens seven by seven of them.
	host.rebuild_grid()
	return true


## Drop `count` of something onto open ground near `at`. Returns how many
## landed, which may be fewer -- the caller says so rather than pretending.
func _scatter_prop(aid: String, at: Vector3, count: int) -> int:
	var origin: Vector3 = at
	if origin == Vector3.ZERO and host.folk.size() > 0:
		origin = host.folk[0].position
	var cell: Vector2i = grid.cell_of(origin)
	var made := 0
	for attempt in count * 20:
		if made >= count:
			break
		var c: Vector2i = cell + Vector2i(rng.randi_range(-5, 5),
										  rng.randi_range(-5, 5))
		if not grid.is_walkable(c):
			continue
		if builder.add_prop(aid, c.x, c.y, rng.randf_range(0.0, 360.0)):
			made += 1
	if made > 0:
		# Grid rebuild, so the new heaps are indexed and villagers can find
		# them. Skipping it leaves fruit nobody is able to notice.
		host.rebuild_grid()
	return made


func _grow_trees(at: Vector3, count: int) -> int:
	# Annotated: `grid` is injected untyped (Divinity is built before the grid
	# is rebuilt for the first time), so everything off it is Variant.
	var cell: Vector2i = grid.cell_of(at)
	var made := 0
	for attempt in count * 25:
		if made >= count:
			break
		var c: Vector2i = cell + Vector2i(rng.randi_range(-3, 3),
										  rng.randi_range(-3, 3))
		if not grid.is_walkable(c):
			continue
		var kind := "Nature/tree" if rng.randf() < 0.7 else "Nature/pine"
		if builder.add_prop(kind, c.x, c.y, rng.randf_range(0.0, 360.0)):
			made += 1
	if made > 0:
		host.rebuild_grid()
	return made


## --- land -------------------------------------------------------------------

func buy_island(slot: Vector2i) -> bool:
	var price := float(islands.price_next())
	if not can_afford(price):
		notice.emit("That island costs %d Faith." % int(price))
		return false
	if not islands.unlock(slot):
		notice.emit("You cannot reach that island.")
		return false
	add_faith(-price)
	host.rebuild_world()
	village.pop_cap = islands.pop_cap()
	_remember_all("New land, across the water.", 0.5)
	notice.emit("New land rises. Room for %d." % village.pop_cap)
	island_bought.emit(slot)
	return true
