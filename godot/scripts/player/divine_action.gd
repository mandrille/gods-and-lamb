extends RefCounted
class_name DivineAction

## One thing the god did, described once.
##
## Faith was credited from five different places, each with its own hand-rolled
## copy of the same three steps: scan `folk`, test a distance, pay whoever was
## near. Each threw its witness list away, so nothing downstream could know who
## had seen anything -- which is why the game can tell you a miracle happened
## and cannot tell you that anybody noticed.
##
## This is the value those places now build instead. It says WHAT was done and
## WHERE, and leaves entirely open who saw it and what it was worth; that is the
## processor's business (`Divinity.perform`). Keeping the two apart is what lets
## the prayer system in a later stage ask "did a FOOD act happen near Mara"
## without knowing anything about faith arithmetic.
##
## The static factories read the game's existing tables -- `WorldTouch.PROPS`,
## `Calamity.LOOK` -- rather than duplicating them, for the same reason
## `FXEvents.FOR_MIRACLE` exists: the rules layer should never learn the tables
## and the tables should never learn the rules.

## WHAT KIND OF THING IT WAS, as a bitmask, because acts are frequently more
## than one: healing a villager is LIFE and PROTECTION at once, and a prayer
## that asks for food does not care whether the food arrived as fruit or rain.
const FOOD := 1
const NATURE := 2
const LIFE := 4
const WATER := 8
const STONE := 16
const PROTECTION := 32
const WRATH := 64
const FIRE := 128

var kind := ""                  ## "touch" | "miracle" | "relief" | "bless"
var at := Vector3.ZERO
var tags := 0
## Per-villager faith at full weight, before bands and novelty.
var weight := 0.0
var radius := 0.0
## Whether distance thins the payout. Relief from a disaster deliberately does
## not: paying the people who were furthest from the fire the least is
## backwards, and it contradicts the whole point of answering one.
var bands := false
## The novelty key. "" means this act never gets stale -- see Witness.
var key := ""
## Global Faith to credit, if any. Most acts credit none: touching the world
## raises PEOPLE, and blessing raises the god. That split is deliberate.
var global := 0.0
var why := ""                   ## the `earned` signal's reason string
var verb := ""                  ## the player-facing fragment, from the caller
var subject = null              ## the villager it was aimed AT, or null


static func make(what: String, where: Vector3, w: float, r: float) -> DivineAction:
	var a := DivineAction.new()
	a.kind = what
	a.at = where
	a.weight = w
	a.radius = r
	return a


## A world touch, built from the row `WorldTouch` already looked up.
static func touch(act: Dictionary, where: Vector3, novelty_key := "") -> DivineAction:
	var a := make("touch", where, WorldTouch.FAITH_PER_TOUCH,
				  WorldTouch.WITNESS_RANGE)
	a.verb = String(act.get("verb", ""))
	a.key = novelty_key
	# BANDED, unlike relief: standing in the miracle is worth more than
	# watching it from the treeline.
	a.bands = true
	a.why = "touch"
	var gives: Dictionary = act.get("gives", {})
	if gives.has("food") or String(act.get("spawns", "")) != "":
		a.tags |= FOOD
	if gives.has("stone"):
		a.tags |= STONE
	if gives.has("wood") or bool(act.get("grows", false)) \
			or String(act.get("becomes", "")) != "":
		a.tags |= NATURE
	return a


## A calamity answered. Paid to EVERYONE, unbanded -- see `bands`.
static func relief(per: float) -> DivineAction:
	var a := make("relief", Vector3.ZERO, per, 0.0)
	a.bands = false
	a.why = "relief"
	a.tags = PROTECTION | LIFE
	return a
