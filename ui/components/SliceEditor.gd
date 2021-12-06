# A code editor with a few conveniences:
#
# 1. Can show errors in an overlay, when given an array of
#    LanguageServerErrors
# 2. Dispatches a signal when scroll values change
# 3. If given a ScriptSlice instance, will synchronize the text state and the
#    ScriptSlice.current_text state
#
# NOTE: to position overlay errors correctly, the script relies on
# theme values, which are _not set_ by default. For this script to
# work properly, you _need_ to:
#
# 1. Set a theme
# 2. Make sure this theme has a font set
#
# The theme gets passed to the overlay at build time, so if you
# change the theme at runtime, make sure you also change the overlay's
# theme.
tool
class_name SliceEditor
extends TextEdit

const ErrorOverlayPopupScene := preload("ErrorOverlayPopup.tscn")

enum SCROLL_DIR { HORIZONTAL, VERTICAL }

signal scroll_changed(vector2)

var errors_overlay := SliceEditorOverlay.new()
var errors_overlay_message: ErrorOverlayPopup = ErrorOverlayPopupScene.instance()

# Array<LanguageServerError>
var errors := [] setget set_errors


func _ready() -> void:
	CodeEditorEnhancer.enhance(self)

	var scroll_offsets := Vector2.ZERO
	var found = 0
	for child in get_children():
		if found >= 2:
			break
		if child is VScrollBar:
			var vscrollbar: VScrollBar = child
			vscrollbar.connect(
				"value_changed", self, "_on_scrollbar_value_changed", [SCROLL_DIR.VERTICAL]
			)
			scroll_offsets.x = vscrollbar.get_minimum_size().x

			found += 1
		elif child is HScrollBar:
			var hscrollbar: HScrollBar = child
			hscrollbar.connect(
				"value_changed", self, "_on_scrollbar_value_changed", [SCROLL_DIR.HORIZONTAL]
			)
			scroll_offsets.y = hscrollbar.get_minimum_size().y

			found += 1

	errors_overlay.name = "ErrorsOverlay"
	errors_overlay.theme = theme
	add_child(errors_overlay)
	errors_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	errors_overlay.margin_right = -scroll_offsets.x
	errors_overlay.margin_bottom = -scroll_offsets.y
	add_child(errors_overlay_message)

	connect("text_changed", self, "_on_text_changed")
	connect("draw", self, "_update_overlays")


func _get_configuration_warning() -> String:
	if not theme:
		return "Without a theme set, slice editor will misbehave"
	if not theme.default_font:
		return "Theme is required to have a default font set"
	return ""


func _on_scrollbar_value_changed(value: float, direction: int) -> void:
	var vec2 = Vector2(0, value) if direction == SCROLL_DIR.VERTICAL else Vector2(value, 0)
	emit_signal("scroll_changed", vec2)


func sync_text_with_slice() -> void:
	if not LiveEditorState.current_slice:
		return
	text = LiveEditorState.current_slice.slice_text
	_on_text_changed()


# Creates and positions error overlays at the right position.
# Call after:
#
# 1. Changing errors
# 2. Scroll/Resize
func _reset_overlays() -> void:
	errors_overlay.clean()
	var slice_properties := LiveEditorState.current_slice
	if slice_properties == null:
		return

	var show_lines_from = slice_properties.start_offset
	var show_lines_to = slice_properties.end_offset

	for index in errors.size():
		var error: LanguageServerError = errors[index]

		var is_outside_lens: bool = (
			(show_lines_from > 0 and error.error_range.start.line < show_lines_from)
			or (show_lines_to > 0 and error.error_range.start.line > show_lines_to)
		)
		if is_outside_lens:
			continue

		var squiggly := errors_overlay.add_error(error)
		if not squiggly:
			continue

		squiggly.connect(
			"region_entered", errors_overlay_message, "show_message", [error.message, squiggly]
		)
		squiggly.connect("region_exited", errors_overlay_message, "hide_message", [squiggly])


func _update_overlays() -> void:
	errors_overlay.update_overlays()


# Receives an array of `LanguageServerError`s
func set_errors(new_errors: Array) -> void:
	if OS.is_debug_build():
		for err in errors:
			assert(err is LanguageServerError, "Error %s isn't a valid LanguageServerError" % [err])
	errors = new_errors
	_reset_overlays()


func _on_text_changed() -> void:
	if LiveEditorState.current_slice != null:
		LiveEditorState.current_slice.current_text = text
