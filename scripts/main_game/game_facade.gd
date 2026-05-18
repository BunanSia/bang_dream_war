class_name GameEventFacade
extends Node

var engine: Node # Reference back to core GameEngine
var ui: MainGameUI

func _init(_engine: Node, _ui: MainGameUI) -> void:
	engine = _engine
	ui = _ui

# ==============================================================================
# --- STORY & PLOT REFLECTION APIS ---
# ==============================================================================

func play_dialogue(file_path: String) -> void:
	var sequence = ScriptParser.parse_dialogue_file(file_path)
	if sequence.size() > 0 and ui.dialogue_ui:
		ui.dialogue_ui.dialogue_engine.start_dialogue(sequence)
		await ui.dialogue_ui.dialogue_engine.dialogue_finished

func remove_band_member(band_name: String, member_name: String) -> void:
	var band = find_band(band_name)
	if band:
		band.remove_member(member_name)
		ui.game_log("System: Removed %s from %s" % [member_name, band_name], "yellow")

func add_band_member(band_name: String, member_name: String) -> void:
	var band = find_band(band_name)
	if band:
		band.add_member(member_name, "Gt", 40, 25)
		ui.game_log("System: Added %s from %s" % [member_name, band_name], "yellow")

func create_and_add_band(band_name: String, member_names: Array) -> void:
	var ras = Band.new(band_name, [])
	if "CHU2" in member_names: ras.add_member("CHU2", "Prod", 45, 10)
	if "Otae" in member_names:  ras.add_member("Otae", "Gt", 40, 25)
	
	add_band(ras)
	ui.game_log("A new rival emerges: %s!" % band_name, "magenta")


# ==============================================================================
# --- DATA & STATE MUTATOR APIS (Moved Here) ---
# ==============================================================================

func find_band(target_name: String) -> Band:
	return GameStateBang.data.bands.get(target_name, null)

func add_band(b: Band) -> void:
	GameStateBang.data.bands[b.band_name] = b

func set_band_relations(band_a: String, band_b: String, relationship: String) -> void:
	var band1 = find_band(band_a)
	var band2 = find_band(band_b)
	
	if band1 and band2:
		band1.update_relation(band_b, relationship)
		band2.update_relation(band_a, relationship)
		ui.game_log(">> %s and %s are now %s!" % [band_a, band_b, relationship], "cyan")
	else:
		printerr("Facade Error: One or both bands not found: ", band_a, ", ", band_b)
# Inside GameEventFacade.gd
# Inside GameEventFacade.gd

func buy_furniture_for_venue(band_name: String, venue_name: String, furniture_data: Dictionary) -> bool:
	var band = find_band(band_name)
	# Safely access the venue from your central game engine's data resource
	var venue = GameStateBang.data.worldMap.get(venue_name)
	
	if not band or not venue:
		printerr("Purchase Error: Invalid Band or Venue mapping.")
		return false
		
	if venue.owner != band:
		ui.game_log("❌ You cannot buy upgrades for a venue you do not control!", "red")
		return false
		
	var cost = furniture_data.get("cost", 0)
	if band.money >= cost:
		band.money -= cost
		
		var item = Furniture.new(
			furniture_data.get("name"),
			cost,
			furniture_data.get("hp_recovery_bonus", 0),
			furniture_data.get("supply_cap_bonus", 0),
			furniture_data.get("description", "")
		)
		
		# Commit the installation directly to the map location instead of the band!
		venue.installed_furniture.append(item)
		
		# Keep current supply safe within the bounds of the newly updated global maximums
		var new_max = band.get_total_max_supply(GameStateBang.data.worldMap)
		band.supply = clampi(band.supply, 0, new_max)
		
		ui.game_log("🛋️ Installed %s at %s! Global HP recovery boosted." % [item.item_name, venue_name], "green")
		return true
		
	ui.game_log("❌ Not enough money to purchase this installation!", "red")
	return false

## Buys equipment and attaches it to a specific performer profile
func buy_member_equipment(band_name: String, member_name: String, equip_data: Dictionary) -> bool:
	var band = find_band(band_name)
	if not band: return false
	
	var cost = equip_data.get("cost", 0)
	if band.money >= cost:
		for member in band.members:
			if member.name == member_name:
				band.money -= cost
				
				var item = Equipment.new(
					equip_data.get("name"),
					cost,
					equip_data.get("performance_bonus", 0),
					equip_data.get("power_bonus", 0),
					equip_data.get("max_hp_bonus", 0),
					equip_data.get("description", "")
				)
				
				member.equipped_items.append(item)
				return true
				
	return false
