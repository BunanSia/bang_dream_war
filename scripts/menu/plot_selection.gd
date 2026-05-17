extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var vbox_container = PlotSelectionVBoxContainer.new()
	add_child(vbox_container)
	vbox_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
