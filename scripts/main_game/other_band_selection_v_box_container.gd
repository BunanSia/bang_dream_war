extends VBoxContainer

class_name OtherBandSelectionVBoxContainer

signal button_pressed(event_name)

# The list of labels for your buttons
var button_labels = ["Check members", "Challenge", "Cooperate"]
var labelbox
var label := ""

func _ready():
	pass

func establish(name):
	label = name
	generate_buttons()

func generate_buttons():
	for text in button_labels:
		create_btn(text)
	if can_attack_current_selection() and is_current_band_rival():
		create_btn("対バン")

func create_btn(text: String):
	# 1. Create a new Button instance
	var new_btn = Button.new()
	
	# 2. Set the text
	new_btn.text = text
	
	# 3. Connect the "pressed" signal using a lambda
	# This allows us to pass the specific text to the function
	new_btn.pressed.connect(func(): _on_button_pressed(text))
	
	# 4. Add it to the scene tree (as a child of this container)
	add_child(new_btn)

func _on_button_pressed(label):
	button_pressed.emit(label)

## 驗證當前被選取的場地 (current_venue) 是否與玩家擁有的任意場地相鄰
## @return: 如果相鄰且可進攻回傳 true，否則回傳 false
func can_attack_current_selection() -> bool:
	# 1. 直接從全域大腦撈取當前被選中的場地名稱與玩家樂團
	var target_venue_name = GameStateBang.current_venue
	var player_band_name = GameStateBang.player
	
	# 2. 安全防線：如果根本沒有選取任何場地，直接回傳 false
	if target_venue_name == "":
		return false
		
	var world_map = GameStateBang.data.worldMap
	var target_venue_obj = world_map.get(target_venue_name)
	
	# 3. 安全防線：如果目標場地不存在，或主人已經是玩家自己，則無法進攻
	if not target_venue_obj: return false
	if target_venue_obj.owner and target_venue_obj.owner.band_name == player_band_name:
		return false

	# 4. 獲取目標敵方場地在矩陣中的 Index
	var enemy_idx: int = GameStateBang.venue_indices.get(target_venue_name, -1)
	if enemy_idx == -1: return false

	# 5. 🎯 核心矩陣掃描：找尋玩家領地與當前目標的連線
	for v_name in world_map:
		var current_venue_obj = world_map[v_name]
		
		# 篩選出屬於玩家的領地作為跳板
		if current_venue_obj.owner and current_venue_obj.owner.band_name == player_band_name:
			var player_venue_idx: int = GameStateBang.venue_indices.get(v_name, -1)
			if player_venue_idx == -1: continue
			
			# 🔍 O(1) 矩陣查表
			if GameStateBang.adjacency_matrix[player_venue_idx][enemy_idx] == 1:
				print("⚔️ [Strategy] 路線開通！可由 [%s] 進攻選中的 [%s]" % [v_name, target_venue_name])
				return true 

	print("❌ [Strategy] 無法進攻 [%s]：路線未連接。" % target_venue_name)
	return false

## 檢查玩家樂團與當前選中的樂團是否為宿敵 (Rival) 關係
## @return: 如果雙方互為宿敵回傳 true，否則回傳 false
func is_current_band_rival() -> bool:
	var player_name = GameStateBang.player
	var target_name = GameStateBang.current_band
	
	# 1. 安全防線：確保全域變數有正確寫入，且玩家不是在跟自己對決
	if player_name == "" or target_name == "" or player_name == target_name:
		return false
		
	# 2. 從資料庫中撈出玩家的樂團物件 (Band Object)
	var bands_db = GameStateBang.data.bands
	if not bands_db.has(player_name):
		push_error("Faction Error: 資料庫中找不到玩家的樂團 -> " + player_name)
		return false
		
	var player_band_obj = bands_db[player_name]
	
	# 3. 🎯 調用你寫好的 API，檢查對該樂團的關係是否為 "Rival"
	var relation_status = player_band_obj.get_relation(target_name)
	
	if relation_status == "Rival":
		print("🔥 [Diplomacy] 宿敵相見分外眼紅！[%s] 與 [%s] 處於宿敵狀態！" % [player_name, target_name])
		return true
		
	return false
