class_name GameInitializer

static func bootstrap(mode) -> Dictionary:
	var config = ConfigManager.load_config(mode)
	
	# 1. Parse All Venues (Instantiated without owners first)
	var world_map = {}
	for v_data in config["venues"]:
		world_map[v_data.name] = Venue.new(v_data.name, v_data.location, v_data.type)
	
	# 2. Parse All Bands & Members
	var bands = {}
	for b_data in config["bands"]:
		var member_objects = []
		for m in b_data.members:
			member_objects.append(Member.new(m.name, m.part, m.perf, m.stam))
		
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
	_load_config()
	return {"bands": bands, "worldMap": world_map, "eventPool": event_pool}

static func _load_config():
	ConfigManager._load_free_members()
	ConfigManager._load_stratagems()
	ConfigManager._load_venue_database()
	ConfigManager._load_counter_matrix()

static func bootsave(mode) -> Dictionary:
	var save_path = "res://data/save.json"
	
	# ==========================================================
	# 🔥 核心分支：如果存檔存在，走【讀取存檔流】
	# ==========================================================
	if FileAccess.file_exists(save_path):
		var file = FileAccess.open(save_path, FileAccess.READ)
		var json_string = file.get_as_text()
		file.close()
		
		var json = JSON.new()
		if json.parse(json_string) == OK:
			var save_data = json.data
			print("💾 [System] 偵測到存檔，開始載入舊進度...")
			return _load_from_save_data(save_data)
		else:
			printerr("💾 [System] 存檔損毀，無法解析 JSON！強行啟動新遊戲...")
	return {}

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
	var event_obj = Event.new(event_id, description, condition_check, actions_list)
# 2. 🔥 核心修正：將當前進度（新遊戲或存檔）的觸發狀態同步還原
	event_obj.triggered = data.get("triggered", false)
	
	# 3. 🔥 關鍵蟬殼防線：深度拷貝原始的 JSON 資料到口袋變數中
	# 這樣未來存檔時，event_obj.to_dict() 才能直接拿出來倒回去，完美避開 Callable
	event_obj.raw_conditions_data = conditions_dict.duplicate(true)
	event_obj.raw_actions_data = actions_list.duplicate(true)
	return event_obj

## 輔助工具：將存檔 Dictionary 還原為真實物件群與全域狀態
static func _load_from_save_data(save_data: Dictionary) -> Dictionary:
	var world_map = {}
	var bands = {}
	var event_pool: Array[Event] = []
	
	# ---- 📌 1. 還原所有場地 (Venues) ----
	var saved_map = save_data.get("worldMap", {})
	for v_name in saved_map:
		var v_data = saved_map[v_name]
		var venue_obj = Venue.new(v_name, v_data.get("location", ""), v_data.get("type", ""))
		if "furnitures" in v_data:
			venue_obj.furnitures = v_data["installed_furniture"]
		world_map[v_name] = venue_obj
		
	# ---- 📌 2. 還原所有樂團與成員 (Bands & Members) ----
	var saved_bands = save_data.get("bands", {})
	for b_name in saved_bands:
		var b_data = saved_bands[b_name]
		var member_objects = []
		for m_data in b_data.get("members", []):
			var member_obj = Member.new(
				m_data.get("name", ""), 
				m_data.get("part", ""), 
				m_data.get("perf", 10), 
				m_data.get("stam", 10)
			)
			member_obj.hp = m_data.get("hp", 100)
			member_obj.max_hp = m_data.get("max_hp", 100)
			member_obj.xp = m_data.get("xp", 0)
			member_objects.append(member_obj)
			
		var band_obj = Band.new(b_name, member_objects)
		band_obj.money = b_data.get("money", 1000)
		band_obj.supply = b_data.get("supply", 50)
		band_obj.goal = b_data.get("goal", "")
		band_obj.type = b_data.get("type", "")
		if "relations" in b_data:
			band_obj.relations = b_data["relations"].duplicate()
		bands[b_name] = band_obj

	# ---- 📌 3. 重新綁定地圖節點擁有權 ----
	for v_name in saved_map:
		var v_data = saved_map[v_name]
		var venue_obj = world_map[v_name]
		var owner_name = v_data.get("owner", "")
		if owner_name != "" and bands.has(owner_name):
			bands[owner_name].add_venue(venue_obj)
		else:
			venue_obj.owner = null

	# ---- 📌 4. 還原事件池 ----
	for e_data in save_data.get("eventPool", []):
		var event_obj = create_event_from_json(e_data)
		if event_obj:
			event_pool.append(event_obj)
	_load_config()
	# ==========================================================
	# 🔥 核心修正：從 JSON 頂層抽離這 10 個核心控制參數（給予安全預設值）
	# ==========================================================
	var global_states = {
		"turn": save_data.get("turn", 1),
		"current_band": save_data.get("current_band", ""),
		"attacker": save_data.get("attacker", ""),
		"defender": save_data.get("defender", ""),
		"current_venue": save_data.get("current_venue", ""),
		"turn_band": save_data.get("turn_band", ""),
		"is_running": save_data.get("is_running", true),
		"plot_mode": save_data.get("plot_mode", ""),
		"current_selected_member_name": save_data.get("current_selected_member_name", ""),
		"player": save_data.get("player", "")
	}
	
	# 將物件資料與全域狀態打包合併回傳
	return {
		"bands": bands, 
		"worldMap": world_map, 
		"eventPool": event_pool,
		"global_states": global_states # 餵給初始化器賦值
	}
