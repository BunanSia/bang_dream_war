extends Camera2D

# Configurable scrolling settings
@export var drag_speed: float = 1.0
@export var zoom_speed: float = 0.05
@export var min_zoom: Vector2 = Vector2(0.5, 0.5)
@export var max_zoom: Vector2 = Vector2(1.5, 1.5)

var is_dragging: bool = false

# CHANGED FROM _unhandled_input TO _input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			is_dragging = true
		else:
			is_dragging = false

	if event is InputEventMouseMotion and is_dragging:
		global_position -= event.relative * drag_speed / zoom.x
