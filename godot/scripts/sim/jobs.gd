extends RefCounted
class_name Jobs

## What a villager IS, and therefore what they want to do.
##
## A job is a look and a bias, nothing more. The look is an asset id -- every
## human shares one body, one rig and one set of clips (blender/assets/_kit/
## folkbody.py) and differs only in colours and the props attached, so a
## lumberjack is the villager wearing an axe. The bias is a multiplier folded
## into Brain.choose_action alongside the god's `favour` and the village's
## `_demand`: a job can lean hard toward its work, but `_demand` still returns
## a hard zero for anything unaffordable or unwanted, so a job can never force
## the impossible.
##
## `employer` is the building that gives the job out. Nobody is born a miner
## in a village with no mine: Village.job_for_newcomer counts standing
## employers against the villagers already holding each job and hands the
## newcomer the largest deficit.
##
## STUB, filled in by the engine pass of the content batch. It exists now so
## the folk authors know the asset ids the engine will load.

const JOBS := {
	"villager":   {"asset": "Folk/villager",   "bias": {}, "employer": ""},
	"adventurer": {"asset": "Folk/adventurer", "bias": {"forage": 1.5},
				   "employer": ""},
	"lumberjack": {"asset": "Folk/lumberjack", "bias": {"chop": 3.0},
				   "employer": "Buildings/lumber_camp"},
	"miner":      {"asset": "Folk/miner",      "bias": {"quarry": 3.0},
				   "employer": "Buildings/mine"},
	"builder":    {"asset": "Folk/builder",    "bias": {"build_*": 2.5},
				   "employer": "Buildings/smithy"},
	"hunter":     {"asset": "Folk/hunter",     "bias": {"hunt": 1.0, "forage": 1.3},
				   "employer": "Buildings/barracks"},
	"priest":     {"asset": "Folk/priest",     "bias": {"bless_flock": 1.0},
				   "employer": "Buildings/shrine"},
	"nurse":      {"asset": "Folk/nurse",      "bias": {"tend": 1.0},
				   "employer": "Buildings/hotel"},
	"bard":       {"asset": "Folk/bard",       "bias": {"sing": 1.0},
				   "employer": "Buildings/tavern"},
}


static func asset_of(job: String) -> String:
	return String((JOBS.get(job, JOBS["villager"]) as Dictionary)["asset"])


## The multiplier this job applies to an action. `build_*` is a wildcard over
## every build action, so a builder does not need every structure listed.
static func mult(job: String, action: String) -> float:
	var bias: Dictionary = (JOBS.get(job, {}) as Dictionary).get("bias", {})
	if bias.has(action):
		return float(bias[action])
	if action.begins_with("build_") and bias.has("build_*"):
		return float(bias["build_*"])
	return 1.0
