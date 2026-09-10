extends RefCounted
class_name Reputation

## What kind of god they think you are.
##
## Not a class the player picked and not a slider they set: it accrues from what
## they actually did, which is the only version of this that means anything.
## Feed a starving village and you become a Provider whether or not you meant
## to; put out enough fires and you are a Protector.
##
## MOVED BY WITNESSES, not by acts. An apple nobody saw shapes nobody's opinion,
## which is the whole reason `DivineAction` carries a witness count through to
## here -- and it is what stops a player farming a reputation in an empty corner
## of the map. It also means reputation and faith rise together naturally,
## because both are paid for by being seen.
##
## Owned by `Divinity` and built in its `_init`, the same shape as `Boons` and
## `Witness`: state plus questions, reaching into nothing.

## The six the design asks for.
##
## FORTUNE has no source yet and that is deliberate rather than forgotten --
## nothing the god currently does is about luck. It is defined here so the save
## format and the UI do not have to change on the day something does (the boon
## and prophecy work is where it comes from), and until then it simply sits at
## zero. An axis nobody can move is dead weight; an axis with a dated reason to
## exist is a place to put the next thing.
const AXES := ["provider", "protector", "nature", "life", "wrath", "fortune"]

## What each kind of act says about you. A single act usually says two things at
## once -- feeding somebody is providing AND, faintly, life -- so this is a list
## per tag rather than one axis each.
const FROM_TAG := {
	DivineAction.FOOD: [["provider", 1.0], ["life", 0.2]],
	DivineAction.NATURE: [["nature", 1.0]],
	DivineAction.WATER: [["nature", 0.6], ["provider", 0.4]],
	DivineAction.STONE: [["provider", 0.6]],
	DivineAction.LIFE: [["life", 1.0], ["protector", 0.4]],
	DivineAction.PROTECTION: [["protector", 1.0]],
	DivineAction.WRATH: [["wrath", 1.0]],
	DivineAction.FIRE: [["wrath", 0.8], ["nature", -0.3]],
}

## Below this the village has not seen enough of you to have an opinion, and
## saying it has is worse than saying nothing -- one apple in the first minute
## should not crown anybody Provider.
const MIN_TOTAL := 25.0
## And one axis has to be genuinely ahead, not merely first past the post.
const LEAD_SHARE := 0.34

var axes: Dictionary = {}


func _init() -> void:
	for a in AXES:
		axes[a] = 0.0


## One act, already resolved. `seen` is what scales it: this is an opinion, and
## an opinion needs somebody to hold it.
func note(tags: int, seen: int, strength := 1.0) -> void:
	if tags == 0 or seen <= 0:
		return
	# Square-rooted, like the blessing chain: the tenth witness to the same act
	# should count, but not as much as the second. Without it a single miracle
	# over a crowded square would decide the whole game's identity.
	var w: float = sqrt(float(seen)) * strength
	for bit in FROM_TAG:
		if tags & int(bit) == 0:
			continue
		for pair in FROM_TAG[bit]:
			var axis := String(pair[0])
			axes[axis] = maxf(0.0, float(axes[axis]) + float(pair[1]) * w)


## Which axis this kind of act speaks to loudest, before it is spent.
##
## `note` folds an act into the running totals and then it is gone, so nothing
## downstream can say WHICH WAY the needle just moved -- and "you are seen as a
## Protector" is a much duller line than "Protector, rising". This answers that
## from the tags alone: no state, no history, just what the act was about.
## SUMMED PER AXIS, exactly the way `note` folds it in, and that is not a
## detail. Answering a fire is tagged PROTECTION and LIFE; taking the single
## largest entry made both "protector" and "life" worth 1.0 and the winner was
## whichever the dictionary happened to iterate first, so the game announced
## "Life rising" for putting out a fire. Adding them up gives protector 1.4
## against life's 1.0 -- the same answer `note` reaches, which is the only
## answer that can be right.
static func leading_from(tags: int) -> String:
	var sums: Dictionary = {}
	for bit in FROM_TAG:
		if tags & int(bit) == 0:
			continue
		for pair in FROM_TAG[bit]:
			var axis := String(pair[0])
			sums[axis] = float(sums.get(axis, 0.0)) + float(pair[1])
	var best := ""
	var best_w := 0.0
	# Walked in AXES order rather than in dictionary order, so a genuine tie
	# resolves the same way on every machine and in every build.
	for axis in AXES:
		if float(sums.get(axis, 0.0)) > best_w:
			best_w = float(sums[axis])
			best = axis
	return best


func total() -> float:
	var t := 0.0
	for a in AXES:
		t += float(axes[a])
	return t


func share(axis: String) -> float:
	var t := total()
	return 0.0 if t <= 0.0 else float(axes.get(axis, 0.0)) / t


## What they would call you, or "" while they are still making their minds up.
func dominant() -> String:
	var t := total()
	if t < MIN_TOTAL:
		return ""
	var best := ""
	var best_v := 0.0
	for a in AXES:
		if float(axes[a]) > best_v:
			best_v = float(axes[a])
			best = a
	return best if best_v / t >= LEAD_SHARE else ""


## Title case, for the one place this is ever shown.
func title() -> String:
	var d := dominant()
	return "" if d == "" else d.capitalize()


func to_doc() -> Dictionary:
	var out := {}
	for a in AXES:
		if float(axes[a]) > 0.0:
			out[a] = float(axes[a])
	return out


func from_doc(doc: Dictionary) -> void:
	for a in AXES:
		axes[a] = float(doc.get(a, 0.0))
