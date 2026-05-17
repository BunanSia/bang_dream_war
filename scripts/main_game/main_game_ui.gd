class_name MainGameUI
extends Node

@export var markers_parent: Node2D
@export var button_container: Control
@export var dialogue_ui: CanvasLayer

var logbox: RichTextLabel
var actionvbox: Control

signal basic_button_pressed(action_name: String)
signal venue_button_pressed(venue_name: String)
signal player_selection_confirmed(selection: String)
signal enemy_selection_confirmed(action_name: String)

func _ready() -> void:
	general_vbox_initialize()
	logbox_generation()

func logbox_generation() -> void:
	logbox = RichTextLabel.new()
	logbox.name = "Dialogue"
	logbox.custom_minimum_size = Vector2(500, 150)
	logbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	logbox.bbcode_enabled = true
	logbox.scroll_following = true 
	add_child(logbox)
	logbox.show()

func game_log(message: String, color: String = "white") -> void:
	var formatted_text = "[color=%s]%s[/color]\n" % [color, message]
	if logbox:
		logbox.append_text(formatted_text)
	print(message)

func generate_venue_buttons() -> void:
	if not markers_parent or not button_container:
		push_error("UI Error: Missing inspectors assignments.")
		return
		
	for child in button_container.get_children():
		child.queue_free()
		
	for marker in markers_parent.get_children():
		if marker is Marker2D:
			var venue_name: String = marker.name
			var btn := Button.new()
			btn.text = venue_name
			btn.custom_minimum_size = Vector2(100, 40)
			btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
			btn.grow_vertical = Control.GROW_DIRECTION_BOTH
			btn.global_position = marker.global_position
			
			btn.pressed.connect(func(): venue_button_pressed.emit(venue_name))
			button_container.add_child(btn)

func general_vbox_initialize() -> void:
	var vbox_container = BasicGameButtonsHBoxContainer.new()
	add_child(vbox_container)
	vbox_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	vbox_container.generate_buttons()
	vbox_container.button_pressed.connect(func(id): basic_button_pressed.emit(id))

func show_player_selection(player_id: String) -> void:
	_clear_action_vbox()
	actionvbox = PlayerSelectionVBoxContainer.new()
	actionvbox.establish(player_id)
	actionvbox.button_pressed.connect(func(sel): player_selection_confirmed.emit(sel))
	add_child(actionvbox)
	actionvbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)

func show_enemy_selection(owner_name: String, relation_label: String) -> void:
	_clear_action_vbox()
	actionvbox = OtherBandSelectionVBoxContainer.new()
	actionvbox.establish("%s(%s)" % [owner_name, relation_label])
	actionvbox.button_pressed.connect(func(act): enemy_selection_confirmed.emit(act))
	add_child(actionvbox)
	actionvbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)

func update_selection_label(new_text: String) -> void:
	if actionvbox and actionvbox.has_method("set_label"):
		actionvbox.set_label(new_text)

func _clear_action_vbox() -> void:
	if actionvbox:
		actionvbox.queue_free()
		actionvbox = null
