class_name GameEventFacade
extends Node

signal battle_resolved

var engine: Node # Reference back to core GameEngine
var ui: MainGameUI
var current_battle = preload("res://scenes/live_battle_scene.tscn")
var current_battle_instance

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
	"start_invasion": 3
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
		
	game_log("❌ 行動點數不足！需要 %d 點 AP，目前僅剩 %d 點。" % [cost, GameStateBang.data.bands[GameStateBang.player].current_action_points], "red")
	return false

## 扣除玩家的行動點數
func _deduct_action_point(action_name: String) -> void:
	if AP_COST_TABLE.has(action_name):
		var cost = AP_COST_TABLE[action_name]
		var band = GameStateBang.data.bands[GameStateBang.get_turn_band()]
		band.current_action_points = maxi(0, band.current_action_points - cost)
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

func add_band_member(band_name: String, member_name: String) -> void:
	var band = find_band(band_name)
	if band:
		band.add_member(member_name, "Gt", 40, 25)
		game_log("System: Added %s from %s" % [member_name, band_name], "yellow")

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

func set_band_relations(band_a: String, band_b: String, relationship: String) -> void:
	var band1 = find_band(band_a)
	var band2 = find_band(band_b)
	
	if band1 and band2:
		band1.update_relation(band_b, relationship)
		band2.update_relation(band_a, relationship)
		game_log(">> %s and %s are now %s!" % [band_a, band_b, relationship], "cyan")
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

func upgrade_member(band_name: String, member_name: String) -> void:
	var band = execute_action(find_band, [GameStateBang.player])
	var member = get_member(band_name, member_name)
	var upgrades_cfg = ConfigManager.load_config_by_path("res://config/upgrades.json").get("promotions", {})
	var tier_data = upgrades_cfg[member.role]
	
	# Deduct costs and adjust member identity fields
	band.money -= tier_data["cost"]
	member.role = tier_data["next_tier"]
	member.base_performance += tier_data["perf_boost"]

func rest_member(band_name: String, member_name: String) -> void:
	var band = execute_action(find_band, [GameStateBang.player])
	
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

func start_invasion(player, target: String) -> void:
	game_log("--- Select a target to invade ---", "red")
	GameStateBang.attacker = player
	GameStateBang.defender = GameStateBang.data.worldMap[target].owner.band_name
	GameStateBang.current_venue = target
	engine.remove_child(ui.get_parent().get_parent())
		
	# 2. 建立戰鬥場景並加入
	current_battle_instance = current_battle.instantiate()
	engine.add_child(current_battle_instance)
	var attacker_band = GameStateBang.data.bands[GameStateBang.attacker]
	var defender_band = GameStateBang.data.bands[GameStateBang.defender]
	var target_venue = GameStateBang.data.worldMap[GameStateBang.current_venue]
	current_battle_instance.start_interactive_battle(
		attacker_band, defender_band, target_venue)

func stop_invation():
# 1. 清除戰鬥畫面
	if current_battle_instance:
		engine.remove_child(current_battle_instance)
		current_battle_instance.queue_free()
		current_battle_instance = null
	# 2. 把當初活得好好的大地圖原封不動掛載回來！
	engine.add_child(ui.get_parent().get_parent())
	battle_resolved.emit()
