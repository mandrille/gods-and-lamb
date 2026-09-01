extends Node3D
class_name ValeLight

## The game light rig, and it is the SAME rig `blender/src/lit.py` renders with.
## That is the whole point of that module: it exists to predict this one, and a
## number that differs here makes every look-dev render a lie.
##
## The sun is the value that transfers exactly. Blender divides irradiance by pi
## and Godot does not, so `lit.py`'s SUN energy of pi is Godot's
## light_energy = 1.0. The 3.6-degree angular size is the soft-shadow width and
## carries across unchanged.
##
## What is NOT here, deliberately: volumetric fog, SSAO, SSIL. GL Compatibility
## has none of them, so using them would make the editor disagree with the web
## build -- which is the one place this game actually ships.

const SUN_ENERGY := 1.0
const SUN_ANGULAR := 3.6           ## degrees; the soft shadow width
const SUN_COLOR := Color(1.0, 0.945, 0.87)
const SUN_EULER := Vector3(-48.0, -128.0, 0.0)

## Sky. A gradient, not a black void -- a real background is most of what makes
## the reference read, and it is also the only ambient fill this renderer has.
const SKY_TOP := Color(0.286, 0.565, 0.85)
const SKY_HORIZON := Color(0.66, 0.80, 0.93)
## The GROUND half of the sky, and it matters far more than it looks like it
## should. The play camera is pitched down about 35 degrees with a half-FOV of
## 18, so the frame never reaches the horizon: everything past the edge of the
## map is this colour, not the blue above. At the stock dark grey it read as a
## black void and looked exactly like the sky had failed to render.
##
## So it is a hazy far-meadow green: where the tiles run out, the world fades
## instead of stopping.
const GROUND_HORIZON := Color(0.52, 0.62, 0.45)
const GROUND_BOTTOM := Color(0.44, 0.54, 0.40)
## Shadow depth. This was a DEAD CONSTANT until 2026-09-01 and the comment
## calling it "the shadow-depth knob" was simply false: with
## `ambient_light_sky_contribution` at 1.0 the ambient term comes wholly from
## the sky radiance and `ambient_light_energy` is never applied. Measured, not
## reasoned: moving it changed mean luma by 0.0000, while dropping the
## contribution to 0 changed it by 0.086.
##
## So the fill is now an explicit COLOUR at an explicit energy. It costs the
## sky's directional variation, which under Compatibility is coarse anyway, and
## it buys a knob that does what its name says -- which matters because it is
## on the debug panel and a slider that moves nothing is worse than no slider.
const AMBIENT_ENERGY := 0.55
const AMBIENT_COLOR := Color(0.60, 0.72, 0.86)   ## the sky, roughly, as a flat fill
const AMBIENT_SKY_MIX := 0.0       ## 1.0 makes AMBIENT_ENERGY inert. See above.

## DEPTH fog, and depth fog only.
##
## VOLUMETRIC fog does not exist in GL Compatibility -- it is a Forward+
## feature, and this game ships to web, which has no other renderer. A
## volumetric control here would be a slider that does nothing in the build
## that matters, so there is not one. What IS available is `fog_*`, which is a
## per-pixel depth fade: it does the job asked of it here, which is to soften
## the far edge of the map into the sky instead of ending at a hard line.
const FOG_ON := true
const FOG_DENSITY := 0.0035     ## 0.008 greyed the whole far half
const FOG_COLOR := Color(0.62, 0.74, 0.84)
const FOG_SUN_SCATTER := 0.18
const FOG_AERIAL := 0.35           ## blends fog toward the sky colour by depth

const GLOW_ON := true
const GLOW_INTENSITY := 0.22    ## 0.35 blew the lit windows to white
const GLOW_BLOOM := 0.05

## Handles the debug menu drives. Public on purpose: the menu is handed these
## rather than reaching into the tree for them, so it cannot bind to a node
## path that a later refactor moves.
var env: Environment
var sun: DirectionalLight3D


func _ready() -> void:
	_add_sky()
	_add_sun()


func _add_sky() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = GROUND_HORIZON
	sky_mat.ground_bottom_color = GROUND_BOTTOM
	sky_mat.sun_angle_max = 30.0

	var sky := Sky.new()
	sky.sky_material = sky_mat
	# Both set explicitly. Left at their defaults the sky came back as the
	# engine clear colour -- a flat grey slab above the horizon that reads as
	# "the lighting is broken" when the lighting was fine and the BACKGROUND
	# was never drawn.
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_128

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_sky_contribution = AMBIENT_SKY_MIX
	env.ambient_light_energy = AMBIENT_ENERGY
	# Standard, not Filmic and not AgX. The palette is authored in sRGB and
	# converted once; a tonemapper that desaturates undoes the thing the
	# palette is FOR. Blender's view_transform is Standard for the same reason.
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0

	env.fog_enabled = FOG_ON
	env.fog_density = FOG_DENSITY
	env.fog_light_color = FOG_COLOR
	env.fog_sun_scatter = FOG_SUN_SCATTER
	env.fog_aerial_perspective = FOG_AERIAL

	env.glow_enabled = GLOW_ON
	env.glow_intensity = GLOW_INTENSITY
	env.glow_bloom = GLOW_BLOOM

	# Off by default and left for the debug menu to switch on: a colour grade
	# applied by default is a second place the palette lives, and the palette
	# already has one.
	env.adjustment_enabled = false

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)



func _add_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.light_angular_distance = SUN_ANGULAR
	sun.shadow_enabled = true
	# A bias this small only works because nothing here is thin: every surface
	# in the village is a chamfered block at least a few centimetres deep.
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.directional_shadow_max_distance = 60.0
	sun.rotation_degrees = SUN_EULER
	add_child(sun)
