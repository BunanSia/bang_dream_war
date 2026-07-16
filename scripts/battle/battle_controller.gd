# BattleController.gd
extends Node
class_name BattleController

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

# 🆕 真正上場決戰的精英名單（由戰前 UI 選出傳入）
var attacker_engaged_members: Array = []
var defender_engaged_members: Array = []

var acted_this_turn: Array = []
var selected_attacker = null

var current_groove_energy: float = 0.0
const MAX_GROOVE_ENERGY: float = 100.0

## 🆕 戰前初始化：必須傳入雙方真正選好的出戰成員名冊 (Array of Members)
func setup_battle(attacker: Band, defender: Band, venue: Venue, attacker_selected_members: Array, defender_selected_members: Array) -> void:
	attacker_band = attacker
	defender_band = defender
	target_venue = venue
	
	# 灌入真正上場的團員（解決了舞台站不下的問題！）
	attacker_engaged_members = attacker_selected_members
	defender_engaged_members = defender_selected_members

	if GameStateBang.venue_database.has(venue.type):
		target_venue.load_from_dict(venue.type, GameStateBang.venue_database[venue.type])
		
	emit_signal("venue_ready", target_venue.background_path)
	emit_signal("log_requested", "🔥 LIVE BATTLE ENGAGED: %s VS %s" % [attacker.band_name, defender.band_name], "yellow")
	emit_signal("log_requested", "📍 演出舞台: %s (%s)" % [venue.name, venue.type], "white")

	gain_groove_energy(0)
	_start_new_round()

# ==========================================
# 陣型防禦邏輯（僅針對場上的人計算）
# ==========================================
func _is_member_in_back_row(member: Object, engaged_members: Array) -> bool:
	var index = engaged_members.find(member)
	if index == -1: return false
	return (index % 2) == 1 # 奇數索引為後排

func _has_front_row_defenders(engaged_members: Array) -> bool:
	for i in range(engaged_members.size()):
		if (i % 2) == 0 and engaged_members[i].hp > 0:
			return true
	return false

func is_target_legal(attacker, defender) -> bool:
	var enemy_engaged = defender_engaged_members if current_state == TurnState.CHOOSE_ATTACKER else attacker_engaged_members
	
	if not _is_member_in_back_row(defender, enemy_engaged):
		return true # 前排永遠可打
		
	var long_range_parts = ["Vo/Gt", "Vo", "Gt", "Ba"]
	if attacker.part in long_range_parts:
		return true # 遠程樂器穿透
		
	if _has_front_row_defenders(enemy_engaged):
		return false # 被前排擋住
		
	return true

# ==========================================
# 核心大腦瘦身：傷害計算
# ==========================================
func _post_combat_check():
	# 1. 如果有人全滅了，這個函數會回傳 true，並在內部呼叫 _finalize_battle() 結束一切
	if _check_battle_over(): return
	
	# 2. 如果比賽還沒結束，再看「當前大回合（例如：玩家進攻回合）」還有沒有「沒行動過的人」
	if _has_available_attackers():
		selected_attacker = null
		_select_next_attacker() # 還有活著且沒動過的人，繼續推給下一個人動
	else:
		# 3. 🔥 重點在這裡！如果目前這個半場（攻方或守方）的所有人都動過了
		emit_signal("log_requested", ">> 全體團員表演結束，換幕處理中... <<", "gray")
		_start_new_round() # 唰一聲，翻轉攻守狀態，跨入下一個新大回合！

#  精準的完全體實作
func _has_available_attackers() -> bool:
	# 1. 動態判定當前到底是哪一個「舞台名單」正在進行大回合演奏
	var current_engaged_list = attacker_engaged_members if current_state == TurnState.CHOOSE_ATTACKER else defender_engaged_members
	
	# 2. 只盤點真正站在台上的精英
	for member in current_engaged_list:
		if member.hp > 0 and not acted_this_turn.has(member):
			return true # 只要台上還有一隻活著的貓還沒動，就繼續維持當前大回合
			
	return false # 台上大家都動過了，安全放行，準備換幕！

func _start_new_round() -> void:
	# 🛡️ 安全鎖：跨入新回合前，再次確保比賽沒結束
	if _check_battle_over(): return 
		
	# 1. 翻轉狀態：原本是 CHOOSE_ATTACKER 演奏，現在換成 CHOOSE_DEFENDER 演奏
	current_state = TurnState.CHOOSE_DEFENDER if current_state == TurnState.CHOOSE_ATTACKER else TurnState.CHOOSE_ATTACKER
	
	# 2. 乾淨清空：把「這回合動過的人」名單清空，讓新登場的樂團全員恢復行動權！
	acted_this_turn.clear()
	selected_attacker = null
	
	# 3. 通知 UI：告訴前端現在換誰的主場操作了
	var is_player = _check_is_player_round()
	emit_signal("turn_started", is_player)
	
	# 4. 🔥 啟動引擎：進入 while 迴圈開始在新樂團的名單裡挑出第一個可以動的人
	_select_next_attacker()

func execute_combat_turn(attacker, defender) -> void:
	# 🎯 複雜的「樂團類型/樂器/環境」交織乘數，全部交由 RuleBook 統一計算！
	var attack_multiplier = RuleBook.get_final_combat_modifier(attacker, defender, attacker_band, defender_band, target_venue, true)
	var final_attacker_perf = attacker.perf * attack_multiplier
	
	var defend_multiplier = RuleBook.get_final_combat_modifier(defender, attacker, defender_band, attacker_band, target_venue, false)
	var final_defender_stam = defender.stam * defend_multiplier
	
	# 傷害結算
	var dmg = maxi(8, (final_attacker_perf / 2) - (final_defender_stam / 4) + randi() % 15)
	defender.hp = maxi(0, defender.hp - dmg)
	
	emit_signal("log_requested", "🎸 [%s] %s 奏響強音！對 %s 造成 %d 點體力震撼！" % [attacker.part, attacker.name, defender.name, dmg], "cyan")
	
	acted_this_turn.append(attacker)
	if current_state == TurnState.CHOOSE_DEFENDER:
		gain_groove_energy(dmg * 0.4)
		
	# 反擊
	if defender.hp > 0:
		var counter_mult = RuleBook.get_final_combat_modifier(defender, attacker, defender_band, attacker_band, target_venue, true)
		var counter_dmg = maxi(8, ((defender.stam * counter_mult) / 2) - (attacker.stam / 4) + randi() % 15)
		attacker.hp = maxi(0, attacker.hp - counter_dmg)
		emit_signal("log_requested", "⚡ [反擊] %s 情感回擊！造成 %s 體力滑落 %d 點。" % [defender.name, attacker.name, counter_dmg], "red")
	else:
		emit_signal("log_requested", "💀 >> %s 精疲力竭，黯然退場！ <<" % defender.name, "orange")
		
	emit_signal("hp_updated")
	_post_combat_check()

# ==========================================
# 流程與 AI 控制
# ==========================================
func _select_next_attacker() -> void:
	selected_attacker = null
	
	while selected_attacker == null:
		if _check_battle_over(): return
			
		var current_list = attacker_engaged_members if current_state == TurnState.CHOOSE_ATTACKER else defender_engaged_members
		
		for member in current_list:
			if member.hp > 0 and not (member in acted_this_turn):
				selected_attacker = member
				break
				
		if selected_attacker == null:
			current_state = TurnState.CHOOSE_DEFENDER if current_state == TurnState.CHOOSE_ATTACKER else TurnState.CHOOSE_ATTACKER
			acted_this_turn.clear()
			emit_signal("turn_started", _check_is_player_round())

	emit_signal("attacker_selected", selected_attacker)
	if not _check_is_player_round(): _process_ai_turn()

func _process_ai_turn() -> void:
	var target_list = defender_engaged_members if current_state == TurnState.CHOOSE_ATTACKER else attacker_engaged_members
	var possible_targets = target_list.filter(func(m): return m.hp > 0 and is_target_legal(selected_attacker, m))
	
	if possible_targets.is_empty(): # 防呆：萬一沒合法目標，強行抓一個活著的
		possible_targets = target_list.filter(func(m): return m.hp > 0)
		
	if not possible_targets.is_empty():
		var chosen = possible_targets.pick_random()
		emit_signal("log_requested", "🤖 電腦選中對手，正蓄勢待發...", "orange")
		await get_tree().create_timer(0.4).timeout 
		execute_combat_turn(selected_attacker, chosen)

func _check_battle_over() -> bool:
	var attackers_alive = attacker_engaged_members.any(func(m): return m.hp > 0)
	var defenders_alive = defender_engaged_members.any(func(m): return m.hp > 0)
	
	if not defenders_alive:
		_finalize_battle(true)
		return true
	elif not attackers_alive:
		_finalize_battle(false)
		return true
	return false

# ==========================================
# 🎯 戰後結算與數據升級更新 (Settlement)
# ==========================================
func _finalize_battle(attacker_won: bool) -> void:
	emit_signal("log_requested", "\n==================================================", "yellow")
	
	if attacker_won:
		emit_signal("log_requested", " RESULT: 勝利！ %s 成功征服了舞台！" % attacker_band.band_name, "green")
		# 1. 變更地圖產權
		target_venue.owner = attacker_band

		# 2. 🔥 場地狀態更新：被攻佔後的 Livehouse 進入狂熱狀態（可供未來擴充事件）
		target_venue.set_meta("last_captured_turn", 1) # 標記場地更新狀態
	else:
		emit_signal("log_requested", " RESULT: 戰敗... %s 捍衛住了陣地！" % defender_band.band_name, "red")
		
	emit_signal("log_requested", "==================================================\n", "yellow")
	emit_signal("battle_ended", attacker_won)

func _check_is_player_round() -> bool:
	var active_band = attacker_band if current_state == TurnState.CHOOSE_ATTACKER else defender_band
	return active_band.band_name == GameStateBang.player

# ==========================================
# 🎯 戰術技能 (Stratagems) - 補全實作
# ==========================================

## 增加或減少 Groove 熱度能量，並通知 UI 更新按鈕狀態
func gain_groove_energy(amount: float) -> void:
	current_groove_energy = clamp(current_groove_energy + amount, 0.0, MAX_GROOVE_ENERGY)
	
	# 從全域戰術資料庫撈取消耗代價 (安全防呆，有預設值)
	var encore_cost = GameStateBang.stratagem_db.get("encore", {}).get("cost", 50.0)
	var sonic_cost = GameStateBang.stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	
	# 發送訊號更新 UI（例如：當能量足夠時，閃爍戰術按鈕）
	emit_signal("groove_updated", current_groove_energy, encore_cost, sonic_cost)


## 發動安可 (Encore)：指定一名場上精疲力竭或殘血的團員，強行恢復 30% 最大體力並重回舞台
## @return: 如果施放成功回傳 true，能量不足或目標非法回傳 false
func use_encore(target: Object) -> bool:
	var cost = GameStateBang.stratagem_db.get("encore", {}).get("cost", 50.0)
	
	# 1. 檢查能量底線
	if current_groove_energy < cost:
		emit_signal("log_requested", "❌ 能量不足！無法發動 [Encore]。", "red")
		return false
		
	# 2. 核心防線：確保目標是目前正在場上戰鬥的隊員 (不論攻守方)
	var all_engaged = attacker_engaged_members + defender_engaged_members
	if not target or not (target in all_engaged):
		emit_signal("log_requested", "❌ 施放失敗：無效的目標。", "red")
		return false
		
	# 3. 扣除能量並執行治療
	current_groove_energy -= cost
	
	# 假設成員最大血量預設為 100，有 max_hp 屬性則用屬性
	var max_hp = target.get("max_hp") if target.has("max_hp") else 100
	target.hp = int(max_hp * 0.30)
	
	emit_signal("log_requested", "✨ [戰術安可] Encore!! %s 再次獲得聚光燈，體力回復至 30%%！" % target.name, "green")
	
	# 4. 戰法施放完畢，刷新數值與 UI 狀態
	gain_groove_energy(0) 
	emit_signal("hp_updated")
	return true


## 發動音爆 (Sonic Boom)：全體 AOE 震撼彈，對敵方場上所有「參戰中」的活著團員造成爆發傷害
## @return: 如果施放成功回傳 true
func use_sonic_boom() -> bool:
	var cost = GameStateBang.stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	
	if current_groove_energy < cost: 
		emit_signal("log_requested", "❌ 氣勢不足！無法發動 [全屏音爆]。", "red")
		return false
	
	current_groove_energy -= cost
	gain_groove_energy(0) # 觸發 UI 更新扣除後的能量
	
	emit_signal("log_requested", "💥 [戰術狂轟] 樂團發動全屏音爆！狂暴的聲波衝擊對手的舞台陣容！", "red")
	
	# 🎯 核心判定：找出誰是目前挨打的一方
	# 如果目前是大回合的 CHOOSE_ATTACKER 且輪到玩家行動，挨打的就是對手的防守陣容
	# 這裡精準鎖定 enemy_list 為敵方的 _engaged_members
	var is_player_attacking = _check_is_player_round() and (current_state == TurnState.CHOOSE_ATTACKER)
	var enemy_list = defender_engaged_members if is_player_attacking else attacker_engaged_members
	
	var hit_any = false
	# 走訪敵方正在舞台上的精英
	for enemy in enemy_list:
		if enemy.hp > 0:
			var base_nerf = randi() % 15 + 10 # 造成 10 ~ 24 點隨機干擾傷害
			enemy.hp = maxi(0, enemy.hp - base_nerf)
			emit_signal("log_requested", ">> %s 承受不住瘋狂音浪，體力滑落 %d 點！" % [enemy.name, base_nerf], "red")
			hit_any = true
			
	if not hit_any:
		emit_signal("log_requested", ">> 音浪太強...可惜對手舞台上已經沒有站著的人了！", "gray")
			
	emit_signal("hp_updated")
	
	# 5. 轟炸完畢後，立刻做核心安全檢查（這發音爆是否直接把對手整隊全滅、拿下比賽）
	_post_combat_check()
	return true


## 輔助函數：戰敗或撤退時重置場上團員的血量底線（防呆）
func _reset_band_hp(band: Band) -> void:
	# 戰鬥結束後，僅將此場真正參戰的人血量歸零，不影響後備名單
	var list = attacker_engaged_members if band == attacker_band else defender_engaged_members
	for m in list:
		if m.hp < 0: 
			m.hp = 0
