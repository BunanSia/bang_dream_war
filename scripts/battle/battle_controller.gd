# BattleController.gd
extends Node
class_name BattleController

# 定義信號，讓 UI 知道何時該更新畫面
signal log_requested(msg: String, color: String)
signal groove_updated(energy: float, encore_cost: float, sonic_cost: float)
signal hp_updated()
signal turn_started(is_player_turn: bool)
signal attacker_selected(attacker: Object)
signal battle_ended(attacker_won: bool)
signal venue_ready()

enum TurnState { CHOOSE_ATTACKER, CHOOSE_DEFENDER }
var current_state = TurnState.CHOOSE_ATTACKER

var attacker_band: Band
var defender_band: Band
var target_venue: Venue

var acted_this_turn: Array = []
var selected_attacker = null

var venue_database: Dictionary = {}
var stratagem_db: Dictionary = {}
var counter_matrix: Dictionary = {}

var current_groove_energy: float = 0.0
const MAX_GROOVE_ENERGY: float = 100.0

func setup_battle(attacker: Band, defender: Band, venue: Venue) -> void:
	attacker_band = attacker
	defender_band = defender
	target_venue = venue
	
	stratagem_db = GameStateBang.stratagem_db
	counter_matrix = GameStateBang.counter_matrix
	venue_database = GameStateBang.venue_database
	
	if venue_database.has(venue.type):
		target_venue.load_from_dict(venue.type, venue_database[venue.type])
		
	# 2. 資料灌入完畢！立刻發送信號通知 UI 可以換背景了
	emit_signal("venue_ready", target_venue.background_path)
		
	emit_signal("log_requested", "LIVE BATTLE ENGAGED: %s VS %s" % [attacker.band_name, defender.band_name], "yellow")
	emit_signal("log_requested", "Location: %s" % venue.name, "white")

	gain_groove_energy(0) # 觸發初始 UI 更新
	_start_new_round()

# ==========================================
# 戰鬥規則與陣型邏輯 (純資料判斷，不依賴 UI)
# ==========================================
func _is_member_in_back_row(member: Object, band: Band) -> bool:
	var index = band.members.find(member)
	if index == -1: return false
	return (index % 2) == 1 # 基數為後排

func _has_front_row_defenders(band: Band) -> bool:
	for i in range(band.members.size()):
		if (i % 2) == 0 and band.members[i].hp > 0: # 偶數為前排
			return true
	return false

func is_target_legal(attacker, defender, target_band: Band) -> bool:
	if not _is_member_in_back_row(defender, target_band):
		return true # 前排永遠可被指定
		
	var long_range_parts = ["Vo/Gt", "Vo", "Gt", "Ba"]
	if attacker.part in long_range_parts:
		return true # 遠程可穿透打後排
		
	if _has_front_row_defenders(target_band):
		return false # 短手且前排有人，不可打後排
		
	return true # 前排死光，後排暴露

# ==========================================
# 傷害計算與回合控制
# ==========================================
func execute_combat_turn(attacker, defender) -> void:
	var venue_mods = target_venue.modifiers if target_venue else {}
	
	# 攻擊者加成計算
	var a_perf = attacker.get("perf")
	var matrix_mod = _get_matrix_modifier(attacker.part, defender.part)
	var env_perf_mod = _get_venue_perf_modifier(attacker.part, venue_mods)
	var throttle = _get_venue_throttle_multiplier(attacker.part, venue_mods)
	
	var final_attacker_perf = (a_perf * (1.0 + matrix_mod + env_perf_mod)) * throttle
	
	# 防禦者計算
	var d_stam = defender.get("stam")
	var env_stam_mod = venue_mods.get("stam_nerf", {}).get(defender.part, 0.0)
	var final_defender_stam = d_stam * (1.0 + env_stam_mod)
	
	# 傷害結算
	var dmg = maxi(8, (final_attacker_perf / 2) - (final_defender_stam / 4) + randi() % 15)
	defender.hp = maxi(0, defender.hp - dmg)
	
	var env_tag = "[環境加成] " if env_perf_mod > 0.0 else ""
	emit_signal("log_requested", "%s[進攻] %s 進行了極致演奏！造成 %s 體力下降 %d 點。" % [env_tag, attacker.name, defender.name, dmg], "cyan")
	
	acted_this_turn.append(attacker)
	if current_state == TurnState.CHOOSE_DEFENDER:
		gain_groove_energy(dmg * 0.4)
		
	# 反擊邏輯
	if defender.hp > 0:
		_process_counter_attack(defender, attacker, venue_mods)
	else:
		emit_signal("log_requested", ">> %s 已經精疲力竭，被迫離開舞台！ <<" % defender.name, "orange")
		
	emit_signal("hp_updated")
	_post_combat_check()

func _process_counter_attack(defender, attacker, venue_mods: Dictionary) -> void:
	var counter_mod = _get_matrix_modifier(defender.part, attacker.part)
	var counter_env = _get_venue_perf_modifier(defender.part, venue_mods)
	var counter_throttle = _get_venue_throttle_multiplier(defender.part, venue_mods)
	var decay_rate = venue_mods.get("stamina_decay_multiplier", 1.0)
	
	var base_score = (defender.get("stam") * (1.0 + counter_mod + counter_env)) * counter_throttle
	var counter_dmg = int(maxi(8, (base_score / 2) - (attacker.get("stam") / 4) + randi() % 15) * decay_rate)
	
	attacker.hp = maxi(0, attacker.hp - counter_dmg)
	emit_signal("log_requested", "[反擊] %s 不甘示弱回擊！造成 %s 體力下降 %d 點。" % [defender.name, attacker.name, counter_dmg], "red")

# ==========================================
# 流程推進
# ==========================================
func _post_combat_check():
	if _check_battle_over(): return
	
	if _has_available_attackers():
		selected_attacker = null
		_select_next_attacker()
	else:
		emit_signal("log_requested", ">> 全體團員表演結束，換幕處理中... <<", "gray")
		_start_new_round()

func _start_new_round() -> void:
	# 1. 核心安全鎖：開新回合前，先檢查遊戲是不是已經結束了！
	if _check_battle_over():
		return # 如果結束了，直接切斷後續所有的流轉
		
	# 2. 切換攻守方狀態
	current_state = TurnState.CHOOSE_DEFENDER if current_state == TurnState.CHOOSE_ATTACKER else TurnState.CHOOSE_ATTACKER
	acted_this_turn.clear()
	selected_attacker = null
	
	var is_player = _check_is_player_round()
	emit_signal("turn_started", is_player)
	
	# 3. 推進流轉
	_select_next_attacker()


func _select_next_attacker() -> void:
	selected_attacker = null
	
	# 使用 while 迴圈來替代遞迴。如果當前大回合的人都動過了，就直接在迴圈內重置並跨入下個大回合
	# 迴圈會一直跑到「成功找到一個活著且還沒動過的角色」為止
	while selected_attacker == null:
		# 如果在找人的中途發現整場戰鬥已經打完了，立刻中斷
		if _check_battle_over():
			return
			
		var current_band = attacker_band if current_state == TurnState.CHOOSE_ATTACKER else defender_band
		
		# 嘗試在當前樂團中找人
		for member in current_band.members:
			if member.hp > 0 and not (member in acted_this_turn):
				selected_attacker = member
				break
				
		# 如果當前大回合的人全動過了，我們就在這裡「就地重置」並翻轉狀態，不要用函數呼叫！
		if selected_attacker == null:
			current_state = TurnState.CHOOSE_DEFENDER if current_state == TurnState.CHOOSE_ATTACKER else TurnState.CHOOSE_ATTACKER
			acted_this_turn.clear()
			
			var is_player = _check_is_player_round()
			emit_signal("turn_started", is_player)
			
			# 註：這裡沒有 return，whlie 迴圈會帶著更新後的狀態直接進入下一次迭代，完美避開遞迴！

	# 順利找到行動者，安全跳出迴圈
	emit_signal("attacker_selected", selected_attacker)
	
	if not _check_is_player_round():
		_process_ai_turn()

func _process_ai_turn() -> void:
	var target_band = defender_band if current_state == TurnState.CHOOSE_ATTACKER else attacker_band
	var possible_targets = target_band.members.filter(func(m): return m.hp > 0)
	
	if possible_targets.size() > 0:
		var chosen = possible_targets.pick_random()
		emit_signal("log_requested", "電腦 %s 鎖定了 %s！" % [selected_attacker.name, chosen.name], "orange")
		
		# 加入微小延遲讓玩家看清 AI 的決策 (因為 Controller 繼承 Node，我們可以使用 timer)
		await get_tree().create_timer(0.2).timeout 
		execute_combat_turn(selected_attacker, chosen)

# ==========================================
# 戰術技能 (Stratagems)
# ==========================================
func gain_groove_energy(amount: float) -> void:
	current_groove_energy = clamp(current_groove_energy + amount, 0.0, MAX_GROOVE_ENERGY)
	var encore_cost = stratagem_db.get("encore", {}).get("cost", 50.0)
	var sonic_cost = stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	emit_signal("groove_updated", current_groove_energy, encore_cost, sonic_cost)

func use_encore(target: Object) -> bool:
	var cost = stratagem_db.get("encore", {}).get("cost", 50.0)
	if current_groove_energy >= cost and target:
		current_groove_energy -= cost
		target.hp = int(target.max_hp * 0.30)
		gain_groove_energy(0) # 更新 UI
		emit_signal("hp_updated")
		return true
	return false

## 發動音爆 (全體 AOE 傷害)
func use_sonic_boom() -> bool:
	var cost = stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	if current_groove_energy < cost: 
		return false
	
	current_groove_energy -= cost
	gain_groove_energy(0) # 觸發 UI 更新
	
	emit_signal("log_requested", "💥 [戰術狂轟] 樂團發動全屏音爆！狂暴的聲波衝擊全場防守者！", "red")
	
	# 判斷現在誰是挨打的一方 (如果是玩家回合，挨打的就是 defender_band)
	var target_band = defender_band if current_state == TurnState.CHOOSE_ATTACKER else attacker_band
	
	for enemy in target_band.members:
		if enemy.hp > 0:
			var base_nerf = randi() % 15 + 10
			enemy.hp = maxi(0, enemy.hp - base_nerf)
			emit_signal("log_requested", ">> %s 受音爆震撼，體力滑落 %d 點！" % [enemy.name, base_nerf], "red")
			
	emit_signal("hp_updated")
	
	# 檢查這發音爆是不是直接把對手全滅了
	_post_combat_check()
	return true

# Helper function to look up dynamic performance modifiers between two parts
func _get_matrix_modifier(attacker_part: String, defender_part: String) -> float:
	if counter_matrix.has(attacker_part):
		if counter_matrix[attacker_part].has(defender_part):
			return counter_matrix[attacker_part][defender_part]
	return 0.0 # Return neutral if relationship doesn't exist

# Helper to look up acoustic performance bonuses for specific parts in the current venue
func _get_venue_perf_modifier(part: String, venue_mods: Dictionary) -> float:
	var perf_bonus_dict = venue_mods.get("perf_bonus", {})
	if perf_bonus_dict.has(part):
		return perf_bonus_dict[part]
	return 0.0

# Helper to process venue structural constraints (e.g., Symphony Hall dampening Vocals)
func _get_venue_throttle_multiplier(part: String, venue_mods: Dictionary) -> float:
	if venue_mods.get("vocal_throttle", false) and part == "Vo/Gt":
		emit_signal("log_requested", "[環境干擾] 傳統古典音樂廳的音響設計壓制了搖滾主唱的爆發力！", "purple")
		return 0.65 # Throttles raw performance output to 65%
	return 1.0
# --- YOUR REFACTORED COMBAT FUNCTION ---


func _check_battle_over() -> bool:
	var attackers_alive = attacker_band.members.any(func(m): return m.hp > 0)
	var defenders_alive = defender_band.members.any(func(m): return m.hp > 0)
	
	if not defenders_alive:
		_finalize_battle(true)
		return true
	elif not attackers_alive:
		_finalize_battle(false)
		return true
		
	return false

func _finalize_battle(attacker_won: bool) -> void:
	emit_signal("log_requested", "戰鬥結束！")
	emit_signal("log_requested", "\n==================================================", "yellow")
	
	if attacker_won:
		emit_signal("log_requested", " RESULT: 勝利！ %s 成功攻佔了舞台！" % attacker_band.band_name, "green")
		# Swap operational territory vectors
		defender_band.remove_venue(target_venue) if defender_band.has_method("remove_venue") else null
		attacker_band.add_venue(target_venue) if attacker_band.has_method("add_venue") else null
		target_venue.owner = attacker_band
	else:
		emit_signal("log_requested", " RESULT: 戰敗... %s 堅守住了 Livehouse 陣地！" % defender_band.band_name, "red")
		
	emit_signal("log_requested", "==================================================\n", "yellow")
	emit_signal("battle_ended", attacker_won)

## 判斷現在是否輪到玩家操作
func _check_is_player_round() -> bool:
	# 1. 根據當前的回合狀態，判斷現在是哪一個樂團在行動
	var active_band: Band = attacker_band if current_state == TurnState.CHOOSE_ATTACKER else defender_band
	
	# 2. 檢查該行動樂團的名字，是否等同於全域變數中的玩家樂團
	return active_band.band_name == GameStateBang.player

func _has_available_attackers() -> bool:
	for member in attacker_band.members:
		if member.hp > 0 and not acted_this_turn.has(member):
			return true
	return false

func force_retreat() -> void:
	emit_signal("log_requested", ">> 樂團決定撤退！放棄了這次的演出競爭... <<", "orange")
	
	# 判斷玩家是攻擊方還是防守方。主動撤退代表「對方」贏了
	var player_is_attacker = (attacker_band.band_name == GameStateBang.player)
	var attacker_won = not player_is_attacker 
	
	_finalize_battle(attacker_won)

## 輔助函數：重置血量底線
func _reset_band_hp(band: Band) -> void:
	for m in band.members:
		if m.hp < 0: 
			m.hp = 0
