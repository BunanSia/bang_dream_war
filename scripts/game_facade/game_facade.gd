class_name GameEventFacade
extends Node

signal battle_resolved

var engine: Node # Reference back to core GameEngine
var ui: MainGameUI
var current_battle = preload("res://scenes/live_battle_scene.tscn")
var current_battle_instance
var shop_scene = preload("res://scenes/furniture_shop.tscn")
var shop_instance
var member_panel_scene = preload("res://scenes/member_panel.tscn")
var member_panel_instance
var recruit_panel_scene = preload("res://scenes/recruit_panel.tscn")
var recruit_panel_instance
var policy_panel_scene = preload("res://scenes/band_policy_panel.tscn")
var current_policy_instance
# 預載你的戰前準備場景
var battle_prep_scene = preload("res://scenes/battle_preparation.tscn")
var prep_instance

var json

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
# inside GameEventFacade.gd 或負責行動的管理腳本

# 1. 行動點數對照表 (AP Cost Table)
# 使用函數名稱字串作為 Key，方便查找與對照
const AP_COST_TABLE: Dictionary = {
	"add_band_member": 1,
	"remove_band_member": 1,
	"set_band_relations": 2,
	"buy_furniture_for_venue": 2,
	"upgrade_member": 3,
	"train_member": 2,
	"start_invasion": 2,
	"update_band_policy": 3
}

## 檢查當前玩家的 AP 是否足夠執行該函數
func check_action_point(action_name: String) -> bool:
	if not AP_COST_TABLE.has(action_name):
		push_warning("AP系統: 找不到函數 '%s' 的 AP 消耗設定，預設允許執行。" % action_name)
		return true
		
	var cost = AP_COST_TABLE[action_name]
	
	# 假設你的 GameStateBang 有儲存目前的 AP 總數
	if GameStateBang.data.bands[GameStateBang.get_turn_band()].current_action_points >= cost:
		return true
		
	game_log("❌ 行動點數不足！需要 %d 點 AP，目前僅剩 %d 點。" % [cost, GameStateBang.data.bands[GameStateBang.get_turn_band()].current_action_points], "red")
	return false

## 扣除玩家的行動點數
func _deduct_action_point(action_name: String) -> void:
	if AP_COST_TABLE.has(action_name):
		var cost = AP_COST_TABLE[action_name]
		var band = GameStateBang.data.bands[GameStateBang.get_turn_band()]
		band.consume_action_points(cost)
		game_log("⚡ 消耗了 %d 點行動點數。剩餘 AP: %d" % [cost, band.current_action_points], "gray")

## 統一的行動執行管道。會自動檢查 AP，通過後才會扣點並執行目標函數。
## 回傳 Variant：如果是 bool 函數會回傳結果，其餘預設回傳 null
func execute_action(action: Callable, args: Array = []) -> Variant:
	var action_name = action.get_method()
	
	# 1. 執行安全門禁檢查
	if not check_action_point(action_name):
		return null # AP 不足，直接攔截不執行
		
	# 2. 通過檢查，扣除點數
	_deduct_action_point(action_name)
	
	# 3. 動態呼叫目標函數並帶入參數陣列 (使用 callv)
	return action.callv(args)

func remove_band_member(band_name: String, member_name: String) -> void:
	var band = find_band(band_name)
	if band:
		band.remove_member(member_name)
		game_log("System: Removed %s from %s" % [member_name, band_name], "yellow")

## 動態將新成員塞入指定樂團（完全抽離硬編碼）
func add_band_member(band_name: String, member_data: Dictionary) -> bool:
	var band = find_band(band_name)
	if not band:
		printerr("Facade Error: Band not found: ", band_name)
		return false
		
	# 1. 從傳入的 Dictionary 中安全地提取數值（若缺少欄位則給予防呆預設值）
	var m_name = member_data.get("name", "Unknown Member")
	var m_part = member_data.get("part", "Vocal")
	var m_perf = member_data.get("perf", 10)
	var m_stam = member_data.get("stam", 10)
	
	# 2. 呼叫 Band 物件內部的核心方法（配合你 Band 類別的參數順序，這裡加上屬性）
	# 註：如果你的 band.add_member 內部也硬編碼了 max_hp / hp，
	# 記得確保它們在內部有被正確初始化為 100
	band.add_member(m_name, m_part, m_perf, m_stam)
	
	# 3. 列印黃色系統日誌
	game_log("System: Added %s (%s) to %s" % [m_name, m_part, band_name], "yellow")
	return true

func create_and_add_band(band_name: String, member_names: Array) -> void:
	var ras = Band.new(band_name, [])
	if "CHU2" in member_names: ras.add_member("CHU2", "Prod", 45, 10)
	if "Otae" in member_names:  ras.add_member("Otae", "Gt", 40, 25)
	
	add_band(ras)
	game_log("A new rival emerges: %s!" % band_name, "magenta")


# ==============================================================================
# --- DATA & STATE MUTATOR APIS (Moved Here) ---
# ==============================================================================

func find_band(target_name: String) -> Band:
	return GameStateBang.data.bands.get(target_name, null)

func add_band(b: Band) -> void:
	GameStateBang.data.bands[b.band_name] = b

## 取得兩個樂團之間的關係狀態
func get_band_relation(band_a: String, band_b: String) -> String:
	var band1 = find_band(band_a)
	var band2 = find_band(band_b)
	
	if not band1 or not band2:
		printerr("Facade Error: Cannot fetch relation. One or both bands not found: ", band_a, ", ", band_b)
		return "Unknown" # 回傳安全防呆值
		
	# 假設你的 Band 物件內部有一個儲存關係的 Dictionary 或 Getter 方法
	# 例如 band1.relations = { "RAISE A SUILEN": "Ally", "Roselia": "Rival" }
	# 這裡我們優先從 band_a 的視角去撈出對 band_b 的關係
	if band1.has_method("get_relation"):
		return band1.get_relation(band_b)
	elif band1.get("relations") and band1.relations.has(band_b):
		return band1.relations[band_b]
		
	# 如果資料庫裡還沒有建立任何關係記錄，給予一個預設的初始關係（例如 "Neutral" 或者是空字串）
	return "Neutral"

func set_band_relations(band_a: String, band_b: String, relationship: String) -> void:
	var band1 = find_band(band_a)
	var band2 = find_band(band_b)
	
	if band1 and band2:
		band1.update_relation(band_b, relationship)
		band2.update_relation(band_a, relationship)
		game_log(">> %s and %s are now %s!" % [band_a, band_b, relationship], "cyan")
	else:
		printerr("Facade Error: One or both bands not found: ", band_a, ", ", band_b)

func buy_furniture_for_venue(band_name: String, venue_name: String, furniture_data: Dictionary) -> bool:
	var band = find_band(band_name)
	# Safely access the venue from your central game engine's data resource
	var venue = GameStateBang.data.worldMap.get(venue_name)
	
	if not band or not venue:
		printerr("Purchase Error: Invalid Band or Venue mapping.")
		return false
		
	if venue.owner != band:
		game_log("❌ You cannot buy upgrades for a venue you do not control!", "red")
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
		
		game_log("🛋️ Installed %s at %s! Global HP recovery boosted." % [item.item_name, venue_name], "green")
		return true
		
	game_log("❌ Not enough money to purchase this installation!", "red")
	return false

func game_log(log: String, color: String):
	if(ui): ui.game_log(log, color)

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

# inside event_facade.gd

## 從指定團員的裝備欄中移除/丟棄特定索引的道具
## 成功移除回傳 true，若資料不合法或找不到則回傳 false
func discard_member_equipped_item(band_name: String, member_name: String, item_index: int) -> bool:
	# 1. 查找對應的樂團資料
	var band = find_band(band_name)
	if not band:
		push_warning("EventFacade: 找不到指定的樂團 -> ", band_name)
		return false
		
	# 2. 查找樂團中對應的團員
	# 提示：如果 _find_active_member 原本只寫在 UI 裡，記得也要把它移植進來，
	# 或者確認這個 facade 本身有辦法取得團員實體。
	var member = get_member(band_name, member_name)
	if not member:
		push_warning("EventFacade: 找不到指定的團員 -> ", member_name)
		return false
		
	# 3. 驗證索引值是否合法，防止 remove_at 造成陣列越界崩潰 (Out of Bounds)
	if item_index < 0 or item_index >= member.equipped_items.size():
		push_warning("EventFacade: 裝備移除索引值無效 -> ", item_index)
		return false
		
	# 4. 執行核心丟棄邏輯
	member.equipped_items.remove_at(item_index)
	return true

## 🚀 執行團員晉升（指定特定分支路徑）
func upgrade_member(band_name: String, member_name: String, branch_index: int = 0) -> void:
	var band = execute_action(find_band, [band_name])
	var member = get_member(band_name, member_name)
	if not band or not member: return
	
	var branches = _get_promotion_branches(member.part)
	# 🛡️ 安全防線：防呆索引值越界或根本沒分支
	if branches.is_empty() or branch_index < 0 or branch_index >= branches.size():
		return 
		
	# 🎯 精準鎖定玩家挑選的那一條技能分支！
	var chosen_branch = branches[branch_index]
	
	var req_lvl = int(chosen_branch.get("level_required", 1))
	var gold_cost = int(chosen_branch.get("cost", 0))
	
	# 🛡️ 硬性指標條件檢查
	if int(member.get("level", 1)) < req_lvl or band.money < gold_cost:
		return

	# 扣款並完成該分支轉職
	band.money -= gold_cost
	member.part = chosen_branch.get("next_tier", member.part)
	member.base_performance += int(chosen_branch.get("perf_boost", 0))
	
	print("🎉 [轉職成功] %s 成功晉升為新的型態: [%s]!" % [member_name, member.part])

## 内部工具：撈出該職位當前可選的所有晉升分支陣列
func _get_promotion_branches(member_part: String) -> Array:
	var upgrades_cfg = ConfigManager.load_upgrade().get("promotions", {})
	return upgrades_cfg.get(member_part, []) # 如果找不到（滿級），回傳空陣列 []

func rest_member(band_name: String, member_name: String) -> void:
	var band = execute_action(find_band, [GameStateBang.get_turn_band()])
	
	# Transaction cost checks: Spend 10 tactical supply points for baseline restructuring
	if band.supply >= 10:
		band.supply -= 10
		
		# Recovery application math formulas
		var hp_healed = 30
		var xp_granted = 15
		var member = get_member(band_name, member_name)
		member.hp = clampi(member.hp + hp_healed, 0, member.get_total_max_hp())
		if member.has_method("gain_xp"):
			member.gain_xp(xp_granted)
		elif "xp" in member:
			member.xp += xp_granted

# Inside GameEventFacade.gd
func train_member(band_name: String, member_name: String) -> void:
	if(!member_name): return
	var band = GameStateBang.data.bands[band_name]

	var member = get_member(band_name, member_name)
	if member.has_method("train"):
		member.train() # Triggers your mechanical stat changes inside your Member object
	else:
		printerr("Training Error: Member object missing 'train()' method.")

func get_member(band_name: String, member_name: String):
	var band = GameStateBang.data.bands[band_name]

	# Find the member by name inside the Band object array
	for member in band.members:
		if member.name == member_name:
			return member
	return null
# ==========================================
# 通用場景切換核心 (私有輔助函數)
# ==========================================

## 取得當前的大地圖節點
func _get_main_map() -> Node:
	return ui.get_parent().get_parent()

## 進入子場景的通用邏輯
func _enter_sub_scene(instance: Node, log_msg: String, log_color: String = "red") -> void:
	game_log(log_msg, log_color)
	engine.remove_child(_get_main_map())
	engine.add_child(instance)

## 離開子場景並返回大地圖的通用邏輯
func _exit_sub_scene(instance: Node) -> void:
	if instance:
		engine.remove_child(instance)
		instance.queue_free()
		
	# 1. 重新掛載大地圖
	var main_map = _get_main_map()
	engine.add_child(main_map)
	
	# 2. 🔥 核心修正：返回大地圖時，立刻觸發刷新
	_refresh_main_map_ui(main_map)

## 負責對大地圖進行資料與視覺同步
func _refresh_main_map_ui(main_map: Node) -> void:
	# 這裡去呼叫你大地圖腳本內部的刷新函數
	# 假設你的大地圖腳本有一個叫 refresh_venues() 或 update_map() 的方法：
	engine.refresh_venues()
	game_log("[系統] 大地圖已重新載入，等待資料同步...", "gray")

func start_invasion(player: String, target: String) -> void:
	GameStateBang.attacker = player
	GameStateBang.current_venue = target
	GameStateBang.defender = GameStateBang.data.worldMap[target].owner.band_name
	
	prep_instance = battle_prep_scene.instantiate() as BattlePreparation
	_enter_sub_scene(prep_instance, "--- Live Battle Preparation ---")
	
	# 如果你在 Prep 結尾用的是自訂信號，這裡綁定它即可
	prep_instance.preparation_completed.connect(on_battle_roster_ready)

## 🎯 核心對接點：一拿到 Facade 封包，立刻無縫加載戰鬥畫面
func on_battle_roster_ready(packet: Dictionary) -> void:
	# 1. 如果是從 UI 按下的，先把準備畫面關掉
	# (注意：如果是雙 AI 觀戰，prep_instance 可能剛生成完就秒拋此函數，交由子場景管理器安全卸載)
	_exit_sub_scene(prep_instance)
	
	# 2. 建立大腦與實例化戰鬥畫面
	current_battle_instance = current_battle.instantiate()
	var b_brain = BattleController.new()
	current_battle_instance.add_child(b_brain)
	current_battle_instance.controller = b_brain
	
	_enter_sub_scene(current_battle_instance, "--- LIVE BATTLE ENGAGED ---")

	
	current_battle_instance.start_interactive_battle(
		packet.attacker_band, 
		packet.defender_band, 
		packet.target_venue
	)
	# 3. 🎯 直接解包（Unpack）字典，優雅對位！
	b_brain.setup_battle(
		packet.attacker_band, 
		packet.defender_band, 
		packet.target_venue, 
		packet.attacker_team, 
		packet.defender_team
	)

func stop_invation() -> void:
	# 戰鬥結束或撤退時，子場景管理器會精準拔掉 current_battle_instance，完全不污染大地圖
	if current_battle_instance:
		_exit_sub_scene(current_battle_instance)
		current_battle_instance = null
	battle_resolved.emit()
func start_shopping() -> void:
	shop_instance = shop_scene.instantiate()
	shop_instance.done_shopping.connect(stop_shopping)
	_enter_sub_scene(shop_instance, "--- Shopping ---")

func stop_shopping() -> void:
	_exit_sub_scene(shop_instance)
	shop_instance = null

func start_managing() -> void:
	member_panel_instance = member_panel_scene.instantiate() # 註：注意拼字若是 instantiate 記得改回
	member_panel_instance.done_managing.connect(stop_managing)
	_enter_sub_scene(member_panel_instance, "--- Start managing ---")

func stop_managing() -> void:
	_exit_sub_scene(member_panel_instance)
	member_panel_instance = null

func start_recruit() -> void:
	recruit_panel_instance = recruit_panel_scene.instantiate() # 註：注意拼字若是 instantiate 記得改回
	recruit_panel_instance.done_recruitment.connect(stop_recruit)
	_enter_sub_scene(recruit_panel_instance, "--- Start managing ---")

func stop_recruit() -> void:
	_exit_sub_scene(recruit_panel_instance)
	recruit_panel_instance = null

## 開啟設定樂團方針畫面
func start_setting_policy() -> void:
	current_policy_instance = policy_panel_scene.instantiate()
	
	# 監聽方針面板送出的「完成」訊號，並轉向接回停止函數
	current_policy_instance.policy_confirmed.connect(stop_setting_policy)
	
	# 呼叫你全域的進入次級場景管理
	_enter_sub_scene(current_policy_instance, "--- Band Policy Setup ---")

## 關閉設定樂團方針畫面，返回大地圖
func stop_setting_policy() -> void:
	if current_policy_instance:
		_exit_sub_scene(current_policy_instance)
		current_policy_instance = null

## 計算樂團在特定場地下的總戰力強度值
## 計算樂團在特定場地下的真實總戰力強度值（結合真實 JSON 資料庫）
func get_band_strength_for_venue(band_id: String, venue_id: String) -> int:
	var band = GameStateBang.data.bands[band_id]
	var venue_database = GameStateBang.venue_database
	var counter_matrix = GameStateBang.counter_matrix

	# 1. 第一道安全防線：確保樂團與大地圖節點存在
	if not band or not GameStateBang.data.has("worldMap") or not GameStateBang.data.worldMap.has(venue_id):
		printerr("Strength Calc Error: Invalid Band ID or Venue Node: ", band_id, " / ", venue_id)
		return 0
		
	# 取得該場地實例的基礎資訊（包含名字、地點與我們剛加的 type）
	var venue_instance = GameStateBang.data.worldMap[venue_id]
	var venue_type = venue_instance.get("type")
	
	# 2. 第二道安全防線：驗證 venue_database 是否有對應這個類型的設定檔
	if not venue_database or not venue_database.has(venue_type):
		printerr("Strength Calc Error: Missing profile in venue_database for type: ", venue_type, " (Venue: ", venue_id, ")")
		return 0
		
	# 3. 順利提取該場地類型的真實 JSON 數據修正檔
	var venue_template_data = venue_database[venue_type]
	var venue_mods = venue_template_data.get("modifiers", {})
	var total_strength: float = 0.0
	
	for member in band.members:
		var member_part = member.part  # 例如 "Vocal", "Guitar", "Bass", "Keyboard", "Drums"
		
		# ---- 📌 A. 攻擊表現 (Perf) 計算 ----
		var a_perf = member.get("perf")
		
		# 提取場地對該樂器編組的效能修正 (預設 0.0)與限流乘數 (預設 1.0)
		var env_perf_mod = venue_mods.get("perf_bonus", {}).get(member_part, 0.0)
		var throttle_multiplier = _get_venue_throttle_multiplier(member_part,venue_mods)
	
		# 計算樂器相剋相乘矩陣 (Matrix Modifier) 的環境期望值：
		# 因為是戰前估算，畫面上沒有特定的單一防守者，
		# 故我們跑遍相剋矩陣中所有可能面對的樂器，取其「平均加成」作為該職位在環境中的生存優勢。
		var matrix_mod: float = 0.0
		if counter_matrix and counter_matrix.has(member_part):
			var counter_targets: Dictionary = counter_matrix[member_part] # 取得如 {"Guitar": 0.1, "Vocal": -0.1}
			if not counter_targets.is_empty():
				var sum: float = 0.0
				for target in counter_targets:
					sum += counter_targets[target]
				matrix_mod = sum / counter_targets.size() # 取平均期望值值
		
		var final_perf = (a_perf * (1.0 + matrix_mod + env_perf_mod)) * throttle_multiplier
		
		# ---- 📌 B. 防禦耐力 (Stam) 計算 ----
		var d_stam = member.get("stam")
		var env_stam_mod = venue_mods.get("stam_nerf", {}).get(member_part, 0.0)
		
		var final_stam = d_stam * (1.0 + env_stam_mod)
		
		# ---- 📌 C. 生存健康度 (HP 權重) ----
		# 考慮到非滿血團員的戰力衰減
		var hp_ratio = float(member.hp) / float(maxi(1, member.max_hp))
		
		# ---- 📌 D. 核心公式權重結算 ----
		# 比照戰鬥傷害公式：Perf 造成的基礎傷害除以 2，Stam 減免除以 4
		# 輸出對戰局影響比重較高，因此給予對應的權重乘數，並乘以殘餘 HP
		var member_score = (final_perf * 0.5) + (final_stam * 0.25 * hp_ratio)
		
		total_strength += member_score
		
	return roundi(total_strength)

# ==========================================
# 輔助工具：模擬戰鬥腳本中的場地修正行為
# (如果你的這些函數寫在 BattleUI.gd，記得複製一份或改成全域調用)
# ==========================================

func _get_venue_perf_modifier(part: String, venue_mods: Dictionary) -> float:
	# 假設你的 venue_mods 結構為 { "perf_buff": { "Guitar": 0.2, "Bass": -0.1 } }
	return venue_mods.get("perf_bonus", {}).get(part, 0.0)

func _get_venue_throttle_multiplier(part: String, venue_mods: Dictionary) -> float:
	# 假設你的 venue_mods 結構為 { "throttle": { "Vocal": 0.5 } }，預設是不限流的 1.0
	var throttle = venue_mods.get("vocal_throttle", false)
	var throttle_multiplier = 0.65 if throttle else 1.0
	return throttle_multiplier

## 更新樂團的戰略目標與組織類型
func update_band_policy(band_id: String, new_goal: String, new_type: String) -> void:
	var band = find_band(band_id)
	if not band:
		printerr("Facade Error: Cannot update policy. Band not found: ", band_id)
		return
		
	# 直接動態覆寫字串屬性
	band.goal = new_goal
	band.type = new_type
	
	# 發布爽快的成就日誌
	game_log("🎯 樂團方針確立！新目標：[%s] | 組織定位：[%s]" % [new_goal, new_type], "magenta")

# ==========================================
# 在 GameEventFacade.gd 中新增以下內容
# ==========================================

## 核心功能：將當前 GameStateBang 的所有狀態與物件序列化並寫入 user://save.json
func save_game_session() -> void:
	game_log("💾 System: 正在儲存遊戲進度...", "yellow")
	
	# 1. 建立頂層的存檔字典，先塞入 10 項全域核心回合變數
	var save_data := {
		"turn": GameStateBang.turn,
		"current_band": GameStateBang.current_band,
		"attacker": GameStateBang.attacker,
		"defender": GameStateBang.defender,
		"current_venue": GameStateBang.current_venue,
		"turn_band": GameStateBang.turn_band,
		"is_running": GameStateBang.is_running,
		"plot_mode": GameStateBang.plot_mode,
		"current_selected_member_name": GameStateBang.current_selected_member_name,
		"player": GameStateBang.player,
		
		# 順便把自由成員招募市場的最新狀態也存下來
		"free_member_pool": GameStateBang.free_member_pool,
		
		# 預留的三大核心資料容器掛載點
		"bands": {},
		"worldMap": {},
		"eventPool": []
	}
	
	# 2. 序列化所有樂團與團員 (Bands & Members)
	for b_name in GameStateBang.data.bands:
		var band_obj = GameStateBang.data.bands[b_name]
		save_data["bands"][b_name] = _serialize_band(band_obj)
		
	# 3. 序列化所有大地圖場地與家具 (Venues & Furnitures)
	for v_name in GameStateBang.data.worldMap:
		var venue_obj = GameStateBang.data.worldMap[v_name]
		save_data["worldMap"][v_name] = _serialize_venue(venue_obj)
		
	# 4. 序列化隨機事件池 (Event Pool)
	for event_obj in GameStateBang.data.eventPool:
		# 假設你的 Event 物件內部有寫好的 to_dict() 或 serialize() 方法
		if event_obj.has_method("to_dict"):
			save_data["eventPool"].append(event_obj.to_dict())
			
	# 5. 實體寫入檔案系統 (user:// 安全防線)
	var save_path = "res://data/save.json"
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(save_data, "\t") # 使用 tab 縮排，讓產出的 json 美觀好 debug
		file.store_string(json_string)
		file.close()
		game_log("✨ System: 存檔成功！已寫入 user://save.json", "green")
	else:
		printerr("❌ Facade Error: 無法寫入存檔檔案！錯誤碼: ", FileAccess.get_open_error())
		game_log("❌ System: 存檔失敗，檔案系統寫入異常。", "red")

## 輔助工具：將 Band 物件及其底下的 Member 物件序列化為 Dictionary
func _serialize_band(band: Object) -> Dictionary:
	var serialized_members := []
	
	# 走訪並拆解樂團裡的每一位成員
	for m in band.members:
		var m_dict = {
			"name": m.name,
			"part": m.part,
			"perf": m.perf,
			"stam": m.stam,
			"hp": m.hp,
			"max_hp": m.max_hp,
			"xp": m.xp
		}
		serialized_members.append(m_dict)
		
	# 建立並回傳樂團的純文字字典
	return {
		"name": band.band_name,
		"money": band.money,
		"supply": band.supply,
		"goal": band.goal, # 包含你剛寫好的方針！
		"type": band.type, # 包含你剛寫好的方針！
		"relations": band.relations.duplicate(),
		"members": serialized_members
	}


## 輔助工具：將 Venue 場地物件序列化為 Dictionary
func _serialize_venue(venue: Object) -> Dictionary:
	# 處理擁有權：存檔時只需要記錄主人的「名字字串」即可，讀檔時再動態還原指標
	var owner_name = ""
	if venue.owner and "band_name" in venue.owner:
		owner_name = venue.owner.band_name
		
	return {
		"name": venue.name,
		"location": venue.city,
		"type": venue.type,
		"owner": owner_name,
		"installed_furniture": venue.get("installed_furniture").duplicate() # 存下海報牆、音響等家具狀態！
	}

## 驗證玩家當前是否能向目標場地發動進攻
func can_attack_venue(target_venue_name: String) -> bool:
	var player_band_id = GameStateBang.player
	var player_band = GameStateBang.data.bands[player_band_id]
	
	# 1. 安全防線：如果目標場地根本不存在，或者主人已經是玩家自己，不能打
	var target_venue_obj = GameStateBang.data.worldMap.get(target_venue_name)
	if not target_venue_obj: return false
	if target_venue_obj.owner == player_band: return false
	
	# 2. 獲取目標場地在矩陣中的 Index
	if not GameStateBang.venue_indices.has(target_venue_name):
		push_error("Matrix Error: Venue name not found in index registry: " + target_venue_name)
		return false
	var target_idx: int = GameStateBang.venue_indices[target_venue_name]
	
	# 3. 🎯 核心掃描：遍歷地圖上所有場地，找出「屬於玩家」且「與目標相鄰」的跳板
	for v_name in GameStateBang.data.worldMap:
		var my_venue = GameStateBang.data.worldMap[v_name]
		
		# 如果這個場地是玩家的，我們就拿它當潛在的「進攻發起點」
		if my_venue.owner == player_band:
			var my_idx: int = GameStateBang.venue_indices.get(v_name, -1)
			if my_idx == -1: continue
			
			# 🔍 查表：從鄰接矩陣看【我的場地索引】與【目標場地索引】有沒有接通
			if GameStateBang.adjacency_matrix[my_idx][target_idx] == 1:
				print("⚔️ [Strategy] 進攻線確立！可從 %s 進攻 %s" % [v_name, target_venue_name])
				return true # 只要找到任意一個場地有連線，立刻放行！
				
	# 遍歷完所有領地，發現沒有任何一塊地跟目標挨著
	print("❌ [Strategy] 無法進攻 %s：該場地與你目前的勢力範圍不相鄰！" % target_venue_name)
	return false
