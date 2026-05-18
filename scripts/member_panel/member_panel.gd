extends Node

@export var markers_parent: Node2D
@export var button_container: Control
@export var character_icon: TextureRect

var equipment_popup_scene = preload("res://scenes/equipment_popup.tscn")

var member
var current_table
var current_band
var table_position
var buttons_position
var tabs_position_start
var tabs_position: Dictionary = {}
var selected_member_name := ""
# Inside MemberPanel.gd
@onready var panel_train: Control = $LeftColumn/TrainPanel
@onready var panel_detailed_info: Control = $LeftColumn/DetailedInfoPanel
@onready var panel_rest: Control = $LeftColumn/RestPanel
@onready var panel_upgrade: Control = $LeftColumn/UpgradePanel
@onready var panel_others: Control = $LeftColumn/OthersPanel

# List your tab file prefixes exactly as they appear in assets/tabs/
# The index in this array will match your tab_index parameters (1 to 6)
const TAB_FILE_NAMES = [
	"train",       # Index 0 -> Map to tab_index 1
	"rest",        # Index 1 -> Map to tab_index 2
	"upgrade",     # Index 2 -> Map to tab_index 3
	"details",     # Index 3 -> Map to tab_index 4
	"strengthen",  # Index 4 -> Map to tab_index 5
	"others"       # Index 5 -> Map to tab_index 6
]

# Assuming your uniform tab size matches the reference image layout dimensions
# e.g., Width: 100px, Height: 60px. Adjust these to fit your assets exactly!
const TAB_SIZE = Vector2(100, 60)

## Your pre-existing global positioning mapping tracking coordinate spots
## e.g., { 1: Vector2(50, 100), 2: Vector2(50, 170), ... }


func _ready() -> void:
	current_band = GameStateBang.current_band
	setup_ui()
	setup_member_table(GameStateBang.data.bands[current_band])
	setup_buttons()
	# Mock data setup if not initialized elsewhere
	if tabs_position.is_empty():
		_initialize_mock_positions()
		
	spawn_dynamic_tabs()

## Dynamically constructs the visual layout and binds interaction signals
func spawn_dynamic_tabs() -> void:
	for i in range(TAB_FILE_NAMES.size()):
		var tab_index = i + 1 # Convert 0-offset array loop to your 1-6 layout index
		
		# 1. Safely check if a positioning rule exists for this specific tab index
		if not tabs_position.has(tab_index):
			push_error("Spawn Error: No positioning coordinate declared for tab: %d" % tab_index)
			continue
			
		var target_pos = tabs_position[tab_index]
		
		# 2. Spawn and configure the visual TextureRect icon layer
		var tex_rect := TextureRect.new()
		tex_rect.name = "TabIcon_" + TAB_FILE_NAMES[i]
		tex_rect.global_position = target_pos
		tex_rect.custom_minimum_size = TAB_SIZE
		tex_rect.size = TAB_SIZE
		
		# Enforce layout protection scaling states
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE # Passes clicks down to the button overlay!
		
		# Try loading your graphical asset cleanly
		var path = "res://assets/tabs/%s.png" % TAB_FILE_NAMES[i]
		if ResourceLoader.exists(path):
			tex_rect.texture = load(path)
		else:
			push_error("Asset Error: Missing tab icon texture at path: " + path)
			
		# Add the visual graphic directly to the panel scene canvas structure
		add_child(tex_rect)
		
		# 3. Spawn the invisible interaction Button directly covering the image space
		var overlay_btn := Button.new()
		overlay_btn.name = "TabBtn_" + TAB_FILE_NAMES[i]
		overlay_btn.global_position = target_pos
		overlay_btn.custom_minimum_size = TAB_SIZE
		overlay_btn.size = TAB_SIZE
		
		# Make the standard background texture transparent so it doesn't mask your icon artwork
		overlay_btn.flat = true 
		
		# 4. CRITICAL: Bind the unique index parameter directly into the signal payload
		overlay_btn.pressed.connect(_on_tab_button_pressed.bind(tab_index))
		
		# Add the button directly to the scene tree grid loop layer
		add_child(overlay_btn)

## Placeholder generator to represent your pre-existing coordinate array
func _initialize_mock_positions() -> void:
	# Generates a clean vertical column layout stack on the left side of your screen
	var start_y = tabs_position_start.y
	var spacing_y = 75
	for i in range(1, 7):
		tabs_position[i] = Vector2(tabs_position_start.x, start_y + ((i - 1) * spacing_y))

func _on_tab_button_pressed(tab_index: int) -> void:
	if(!selected_member_name): return
	# Hide all sub-views by default
	panel_detailed_info.visible = false
	panel_rest.visible = false
	panel_upgrade.visible = false
	panel_others.visible = false
	panel_train.visible = false

	match tab_index:
		1: _on_train_button_pressed(selected_member_name)          # Triggering your pre-existing code
		2: _setup_rest_tab()            # [2] 補給 / Rest
		3: _setup_upgrade_tab()         # [3] 升級 / Promotion
		4: _setup_details_tab()         # [4] 詳細 / Biography
		5: _on_equip_button_pressed()   # Triggering your pre-existing code
		6: _setup_others_tab()          # [6] 其他 / Management

# Inside MemberPanel.gd -> Rest Context

func _setup_rest_tab() -> void:
	panel_rest.visible = true
	var band = Global.event_facade.find_band(GameStateBang.player)
	# Display current stats and operational cost calculations
	$LeftColumn/RestPanel/SupplyLabel.text = "目前樂團補給 (Current Supply): %d / %d" % [band.supply, band.get_total_max_supply(GameStateBang.data.worldMap)]
	$LeftColumn/RestPanel/MemberHPLabel.text = "團員體力 (Member HP): %d / %d" % [member.hp, member.get_total_max_hp()]
	$LeftColumn/RestPanel/SupplyLabel.add_theme_color_override("font_color", Color.BLACK)
	$LeftColumn/RestPanel/MemberHPLabel.add_theme_color_override("font_color", Color.BLACK)
	
	# Disable the rest action execution if the performer is already fully healed
	$LeftColumn/RestPanel/RestButton.disabled = (member.hp >= member.get_total_max_hp() or band.supply < 10)

func _on_rest_button_pressed() -> void:
	var band = Global.event_facade.find_band(GameStateBang.player)
	
	# Transaction cost checks: Spend 10 tactical supply points for baseline restructuring
	if band.supply >= 10:
		band.supply -= 10
		
		# Recovery application math formulas
		var hp_healed = 30
		var xp_granted = 15
		
		member.hp = clampi(member.hp + hp_healed, 0, member.get_total_max_hp())
		if member.has_method("gain_xp"):
			member.gain_xp(xp_granted)
		elif "xp" in member:
			member.xp += xp_granted
			
		Global.event_facade.ui.game_log("☕ %s rested! Restored %d HP and gained %d XP." % [member.name, hp_healed, xp_granted], "green")
		_setup_rest_tab() # Instantly refreshes text values on the UI display layout!

# Inside MemberPanel.gd -> Detail Context

func _setup_details_tab() -> void:
	panel_detailed_info.visible = true
	var band = Global.event_facade.find_band(GameStateBang.player)

	# Add custom bio blurbs directly out of your member attributes setup mapping
	var profile_blurb = member.get("bio")
	var bio_text = "[color=black]"
	bio_text += "\n[i]%s[/i]" % profile_blurb
	bio_text += "[/color]"
	$LeftColumn/DetailedInfoPanel/RichTextLabel.text = bio_text
	$LeftColumn/DetailedInfoPanel/RichTextLabel.custom_minimum_size = Vector2(250, 250)

func _setup_info_tab():
	# Build out clean data layout tracking fields
	var bio_text = "團員簡介 (Performer Profile)\n\n"
	bio_text += "姓名 (Name): %s\n" % member.name
	bio_text += "位置 (Role): %s\n" % member.part
	bio_text += "等級 (Level): %d (經驗值 XP: %d)\n" % [member.level, member.xp]
	bio_text += "體力狀態 (HP): %d / %d\n" % [member.hp, member.max_hp]
	bio_text += "演奏表現 (Perf): %d\n" % member.get_total_performance()
	bio_text += "耐力係數 (Stam): %d\n" % member.stam	
	$Info.text = bio_text
	$Info.custom_minimum_size = Vector2(250, 250)


# Inside MemberPanel.gd -> Upgrade Context

func _setup_upgrade_tab() -> void:
	panel_upgrade.visible = true
	var band = Global.event_facade.find_band(GameStateBang.player)

	var member_lvl = member.get("level") # Assumes your member profiles track level thresholds
	var current_role = member.part
	var text = "[color=black]"
	
	# Fetch matching roadmap records out of our upgrades data payload configurations
	var upgrades_cfg = ConfigManager.load_config_by_path("res://configs/upgrades.json").get("promotions", {})
	$LeftColumn/UpgradePanel/InfoLabel.custom_minimum_size = Vector2(250, 250)
	$LeftColumn/UpgradePanel/UpgradeButton.add_theme_color_override("font_color", Color.BLACK)
	if not upgrades_cfg.has(current_role):
		text +="該成員已達到最高職業限界... (Max Tier Reached.)"
		text +="[/color]"
		$LeftColumn/UpgradePanel/InfoLabel.text = text
		$LeftColumn/UpgradePanel/UpgradeButton.disabled = true
		return
		
	var target_tier_data = upgrades_cfg[current_role]
	var next_title = target_tier_data["next_tier"]
	var req_lvl = target_tier_data["level_required"]
	var gold_cost = target_tier_data["cost"]
	
	var ui_msg = "可晉升至 (Promotion Target): [b]%s[/b]\n" % next_title
	ui_msg += "等級需求 (Level Req): %d / [color=yellow]%d\n" % [member_lvl, req_lvl]
	ui_msg += "資金花費 (Cost): $%d (擁有: $%d)\n" % [gold_cost, band.money]
	text += ui_msg
	text += "[/color]"
	$LeftColumn/UpgradePanel/InfoLabel.text = text
	# Enforce both financial check variables and experience tiering prerequisites
	$LeftColumn/UpgradePanel/UpgradeButton.disabled = (member_lvl < req_lvl or band.money < gold_cost)

func _on_upgrade_button_pressed() -> void:
	var band = Global.event_facade.find_band(GameStateBang.player)
	var upgrades_cfg = ConfigManager.load_config_by_path("res://config/upgrades.json").get("promotions", {})
	var tier_data = upgrades_cfg[member.role]
	
	# Deduct costs and adjust member identity fields
	band.money -= tier_data["cost"]
	member.role = tier_data["next_tier"]
	member.base_performance += tier_data["perf_boost"]
	
	Global.event_facade.ui.game_log("⚡ EVOLUTION: %s has evolved into a %s!" % [member.name, member.role], "purple")
	_setup_upgrade_tab() # Force visual components recalculation state instantly!

func _on_tree_item_clicked() -> void:
	print("tree item clicked")
	var selected_item: TreeItem = current_table.get_selected()
	if selected_item:
		# Assuming Column 0 contains the string of the member's name
		selected_member_name = selected_item.get_text(0)
		_get_member()
		update_icon()
		_setup_info_tab()
		_on_tab_button_pressed(4)
# Inside MemberPanel.gd -> Management Context

func _setup_others_tab() -> void:
	panel_others.visible = true
	$OthersPanel/WarningLabel.text = "⚠️ 警告: 您正在準備解除 [color=red]%s[/color] 的職務。\n解雇後該成員與其全部附帶裝備將被永久清除。" % member.name

func _on_layoff_button_pressed() -> void:
	var band = Global.event_facade.find_band(GameStateBang.player)
	
	# Prevent the player from deleting their entire squad down to 0 members
	if band.members.size() <= 1:
		$OthersPanel/WarningLabel.text = "[color=red]❌ 錯誤: 樂團內必須保留至少一名成員！[/color]"
		return
		
	# Find indices tracking location records and purge the element loop array
	for i in range(band.members.size()):
		if band.members[i].name == GameStateBang.current_selected_member_name:
			var fired_member_name = band.members[i].name
			band.members.remove_at(i)
			
			Global.event_facade.ui.game_log("❌ LAYOFF: %s has been removed from the roster." % fired_member_name, "red")
			
			# Reset target trackers back to safe default empty strings
			GameStateBang.current_selected_member_name = ""
			
			# Force parent interface viewport reload to update the right-side roster table!
			setup_member_table(GameStateBang.bands[GameStateBang.current_band])
			selected_member_name = ""
			GameStateBang.current_selected_member_name = selected_member_name
			return

func update_icon():
	if character_icon:
		character_icon.texture = null # Or set a placeholder image
	var texture_path = "res://assets/icons/%s.png" % selected_member_name
	
	# 3. Safe Guard: Check if the image file actually exists before loading it
	if ResourceLoader.exists(texture_path):
		var new_texture = load(texture_path)
		character_icon.texture = new_texture


func setup_ui():
	for marker in markers_parent.get_children():
		match marker.name:
			"Table": table_position = marker.global_position
			"Buttons": buttons_position = marker.global_position
			"TabPositions": tabs_position_start = marker.global_position
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

# Inside GameEventFacade.gd
func _on_train_button_pressed(member_name: String) -> void:
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
	table.custom_minimum_size = Vector2(800, 400) 
	table.add_theme_font_size_override("font_size", 28)
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

func _on_equip_button_pressed() -> void:
	if selected_member_name == "":
		print("Please select a character row from the status table first!")
		return
	GameStateBang.current_selected_member_name = selected_member_name
	# Instantiate the panel scene overlay
	var popup_instance = equipment_popup_scene.instantiate()
	# Append it straight to your current scene root view wrapper stack
	add_child(popup_instance)

func _get_member():
	var band = GameStateBang.data.bands[current_band]
	for band_member in band.members:
		if band_member.name == selected_member_name: member = band_member
