extends RefCounted
class_name ShotWindow

## Park the render window off-screen and stop it taking focus.
##
## It still renders -- get_root().get_texture() needs a real swapchain, so a
## screenshot run cannot be --headless -- it just never steals focus or covers
## anything. Agent-driven shot runs were interrupting the user several times an
## hour before this existed.
static func park() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_position(Vector2i(-6000, -6000))


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
