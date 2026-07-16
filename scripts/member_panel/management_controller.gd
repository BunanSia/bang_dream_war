## ManagementController.gd
## 負責處理團員管理系統的核心資料與邏輯運算
class_name ManagementController
extends Node

# 宣告給 UI 聽的狀態更新信號
signal data_refreshed
signal error_occurred(message: String)

# 記住當前選中的裝備資料
var selected_equipment_data: Dictionary = {}
var current_band_id: String
var current_band: Object
var selected_member: Object

func _init(band_id: String) -> void:
	current_band_id = band_id
	current_band = GameStateBang.data.bands[band_id]
# 假設你在 init 時會傳入當前點擊的 band_id

## 判斷當前管理的樂團是不是玩家控制的樂團
func is_player_band() -> bool:
	return current_band_id == GameStateBang.player

## 設定當前選中的團員
func select_member_by_name(name: String) -> void:
	selected_member = null
	for m in current_band.members:
		if m.name == name:
			selected_member = m
			break

# ==========================================
# 邏輯核心：計算與驗證 (Getters & Validators)
# ==========================================

func has_selected_member() -> bool:
	return selected_member != null

## 取得休息分頁所需的狀態資料
func get_rest_data() -> Dictionary:
	if not selected_member: return {}
	
	var max_supply = current_band.get_total_max_supply(GameStateBang.data.worldMap)
	var is_healed = selected_member.hp >= selected_member.get_total_max_hp()
	var can_rest = (not is_healed) and (current_band.supply >= 10)
	
	return {
		"current_supply": current_band.supply,
		"max_supply": max_supply,
		"member_hp": selected_member.hp,
		"member_max_hp": selected_member.get_total_max_hp(),
		"can_rest": can_rest
	}

## 📊 取得升級分頁所需的狀態資料（支援多分支路線）
func get_upgrade_data() -> Dictionary:
	if not selected_member: return { "max_tier_reached": true, "branches": [] }
	
	var branches = Global.event_facade.execute_action(Global.event_facade._get_promotion_branches, [selected_member.part])
	if branches.is_empty():
		return { "max_tier_reached": true, "branches": [] }
		
	var member_lvl = int(selected_member.get("level"))
	var processed_branches = []
	
	# 遍歷所有分支，為 UI 計算各別的解鎖狀態
	for branch in branches:
		var req_lvl = int(branch.get("level_required", 1))
		var gold_cost = int(branch.get("cost", 0))
		
		processed_branches.append({
			"next_title": branch.get("next_tier", "UNKNOWN"),
			"req_level": req_lvl,
			"cost": gold_cost,
			"perf_boost": int(branch.get("perf_boost", 0)),
			"can_upgrade": (member_lvl >= req_lvl) and (current_band.money >= gold_cost)
		})
		
	return {
		"max_tier_reached": false,
		"current_level": member_lvl,
		"current_money": current_band.money,
		"branches": processed_branches # 💡 丟出所有分支資料供 UI 生成多個按鈕
	}

# ==========================================
# 邏輯核心：狀態修改行為 (Mutators)
# ==========================================

func rest_current_member() -> void:
	if not selected_member: return
	Global.event_facade.execute_action(Global.event_facade.rest_member, [GameStateBang.player, selected_member.name])
	data_refreshed.emit()

func upgrade_current_member() -> void:
	if not selected_member: return
	Global.event_facade.execute_action(Global.event_facade.upgrade_member, [GameStateBang.player, selected_member.name])
	Global.event_facade.execute_action(Global.event_facade.ui.game_log, ["⚡ EVOLUTION: %s has evolved!", "purple"])
	data_refreshed.emit()

func train_current_member() -> void:
	if not selected_member: return
	Global.event_facade.execute_action(Global.event_facade.train_member, [GameStateBang.player, selected_member.name])
	data_refreshed.emit()

func layoff_current_member() -> void:
	if not selected_member: return
	Global.event_facade.execute_action(Global.event_facade.remove_band_member, [GameStateBang.player, selected_member.name])
	selected_member = null
	data_refreshed.emit()

func get_equipment_data() -> Array:
	if not selected_member: return []
	var catalog = ConfigManager.load_shop_catalog()
	var gear_list = catalog.get("shop_items", {}).get("equipment", [])
	return gear_list

# ==========================================
# 在 ManagementController.gd 中新增以下變數與方法
# ==========================================

## 設定當前選中的裝備
func select_equipment(item_data: Dictionary) -> void:
	selected_equipment_data = item_data

## 檢查是否可以購買 (條件：有選人、有選裝備、錢夠)
func can_buy_equipment() -> bool:
	if not selected_member or selected_equipment_data.is_empty():
		return false
		
	var cost = selected_equipment_data.get("cost", 999999) # 預設天價防呆
	return current_band.money >= cost

## 執行購買裝備
func buy_equipment_for_member() -> void:
	if not can_buy_equipment(): 
		return
		
	var item_name = selected_equipment_data.get("name")
	
	# 這裡呼叫你的 Global.event_facade 來處理實際的扣款與裝備賦予
	# (請依照你實際 Facade 裡面的參數順序微調)
	Global.event_facade.execute_action(
		Global.event_facade.buy_member_equipment, 
		[GameStateBang.player, selected_member.name, selected_equipment_data]
	)
	
	# 發送購買成功的日誌
	Global.event_facade.execute_action(
		Global.event_facade.ui.game_log, 
		["🛒 購買成功: 幫 %s 裝備了 %s!" % [selected_member.name, item_name], "green"]
	)
	
	# 買完後清空當前選取，並通知 UI 刷新 (這樣錢的顯示才會立刻變少)
	selected_equipment_data = {}
	data_refreshed.emit()
