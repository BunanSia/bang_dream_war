class_name MainGameUI
extends Node

const logo_path = "res://assets/logo"

@export var basic_ui: Node
@export var markers_parent: Node2D
@export var button_container: Control
@export var flag_container: Node2D
@export var dialogue_ui: CanvasLayer
@export var furniture_icon_container: Control

var logbox: RichTextLabel
var actionvbox: Control
var data_label: Label
var actionvbox_position
var data_position
var basicbuttons_position
var furnitureslots_position

signal basic_button_pressed(action_name: String)
signal venue_button_pressed(venue_name: String)
signal player_selection_confirmed(selection: String)
signal enemy_selection_confirmed(action_name: String)

func _ready() -> void:
	setup_ui()
	general_vbox_initialize()
	logbox_generation()

func setup_ui():
	for marker in basic_ui.get_children():
		match marker.name:
			"Actions": actionvbox_position = marker.global_position
			"Data": data_position = marker.global_position
			"BasicButtons": basicbuttons_position = marker.global_position
			"FurnitureSlots": furnitureslots_position = marker.global_position

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
	if not markers_parent or not button_container or not flag_container:
		push_error("UI Error: Missing inspectors assignments.")
		return
		
	for child in button_container.get_children():
		child.queue_free()
		
	for marker in markers_parent.get_children():
		if marker is Marker2D:
			var venue_name: String = marker.name
			var btn := Button.new()

			var texture := TextureRect.new()
			var owner = GameStateBang.data.worldMap[venue_name].owner.band_name
			owner = owner.replace("*", "_")
			var texture_path = logo_path + "/%s.png" % owner
			if ResourceLoader.exists(texture_path):
				var new_texture = load(texture_path)
				texture.texture = new_texture
			texture.global_position = marker.global_position
			flag_container.add_child(texture)

			# Get base sizes
			var tex_size = texture.texture.get_size()
			var rect_size = texture.get_size()

			# Calculate dynamic width and height maintaining aspect ratio
			var scale_factor = min(rect_size.x / tex_size.x, rect_size.y / tex_size.y)
			var dynamic_width = tex_size.x * scale_factor
			var dynamic_height = tex_size.y * scale_factor

			btn.custom_minimum_size = Vector2(dynamic_width, dynamic_height)
			btn.self_modulate.a = 0.2
			btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
			btn.grow_vertical = Control.GROW_DIRECTION_BOTH
			btn.global_position = marker.global_position
			
			btn.pressed.connect(func(): venue_button_pressed.emit(venue_name))
			button_container.add_child(btn)

func general_vbox_initialize() -> void:
	var vbox_container = BasicGameButtonsHBoxContainer.new()
	add_child(vbox_container)
	vbox_container.global_position = basicbuttons_position
	vbox_container.generate_buttons()
	vbox_container.button_pressed.connect(func(id): basic_button_pressed.emit(id))

func show_data():
	var ap_point = "Action:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].current_action_points + "\n"
	var supply = "Supply:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].supply + "\n"
	var money = "Money:" + "%s" % GameStateBang.data.bands[GameStateBang.current_band].money + "\n"
	var venue = "City:" + "%s" % GameStateBang.current_venue + "\n"
	var band = "Band:" + "%s" % GameStateBang.current_band + "\n"
	data_label = Label.new()
	data_label.text = ap_point + supply + money + venue + band
	if(GameStateBang.current_band != GameStateBang.player):
		var rel = "Relation:" + "%s" % GameStateBang.data.bands[GameStateBang.player].get_relation(GameStateBang.current_band)
		data_label.text += rel
	data_label.set("theme_override_font_sizes/font_size", 24)
	add_child(data_label)

func show_player_selection(player_id: String) -> void:
	_refresh_ui()
	actionvbox = PlayerSelectionVBoxContainer.new()
	actionvbox.establish(player_id)
	actionvbox.button_pressed.connect(func(sel): player_selection_confirmed.emit(sel))
	add_child(actionvbox)
	actionvbox.global_position = actionvbox_position
	show_data()

func show_enemy_selection(owner_name: String, relation_label: String) -> void:
	_refresh_ui()
	actionvbox = OtherBandSelectionVBoxContainer.new()
	actionvbox.establish("%s(%s)" % [owner_name, relation_label])
	actionvbox.button_pressed.connect(func(act): enemy_selection_confirmed.emit(act))
	add_child(actionvbox)
	actionvbox.global_position = actionvbox_position
	show_data()

func update_selection_label(new_text: String) -> void:
	if actionvbox and actionvbox.has_method("set_label"):
		actionvbox.set_label(new_text)

func _refresh_ui() -> void:
	if actionvbox:
		actionvbox.queue_free()
		actionvbox = null
	if data_label:
		data_label.queue_free()
		data_label = null

# Inside MainGameUI.gd

## Updates the visual layout to display icons for all furniture installed at the venue
func refresh_venue_furniture_icons(installed_furniture: Array) -> void:
	# 1. Clear out previous icons from old selections
	for child in furniture_icon_container.get_children():
		child.queue_free()
		
	# 2. If the venue has no upgrades, you can show a label or just leave it empty
	if installed_furniture.is_empty():
		return
		
	# 3. Loop through each furniture item object present at this location
	for item in installed_furniture:
		var tex_rect := TextureRect.new()
		
		# Configure layout rules so icons scale nicely inside your HBoxContainer
		tex_rect.custom_minimum_size = Vector2(40, 40) # Set to your desired icon resolution
		tex_rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		
		# Define path mapping pointing to your dynamic asset database structure
		var asset_path = "res://assets/furniture/%s.png" % item.item_name
		
		if ResourceLoader.exists(asset_path):
			tex_rect.texture = load(asset_path)
		else:
			# Fallback placeholder asset if an icon file is missing
			tex_rect.texture = load("res://assets/furniture/placeholder_building.png")
			
		# Optional: Add a simple tooltip hint so hovering the mouse reveals the name/stats
		tex_rect.tooltip_text = "%s\n+%d HP Recovery" % [item.item_name, item.hp_recovery_bonus]
		
		# 4. Commit to the visual scene layout tree
		furniture_icon_container.add_child(tex_rect)
