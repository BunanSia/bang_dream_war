class_name ScriptParser

static func parse_dialogue_file(file_path: String) -> Array[Dictionary]:
	var dialogue_sequence: Array[Dictionary] = []
	
	# 1. Safety check to see if the script path is valid
	if not FileAccess.file_exists(file_path):
		printerr("Dialogue script file missing at path: ", file_path)
		return dialogue_sequence
		
	var file = FileAccess.open(file_path, FileAccess.READ)
	
	# 2. Read the file line-by-line
	while not file.eof_reached():
		var raw_line = file.get_line().strip_edges()
		
		# Skip empty lines or comment lines (e.g., lines starting with #)
		if raw_line == "" or raw_line.begins_with("#"):
			continue
			
		# 3. Split the line at the first colon ":" to separate Speaker from Text
		var colon_index = raw_line.find(":")
		if colon_index != -1:
			# From index 0, grab 'colon_index' number of characters
			var speaker = raw_line.substr(0, colon_index).strip_edges()

			# From after the colon, grab everything else to the end of the string
			var text = raw_line.substr(colon_index + 1, raw_line.length() - colon_index - 1).strip_edges()
			# Append the structured line to our sequence array
			dialogue_sequence.append({
				"speaker": speaker,
				"text": text
			})
		else:
			# Edge case fallback: if a line has no speaker, treat it as a narrator block
			dialogue_sequence.append({
				"speaker": "Narrator",
				"text": raw_line
			})
			
	file.close()
	return dialogue_sequence
