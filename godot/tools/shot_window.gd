extends RefCounted
class_name ShotWindow

## Park the render window off-screen and stop it taking focus.
##
## It still renders -- get_root().get_texture() needs a real swapchain, so a
## screenshot run cannot be --headless -- it just never steals focus or covers
## anything. Agent-driven shot runs were interrupting the user several times an
## hour before this existed.
## INSIDE the desktop, not beyond it. This parked at (-6000, -6000), which is
## outside any real desktop rectangle -- Windows refuses to place a window
## there, and Godot then dies immediately after the OpenGL line with nothing on
## stderr. It looks exactly like the game crashing on startup. The far corner
## of a 2560x1440 desktop is off-screen enough: the window is behind everything
## and never takes focus, which is all this was ever for.
const PARK_AT := Vector2i(2400, 1300)


static func park() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(PARK_AT)


## Can this run photograph anything at all?
##
## A parked window still needs a real swapchain, and there is not one when the
## machine has no usable display -- a locked session, a headless CI runner, or
## `--headless`. Every windowed run then dies the moment it tries to open a
## window, which looks exactly like the game crashing and is not.
##
## So a probe asks first, asserts what it can, and says which pictures it did
## not take rather than failing on the machine's account.
static func can_shoot() -> bool:
	return DisplayServer.get_name() != "headless"


## Take the picture, or don't, and say which.
##
## Every probe used to reach for the root texture and save it
## itself. Headless, `get_image()` returns null, the call throws, and -- this is
## the part that cost an afternoon -- the throw aborts `_process` BEFORE the
## `quit()` two lines below it. The probe does not fail; it hangs until
## something kills it, and reports nothing at all about what it was testing.
##
## So the picture goes through here, where not having a screen is an answer
## rather than an exception.
static func shoot(path: String) -> bool:
	if not can_shoot():
		return false
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return false
	var vp: Viewport = (loop as SceneTree).get_root()
	if vp == null or vp.get_texture() == null:
		return false
	var img: Image = vp.get_texture().get_image()
	if img == null:
		return false
	img.save_png(path)
	return true
