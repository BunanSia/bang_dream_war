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

## 遍歷所有可能操作，計算最高分的行動（整合外交關係與戰力評估）
func _evaluate_best_action(band: Band) -> Dictionary:
	var best_choice: Dictionary = {}
	var highest_score: float = -1.0
	var band_name = band.band_name # 確保變數與 args 內容一致
	
	# ==========================================================
	# 策略 A：訓練團員 (Train Member) -> 保持不變
	# ==========================================================
	if facade.check_action_point("train_member"):
		for member in band.members:
			if member.hp > 30:
				var score = 40.0
				if personality == "TURTLE": score += 25.0
				
				if score > highest_score:
					highest_score = score
					best_choice = {"type": "train_member", "args": [band_name, member.name]}
					
	# ==========================================================
	# 策略 B：讓疲憊的團員休息 (Rest Member) -> 保持不變
	# ==========================================================
	if band.supply >= 10:
		for member in band.members:
			if member.hp < 40:
				var score = 80.0 + (100.0 - member.hp)
				if score > highest_score:
					highest_score = score
					best_choice = {"type": "rest_member", "args": [band_name, member.name]}

	# ==========================================================
	# 策略 C：購買 LiveHouse 家具擴張上限 -> 保持不變
	# ==========================================================
	if facade.check_action_point("buy_furniture_for_venue") and band.money >= 500:
		for venue_name in GameStateBang.data.worldMap:
			var venue = GameStateBang.data.worldMap[venue_name]
			if venue.owner == band:
				var score = 50.0
				if band.supply < 15: score += 40.0
				
				if score > highest_score:
					highest_score = score
					var mock_furniture = {"name": "高階音響系統", "cost": 500, "hp_recovery_bonus": 5, "supply_cap_bonus": 20, "description": "AI 升級"}
					best_choice = {"type": "buy_furniture_for_venue", "args": [band_name, venue_name, mock_furniture]}

	# ==========================================================
	# 策略 D：發動地盤入侵爭奪 (Start Invasion) -> 🔥 核心重構
	# ==========================================================
	if facade.check_action_point("start_invasion"):
		for venue_name in GameStateBang.data.worldMap:
			var venue = GameStateBang.data.worldMap[venue_name]
			
			# 1. 基本過濾：如果這個 LiveHouse 本來就是我的，或者它目前沒有任何人佔領，跳過
			if venue.owner == band or not venue.owner:
				continue
				
			var opponent_band = venue.owner
			var opponent_name = opponent_band.band_name
			
			# 2. 🟢 條件一：非死對頭（Rival）不發動入侵
			# 透過 Facade 獲取當前 AI 樂團與該 LiveHouse 佔領者樂團的外交關係
			var relationship = facade.execute_action(facade.get_band_relation, [band_name, opponent_name])
			if relationship != "Rival":
				continue # 如果是 Neutral、Ally，直接沒興趣，不開戰
				
			# 3. 🟢 條件二：戰力評估與權重修正
			# 使用剛剛寫好的演算法，算出「進攻方（我方）」與「防守方（對方）」在該場地的真實戰力
			var my_strength = facade.execute_action(facade.get_band_strength_for_venue, [band_name, venue_name])
			var op_strength = facade.execute_action(facade.get_band_strength_for_venue, [opponent_name, venue_name])
			
			var score = 30.0
			if personality == "AGGRESSIVE": score += 50.0 # 侵略型 AI 基礎戰意高
			
			# 對方的主人是玩家，激起 NPC 的宿敵挑戰欲，分數加成
			if opponent_name == GameStateBang.player:
				score += 20.0 
				
			# ⚔️ 關鍵戰力差距判定 (Discourage Logic)：
			if op_strength > my_strength:
				# 情況一：對方比我強！
				var strength_gap = op_strength - my_strength
				
				if personality == "TURTLE":
					# 防守型 AI 看到對方比較強，直接慫掉（大幅扣分，甚至變負值）
					score -= (strength_gap * 2.0)
				else:
					# 普通型或侵略型 AI，雖然被勸退（Discouraged），但如果差距不大還是可能硬碰硬
					score -= (strength_gap * 0.8)
			else:
				# 情況二：我方比對方強！欺軟怕硬，戰意飆升
				var strength_advantage = my_strength - op_strength
				score += (strength_advantage * 0.5)
				
			# 4. 安全防線：如果被勸退到分數低於 0，代表打贏機率太低，AI 索性放棄此行動
			if score <= 0.0:
				continue
				
			# 5. 結算最高分
			if score > highest_score:
				highest_score = score
				best_choice = {"type": "start_invasion", "args": [band_name, venue_name]}

	return best_choice

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
