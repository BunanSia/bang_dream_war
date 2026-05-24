extends Control

signal done_shopping

@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var shop_grid: GridContainer = $ScrollContainer/ShopGrid
@onready var desc_label: RichTextLabel = $BottomDetailsBox/ItemDescription
@onready var buy_button: Button = $BottomDetailsBox/BuyButton

var slot_scene = preload("res://scenes/shop_slot.tscn")
var selected_item_data: Dictionary = {}

func _ready() -> void:
	# 1. Connect foundational control signals
	buy_button.pressed.connect(_on_buy_pressed)
	$BottomDetailsBox/ReturnButton.pressed.connect(_on_return_pressed)
	buy_button.disabled = true # Lock buy until something is selected
	
	# 2. Grab your dynamic catalog items array from your data configuration layer
	var catalog = _get_shop_catalog()
	populate_shop(catalog)

## Populates the 4x5 grid layout dynamically
func populate_shop(items: Array) -> void:
	# Clean out visual test items
	for child in shop_grid.get_children():
		child.queue_free()
	scroll_container.custom_minimum_size = Vector2(1920, 800)
		
	# Restrict display boundaries to your rule: Max 5 rows * 4 columns = 20 slots
	var max_slots = min(items.size(), 20)
	shop_grid.add_theme_constant_override("h_separation", 150) # 橫向間距
	shop_grid.add_theme_constant_override("v_separation", 150) # 縱向間距
	for i in range(max_slots):
			var item_data = items[i]
			var slot_instance = slot_scene.instantiate()
			
			# 3. CRITICAL FIX: Explicitly size the slot via code before appending it
			# Change Vector2 values below to match the exact size you want your cards to be
			slot_instance.custom_minimum_size = Vector2(150, 150)
			slot_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot_instance.size_flags_vertical = Control.SIZE_EXPAND_FILL
			
			shop_grid.add_child(slot_instance)
			slot_instance.setup(item_data)
				
			# Listen to the slot communication pipeline
			slot_instance.slot_focused.connect(_on_item_selected)


func _on_item_selected(item_data: Dictionary) -> void:
	selected_item_data = item_data
	buy_button.disabled = false
	
	# Dynamically extract parameters
	var item_name = item_data.get("name", "Unknown Item")
	var hp_bonus = item_data.get("hp_recovery_bonus", 0)
	var supply_bonus = item_data.get("supply_cap_bonus", 0)
	var cost = item_data.get("cost", 0)
	var custom_desc = item_data.get("description", "")
	
	# Assemble the BBCode layout text box
	var display_text = "[color=black]"
	display_text += "[b]%s[/b]\n" % item_name
	display_text += "1. HP Recovery: +%d\n" % hp_bonus
	display_text += "2. Supply Capacity: +%d\n" % supply_bonus
	
	if not custom_desc.is_empty():
		display_text += "說明 (Info): %s\n" % custom_desc
	display_text += "[/color]"
	display_text += "\n[color=yellow] Cost: $%d[/color]" % cost
	
	desc_label.text = display_text
	desc_label.fit_content = true
func _on_buy_pressed() -> void:
	if selected_item_data.is_empty(): return
	
	# Route the order to your lightweight data transaction Facade layer
	var current_venue = GameStateBang.current_venue
	var current_player = GameStateBang.turn_band
	# Assuming access tracking to your global EventFacade instance running inside core engine
	var success = Global.event_facade.execute_action(
		Global.event_facade.buy_furniture_for_venue,
		[current_player, current_venue, selected_item_data])
	if success:
		print("Investment approved, building launched.")
		# Turn off button or refresh view states
		buy_button.disabled = true
		desc_label.text = "建造命令已下達... (Construction ordered...)"

func _on_return_pressed() -> void:
	# Drop cleanly back into the main map world panel loop layout
	done_shopping.emit()

## Mock template simulating your external dynamic JSON lookup architecture pipeline
## Fetches catalog lists straight from the filesystem config architecture
func _get_shop_catalog() -> Array:
	# 1. Read raw dictionary from your pre-existing ConfigManager file engine
	# Ensure ConfigManager has an accessible load_config approach or edit path target here
	var full_catalog_data: Dictionary = ConfigManager.load_shop_catalog()
	
	if full_catalog_data.is_empty():
		push_error("Shop Error: Could not read or locate shop_catalog.json!")
		return []
		
	# 2. Extract the specific nested structural furniture array data block safely
	var shop_items_block = full_catalog_data.get("shop_items", {})
	var furniture_list = shop_items_block.get("furniture", [])
	
	return furniture_list
