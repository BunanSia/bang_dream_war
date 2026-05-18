class_name GameInitializer

static func bootstrap(mode) -> Dictionary:
	var config = ConfigManager.load_config(mode)
	
	# 1. Parse All Venues (Instantiated without owners first)
	var world_map = {}
	for v_data in config["venues"]:
		world_map[v_data.name] = Venue.new(v_data.name, v_data.location)
	
	# 2. Parse All Bands & Members
	var bands = {}
	for b_data in config["bands"]:
		var member_objects = []
		for m in b_data.members:
			member_objects.append(Member.new(m.name, m.role, m.perf, m.stam))
		
		bands[b_data.name] = Band.new(b_data.name, member_objects)

	# 3. Dynamic Ownership Resolution (No longer hardcoded to 2 venues per band)
	for v_data in config["venues"]:
		var venue_obj = world_map[v_data.name]
		var owner_name = v_data.get("initial_owner", "")
		
		# If an owner name is provided and that band actually exists in our data
		if owner_name != "" and bands.has(owner_name):
			var owning_band = bands[owner_name]
			owning_band.add_venue(venue_obj)
		else:
			# Explicitly keep it neutral/null if no configuration matches
			venue_obj.owner = null

	# 4. Generate Complete Cross-Band Relationships
	var band_keys = bands.keys()
	for i in range(band_keys.size()):
		var current_band = bands[band_keys[i]]
		for j in range(band_keys.size()):
			if i != j:
				var other_band_name = band_keys[j]
				current_band.relations[other_band_name] = "Neutral"

	# 5. Parse Events
	var event_pool: Array[Event] = []
	for e_data in config["events"]:
		var event_obj = create_event_from_json(e_data)
		if event_obj:
			event_pool.append(event_obj)

	return {"bands": bands, "worldMap": world_map, "eventPool": event_pool}

static func create_event_from_json(data: Dictionary) -> Event:
	var event_id = data.get("id", "UNKNOWN")
	var description = data.get("desc", "")
	var target_turn = data.get("trigger_turn", 1)
	var actions_list = data.get("actions", [])
	var conditions_dict = data.get("conditions", {})	
# The runtime execution lambda wrapper evaluated during process_events()
	var condition_check = func(current_turn: int, game_data: Dictionary) -> bool:
		# If no conditions are provided, default to failing safe or passing automatically
		if conditions_dict.is_empty():
			return false
			
		# Loop through every condition rule declared in the JSON block
		for condition_type in conditions_dict:
			var criteria = conditions_dict[condition_type]
			
			match condition_type:
				"min_turn":
					if current_turn < int(criteria):
						return false
						
				"exact_turn":
					if current_turn != int(criteria):
						return false
						
				"venue_owner":
					var target_venue = criteria.get("venue_name", "")
					var expected_owner = criteria.get("owner_name", "")
					
					var venue_obj = game_data.worldMap.get(target_venue)
					# If venue doesn't exist, or owner doesn't match, condition fails
					if not venue_obj:
						return false
					if expected_owner == "Neutral" and venue_obj.owner != null:
						return false
					if venue_obj.owner and venue_obj.owner.band_name != expected_owner:
						return false
						
				"band_relation":
					var band_a = criteria.get("band_a", "")
					var band_b = criteria.get("band_b", "")
					var expected_status = criteria.get("status", "")
					
					var band_obj = game_data.bands.get(band_a)
					if not band_obj or band_obj.get_relation(band_b) != expected_status:
						return false
						
				_:
					push_error("Parser Error: Unknown condition validator rule: " + condition_type)
					return false
					
		# If the loop completes without returning false, ALL conditions passed successfully!
		return true
	return Event.new(event_id, description, condition_check, actions_list)
