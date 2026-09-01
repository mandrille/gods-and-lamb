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
