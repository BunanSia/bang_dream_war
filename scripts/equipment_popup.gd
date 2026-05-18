extends Control

# Connect these targeting paths to your scene node slots
@onready var current_slots_container: HBoxContainer = $MainPanel/CurrentSlotsBox
@onready var shop_grid: GridContainer = $MainPanel/ShopGrid
@onready var desc_label: RichTextLabel = $MainPanel/ItemDescription
@onready var action_button: Button = $MainPanel/ActionButton

var slot_scene = preload("res://scenes/shop_slot.tscn") # Reusing your modular slot setup scene!
var current_member := ""

var selected_item_data: Dictionary = {}
var is_selected_from_inventory: bool = false
var selected_inventory_index: int = -1

func _ready() -> void:
	current_member = GameStateBang.current_selected_member_name
	action_button.disabled = true
	action_button.pressed.connect(_on_action_pressed)
	$MainPanel/CloseButton.pressed.connect(queue_free) # Destroys the popup overlay panel safely
	
	# Load shop list items dynamically from your JSON utility file structure
	var catalog = ConfigManager.load_config_by_path("res://configs/shop_catalog.json")
	var gear_list = catalog.get("shop_items", {}).get("equipment", [])
	
	_populate_shop_grid(gear_list)
	_refresh_member_current_equipment()

## Renders the gear database items available to buy
func _populate_shop_grid(items: Array) -> void:
	for child in shop_grid.get_children(): child.queue_free()
	
	for item_data in items:
		var slot = slot_scene.instantiate()
		slot.custom_minimum_size = Vector2(100, 100)
		shop_grid.add_child(slot)
		slot.setup(item_data)
		slot.slot_focused.connect(func(data): _on_item_focused(data, false))

## Renders the gear slots currently attached to the selected character profile
func _refresh_member_current_equipment() -> void:
	for child in current_slots_container.get_children(): child.queue_free()
	
	var band = Global.event_facade.find_band(GameStateBang.player)
	var member = _find_active_member(band, current_member)
	if not member: return
	
	# Loop through their max inventory boundaries (e.g., maximum 3 slots)
	for i in range(member.equipped_items.size()):
		var gear = member.equipped_items[i]
		var slot = slot_scene.instantiate()
		slot.custom_minimum_size = Vector2(80, 80)
		current_slots_container.add_child(slot)
		
		# Map custom object structure back to standard catalog layout mapping format
		var gear_data = {"name": gear.item_name, "cost": gear.cost, "performance_bonus": gear.performance_bonus, "stamina_bonus": gear.power_bonus, "is_equipped": true, "index": i}
		slot.setup(gear_data)
		slot.slot_focused.connect(func(data): _on_item_focused(data, true))

func _on_item_focused(item_data: Dictionary, from_inventory: bool) -> void:
	selected_item_data = item_data
	is_selected_from_inventory = from_inventory
	action_button.disabled = false
	
	var display_text = "[b]%s[/b]\n" % item_data.get("name")
	display_text += "性能 (Performance): +%d\n" % item_data.get("performance_bonus", 0)
	display_text += "耐力 (Stamina): +%d\n" % item_data.get("stamina_bonus", 0)
	
	if from_inventory:
		selected_inventory_index = item_data.get("index", -1)
		action_button.text = "丟棄武器 (Discard Equipment)"
		display_text += "\n[color=red]目前已裝備。點擊按鈕將永久銷毀此道具。[/color]"
	else:
		action_button.text = "下令購買 (Purchase Equipment)"
		display_text += "\n[color=yellow]購買成本 (Cost): $%d[/color]" % item_data.get("cost", 0)
		
	desc_label.text = display_text

func _on_action_pressed() -> void:
	if selected_item_data.is_empty(): return
	
	var current_player = GameStateBang.player

	if is_selected_from_inventory:
		# DISCARD AXIS PIPELINE
		var band = Global.event_facade.find_band(current_player)
		var member = _find_active_member(band, current_member)
		if member and selected_inventory_index != -1:
			member.equipped_items.remove_at(selected_inventory_index)
			Global.event_facade.ui.game_log("🗑️ Discarded %s from slots." % selected_item_data.get("name"), "yellow")
	else:
		# PURCHASE AXIS PIPELINE
		# Check item weight limit capacity cap before finalizing purchase
		var band = Global.event_facade.find_band(current_player)
		var member = _find_active_member(band, current_member)
		if member && member.equipped_items.size() >= 3:
			desc_label.text = "[color=red]❌ 裝備欄位已滿！請先點擊上方已裝備道具進行丟棄。[/color]"
			return
			
		var success = Global.event_facade.buy_member_equipment(current_player, current_member, selected_item_data)
		if not success: return
		
	# Post-transaction structural refresh steps
	action_button.disabled = true
	_refresh_member_current_equipment()

func _find_active_member(band: Band, m_name: String):
	for m in band.members:
		if m.name == m_name: return m
	return null
