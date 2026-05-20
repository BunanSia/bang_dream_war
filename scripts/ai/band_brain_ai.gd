class_name BandBrainAI
extends RefCounted

var facade: GameEventFacade
var band_name: String
var personality: String # "AGGRESSIVE" (侵略型), "TURTLE" (防守訓練型), "BALANCED" (平衡型)
signal ai_process_complete

func _init(_facade: GameEventFacade, _band_name: String, _personality: String = "BALANCED") -> void:
	facade = _facade
	band_name = _band_name
	personality = _personality

func process_turn() -> void:
	var band = facade.find_band(band_name)
	if not band: return
	
	facade.game_log("🤖 敵方樂團 [ %s ] 開始進行戰略思考..." % band_name, "magenta")
	
	while _get_current_ap(band) > 0:
		var best_action = _evaluate_best_action(band)
		
		if best_action.is_empty():
			facade.game_log("🤖 [ %s ] 本輪已無最佳策略，宣告保留或結束行動。" % band_name, "gray")
			break
			
		# Check if the chosen action is a battle
		_execute_ai_choice(best_action)
		
		if best_action["type"] == "start_invasion":
			# CRITICAL: The AI triggered a battle. 
			# We immediately kill this function. Do NOT emit ai_process_complete!
			return 
			
	# Only emit this if the AI spent all AP peacefully (training, resting, etc.)
	ai_process_complete.emit()

func _get_current_ap(band: Band) -> int:
	return band.get("current_action_points") if "current_action_points" in band else 0

# ==============================================================================
# --- 效用評估矩陣 (Utility Evaluation Matrix) ---
# ==============================================================================

## 遍歷所有可能操作，計算最高分的行動
func _evaluate_best_action(band: Band) -> Dictionary:
	var best_choice: Dictionary = {}
	var highest_score: float = -1.0
	
	# 策略 A：訓練團員 (Train Member)
	if facade.check_action_point("train_member"):
		for member in band.members:
			if member.hp > 30: # 體力太低先不訓練
				var score = 40.0
				if personality == "TURTLE": score += 25.0 # 防守型更愛訓練
				
				if score > highest_score:
					highest_score = score
					best_choice = {"type": "train_member", "args": [band_name, member.name]}
					
	# 策略 B：讓疲憊的團員休息 (Rest Member)
	# 備註：rest_member 在 Facade 中目前沒寫進 AP 表，這裡我們預估它不耗 AP 但耗 Supply
	if band.supply >= 10:
		for member in band.members:
			if member.hp < 40: # 團員快過勞了
				var score = 80.0 + (100.0 - member.hp) # 越累分數越高（剛需優先）
				if score > highest_score:
					highest_score = score
					best_choice = {"type": "rest_member", "args": [band_name, member.name]}

	# 策略 C：購買 LiveHouse 家具擴張上限 (Buy Furniture)
	if facade.check_action_point("buy_furniture_for_venue") and band.money >= 500:
		# 尋找 AI 自己控制的 LiveHouse
		for venue_name in GameStateBang.data.worldMap:
			var venue = GameStateBang.data.worldMap[venue_name]
			if venue.owner == band:
				var score = 50.0
				if band.supply < 15: score += 40.0 # 補給快不夠了，強烈渴望升級家具
				
				if score > highest_score:
					highest_score = score
					# 模擬一份基礎家具設定檔
					var mock_furniture = {"name": "高階音響系統", "cost": 500, "hp_recovery_bonus": 5, "supply_cap_bonus": 20, "description": "AI 升級"}
					best_choice = {"type": "buy_furniture_for_venue", "args": [band_name, venue_name, mock_furniture]}

	# 策略 D：發動地盤入侵爭奪 (Start Invasion)
	if facade.check_action_point("start_invasion"):
		for venue_name in GameStateBang.data.worldMap:
			var venue = GameStateBang.data.worldMap[venue_name]
			# 只要這個 LiveHouse 不是我的，就是潛在進攻目標
			if venue.owner != band:
				var score = 30.0
				if personality == "AGGRESSIVE": score += 50.0 # 侵略型 AI 渴望點滿！
				
				# 如果對方的主人是死對頭或目前玩家，分數再加成
				if venue.owner and venue.owner.band_name == GameStateBang.player:
					score += 20.0 
					
				if score > highest_score:
					highest_score = score
					best_choice = {"type": "start_invasion", "args": [band_name, venue_name]}

	return best_choice

# inside band_brain_ai.gd (繼續延伸)

## 根據評估結果，把指令轉發給全球 Facade 執行管道
func _execute_ai_choice(choice: Dictionary) -> void:
	var type = choice["type"]
	var args = choice["args"]
	
	match type:
		"train_member":
			facade.game_log("🤖 [AI 行動] %s 決定對團員 %s 進行特訓！" % [band_name, args[1]], "magenta")
			facade.execute_action(facade.train_member, args)
			
		"rest_member":
			facade.game_log("🤖 [AI 行動] %s 安排疲憊的團員 %s 進行後台歇息。" % [band_name, args[1]], "cyan")
			# 由於 rest_member 沒在 AP 表內，若不需要扣 AP 可直接呼叫
			facade.execute_action(facade.rest_member, [args[0], args[1]])
			
		"buy_furniture_for_venue":
			facade.game_log("🤖 [AI 行動] %s 豪擲千金為 LiveHouse %s 升級了硬體設備設施！" % [band_name, args[1]], "green")
			facade.execute_action(facade.buy_furniture_for_venue, args)
			
		"start_invasion":
			facade.game_log("🔥 [AI 宣戰] %s 揮軍大舉突擊由 %s 佔領的舞台: %s！" % [band_name, GameStateBang.data.worldMap[args[1]].owner.band_name, args[1]], "red")
			# 鎖定大戰略狀態，並正式切換進入你做好的 Task 1~3 Live 戰鬥場景！
			facade.execute_action(facade.start_invasion, [band_name, args[1]])
