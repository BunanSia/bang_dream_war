class_name ConfigManager

const BASE_PATH = "res://configs/"
const DEFAULT_CONFIG_PATH = "res://configs/configs.json"

static func load_config(mode: int) -> Dictionary:
	# Convert your PlotMode enum integer to a corresponding string filename
	var file_name = "story_events.json" # Fallback default
	
	match mode:
		PlotMode.PlotMode.STORY:
			file_name = "story_events.json"
		PlotMode.PlotMode.FREEPLAY:
			file_name = "freeplay_events.json"
		PlotMode.PlotMode.TUTORIAL:
			file_name = "tutorial_events.json"
			
	var full_path = BASE_PATH + file_name
	
	# File loading logic
	if not FileAccess.file_exists(full_path):
		push_error("Config Error: File not found at path " + full_path)
		return {}
		
	var file = FileAccess.open(full_path, FileAccess.READ)
	var json_text = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_text)
	if error == OK:
		var data_received = json.get_data()
		if data_received is Dictionary:
			return data_received
			
	push_error("Config Error: Failed to parse JSON from " + full_path)
	return {}

static func load_config_by_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK:
		return json.get_data() if json.get_data() is Dictionary else {}
	return {}

# ==========================================
# 資料讀取 (Data Loading)
# ==========================================
static func _load_stratagems() -> void:
	var file_path = "res://data/stratagems.json"
	GameStateBang.stratagem_db = load_config_by_path(file_path)

static func _load_venue_database() -> void:
	var file_path = "res://data/venues.json"
	GameStateBang.venue_database = load_config_by_path(file_path)

static func _load_counter_matrix() -> void:
	GameStateBang.counter_matrix = load_config_by_path("res://data/instrument_matrix.json")

static func _load_free_members():
	var file_path = "res://data/free_members.json"
	if FileAccess.file_exists(file_path):
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(file_path)) == OK:
			GameStateBang.free_member_pool = json.data

static func _load_shop_catalog():
	load_config_by_path("res://configs/shop_catalog.json")
