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

static func save_template_config():
	var template = {
		"venues": [
			{"name": "CiRCLE", "location": "Tokyo", "initial_owner": "Poppin'Party"},
			{"name": "Galaxy", "location": "Shinjuku", "initial_owner": "Poppin'Party"},
			{"name": "7th!", "location": "Shibuya", "initial_owner": "Roselia"},
			{"name": "Space", "location": "Kita-Senju", "initial_owner": ""} # Neutral Venue Example
		],
		"bands": [
			{
				"name": "Poppin'Party",
				"members": [
					{"name": "Kasumi", "role": "Vo/Gt", "perf": 25, "stam": 20}
				]
			},
			{
				"name": "Roselia",
				"members": [
					{"name": "Yukina", "role": "Vo", "perf": 35, "stam": 12}
				]
			}
		],
		"events": [
			{"id": "RAS_RAID", "desc": "RAISE A SUILEN disrupts!", "trigger_turn": 3}
		]
	}
	
	var file = FileAccess.open(DEFAULT_CONFIG_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(template, "\t"))
	file.close()
