extends Node

@export var markers_parent: Node2D
@export var button_container: Control
@export var character_icon: TextureRect

var current_table
var current_band
var table_position
var buttons_position
var selected_member_name := ""

func _on_tree_item_clicked() -> void:
	print("tree item clicked")
	var selected_item: TreeItem = current_table.get_selected()
	if selected_item:
		# Assuming Column 0 contains the string of the member's name
		selected_member_name = selected_item.get_text(0)
		update_icon()

func update_icon():
	if character_icon:
		character_icon.texture = null # Or set a placeholder image
	var texture_path = "res://assets/icons/%s.png" % selected_member_name
	
	# 3. Safe Guard: Check if the image file actually exists before loading it
	if ResourceLoader.exists(texture_path):
		var new_texture = load(texture_path)
		character_icon.texture = new_texture

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_band = GameStateBang.current_band
	setup_ui()
	setup_member_table(GameStateBang.data.bands[current_band])
	setup_buttons()

func setup_ui():
	for marker in markers_parent.get_children():
		match marker.name:
			"Table": table_position = marker.global_position
			"Buttons": buttons_position = marker.global_position

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func setup_buttons():
	var vbox_container = MemberActionVBoxContainer.new()
	vbox_container.button_pressed.connect(_on_player_selection_selected)
	add_child(vbox_container)
	# vbox_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	vbox_container.global_position = buttons_position

func _on_player_selection_selected(name):
	match name:
		"Return":
			get_tree().change_scene_to_file("res://scenes/main_game.tscn")
		"Train Member":
			train_band_member(selected_member_name)

# Inside GameEventFacade.gd

func train_band_member(member_name: String) -> void:
	if(!member_name): return
	var band = GameStateBang.data.bands[current_band]

	# Find the member by name inside the Band object array
	for member in band.members:
		if member.name == member_name:
			if member.has_method("train"):
				member.train() # Triggers your mechanical stat changes inside your Member object
			else:
				printerr("Training Error: Member object missing 'train()' method.")
			setup_member_table(GameStateBang.data.bands[current_band])
			return

func setup_member_table(owner):
# 1. Clear the previous table if it exists
	if current_table:
		current_table.queue_free()
	
	# 2. Create the new table
	var table = Tree.new()
	current_table = table # Update the reference
	current_table.item_selected.connect(_on_tree_item_clicked)
	
	# --- THE FIX: Tell the table to grow ---
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# 2. Set the Anchor to Center Top
	# table.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	table.global_position = table_position

	# 3. Size Flags & Minimum Size
	# Since it's Center Top, it will shrink to its min_size unless we define it
	table.custom_minimum_size = Vector2(800, 400) 
	table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Optional: Force a minimum height so it doesn't collapse in a VBox
	table.custom_minimum_size.y = 200 
	# ---------------------------------------

	# 1. Setup Columns
	table.columns = 6
	table.set_column_title(0, "Name")
	table.set_column_title(1, "Part")
	table.set_column_title(2, "Perf")
	table.set_column_title(3, "Stam")
	table.set_column_title(4, "Max HP")
	table.set_column_title(5, "HP")
	table.column_titles_visible = true

	# 2. Create the Root (Hidden)
	var root = table.create_item()
	table.hide_root = true # Usually cleaner to hide the empty root item
	
	# 3. Add Data Rows
	for member in owner.members:
		var row = table.create_item(root)
		row.set_text(0, member.name)
		row.set_text(1, member.part)
		row.set_text(2, str(member.perf))
		row.set_text(3, str(member.stam))
		row.set_text(4, str(member.max_hp))
		row.set_text(5, str(member.hp))

	# 4. Column Expansion
	for i in range(table.columns):
		table.set_column_expand(i, true)

	add_child(table)
