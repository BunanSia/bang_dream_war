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
	return engine.data.bands.get(target_name, null)

func add_band(b: Band) -> void:
	engine.data.bands[b.band_name] = b

func set_band_relations(band_a: String, band_b: String, relationship: String) -> void:
	var band1 = find_band(band_a)
	var band2 = find_band(band_b)
	
	if band1 and band2:
		band1.update_relation(band_b, relationship)
		band2.update_relation(band_a, relationship)
		ui.game_log(">> %s and %s are now %s!" % [band_a, band_b, relationship], "cyan")
	else:
		printerr("Facade Error: One or both bands not found: ", band_a, ", ", band_b)
