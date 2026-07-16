# RecruitController.gd
extends Node
class_name RecruitController

signal recruit_market_refreshed

## 檢查玩家是否擁有海報牆家具 (掃描玩家擁有的所有場地)
func has_poster_wall() -> bool:
	var player_band_id = GameStateBang.player
	var player_band = GameStateBang.data.bands[player_band_id]
	
	if not GameStateBang.data.has("worldMap"):
		return false
		
	for venue_name in GameStateBang.data.worldMap:
		var venue = GameStateBang.data.worldMap[venue_name]
		if venue.get("owner") == player_band:
			var furnitures = venue.get("installed_furniture")
			# 相容字串與 Dictionary 格式的家具檢查
			for furniture in furnitures:
				if "Poster Wall" == furniture.item_name:
					return true
	return false

## 獲取目前市場上所有可招募的自由成員
func get_available_recruits() -> Array:
	return GameStateBang.free_member_pool

## 檢查特定的成員是否符合招募條件
func can_recruit_member(member_data: Dictionary) -> bool:
	# 1. 剛需條件：必須有海報牆
	if not has_poster_wall(): 
		return false
		
	var player_band = GameStateBang.data.bands[GameStateBang.player]
	var cost = member_data.get("cost", 99999)
	
	# 2. 經濟條件：錢夠不夠
	if player_band.money < cost: 
		return false
	return true

## 執行招募核心商務邏輯
func recruit_member(member_data: Dictionary) -> void:
	if not can_recruit_member(member_data):
		printerr("Recruit Error: Conditions not met for ", member_data.get("name"))
		return
	
	# 1. 透過 Facade 門面執行實際的扣款、扣 AP、塞入隊伍資料
	var success = Global.event_facade.execute_action(
		Global.event_facade.add_band_member,
		[GameStateBang.player, member_data]
	)
	if success:
		# 2. 從全域的自由成員池中移除（已被玩家簽走）
		GameStateBang.free_member_pool.erase(member_data)
		
		# 3. 通知 UI 市場資料有變動，該刷新了
		recruit_market_refreshed.emit()
