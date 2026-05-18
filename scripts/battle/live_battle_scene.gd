# LiveBattleScreen.gd
extends Control

enum TurnState { CHOOSE_ATTACKER, CHOOSE_TARGET, RESOLVING }
var current_state = TurnState.CHOOSE_ATTACKER

var attacker_band: Band
var defender_band: Band
var target_venue: Venue

var card_scene = preload("res://scenes/battle_member_card.tscn")

# Track which members have already acted during the current round
var acted_this_turn: Array = []
var selected_attacker = null

# Ensure these points reference your newly updated GridContainers now!
@onready var attacker_container: GridContainer = $VBoxContainer/StageLayout/LeftTeamBox/AttackerRoster
@onready var defender_container: GridContainer = $VBoxContainer/StageLayout/RightTeamBox/DefenderRoster
@onready var log_box = $VBoxContainer/FooterPanel/BattleLog
@onready var prompt_label = $VBoxContainer/FooterPanel/ActionPrompt

## Replaces your old standalone handle_battle method! Called on scene transition initialization.
func start_interactive_battle(attacker: Band, defender: Band, venue: Venue) -> void:
	attacker_band = attacker
	defender_band = defender
	target_venue = venue
	
	_write_log("LIVE BATTLE ENGAGED: %s VS %s" % [attacker.band_name, defender.band_name], "yellow")
	_write_log("Location: %s" % venue.name, "white")
	# --- CONFIGURE STRUCTURAL COLUMNS DISTANCE ---
	var stage: HBoxContainer = $VBoxContainer/StageLayout
	
	# 1. Force a mandatory base buffer gap between the three major blocks
	stage.add_theme_constant_override("separation", 150) # 40 pixels wide spacing gap
	
	# 2. Configure the teams to aggressively expand into available screen real estate
	# This pushes LeftTeamBox all the way left and RightTeamBox all the way right
	$VBoxContainer/StageLayout/LeftTeamBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$VBoxContainer/StageLayout/RightTeamBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 3. Ensure the VS Label remains locked and tightly centered
	$VBoxContainer/StageLayout/VSLabel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# ---------------------------------------------

	# 2. Tell the middle StageLayout to stretch and absorb all leftover screen height
	# This ensures your Header stays at the top, Footer stays at the bottom, 
	# and the Battle Stage takes up the dominant middle area.
	$VBoxContainer/StageLayout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# 3. Keep the Header and Footer bounded to their own compact sizes
	$VBoxContainer/HeaderPanel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	$VBoxContainer/FooterPanel.size_flags_vertical = Control.SIZE_SHRINK_END
	# -----------------------------------------------------
	log_box.custom_minimum_size = Vector2(800, 100)
	_build_rosters()
	_start_new_round()

# Inside LiveBattleScreen.gd

func _build_rosters() -> void:
	# 1. Clean out the previous visual grid setups
	for child in attacker_container.get_children(): child.queue_free()
	for child in defender_container.get_children(): child.queue_free()
	
	# 2. Configure clean, grid-based spacing boundaries
	# This handles the structural gap between columns and rows independently
	var space_x = 200 # Distance between columns
	var space_y = 300 # Distance between rows
	
	attacker_container.add_theme_constant_override("h_separation", space_x)
	attacker_container.add_theme_constant_override("v_separation", space_y)
	
	defender_container.add_theme_constant_override("h_separation", space_x)
	defender_container.add_theme_constant_override("v_separation", space_y)
	
	# 3. Dynamic Spawning logic maps directly into the 3-column rows automatically!
	# Spawn Attackers
	for member in attacker_band.members:
		var card = card_scene.instantiate()
		attacker_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_attacker_clicked)
		
	# Spawn Defenders
	for member in defender_band.members:
		var card = card_scene.instantiate()
		defender_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_defender_clicked)

func _start_new_round() -> void:
	acted_this_turn.clear()
	selected_attacker = null
	current_state = TurnState.CHOOSE_ATTACKER
	prompt_label.text = "新回合開始：請點擊您的一名左側團員發動表演！"
	# prompt_label.custom_minimum_size = Vector2(80, 15)
	# log_box.custom_minimum_size = Vector2(80, 15)
	_refresh_card_filters()

## Callback handling attacker selections
func _on_attacker_clicked(member) -> void:
	if current_state != TurnState.CHOOSE_ATTACKER: return
	if member.hp <= 0 or acted_this_turn.has(member): return
	
	selected_attacker = member
	current_state = TurnState.CHOOSE_TARGET
	prompt_label.text = "【%s】準備中！請點擊右側敵方的一名團員進行突擊！" % member.name
	_refresh_card_filters()

## Callback handling targeted structural damage routing
func _on_defender_clicked(target_member) -> void:
	if current_state != TurnState.CHOOSE_TARGET: return
	if target_member.hp <= 0 or selected_attacker == null: return
	
	current_state = TurnState.RESOLVING
	
	# 1. Attacker performs (Your original combat formula)
	var a_perf = selected_attacker.get("perf")
	var d_stam = target_member.get("stam")
	var dmg = maxi(8, (a_perf / 2) - (d_stam / 4) + randi() % 15)
	
	target_member.hp = maxi(0, target_member.hp - dmg)
	_write_log("[進攻] %s 進行了極致演奏！造成 %s 體力下降了 %d 點。" % [selected_attacker.name, target_member.name, dmg], "cyan")
	
	# Mark attacker as having used their 1 action chance this turn
	acted_this_turn.append(selected_attacker)
	
	# 2. Check if target survived to execute an immediate counter-strike
	if target_member.hp > 0:
		var counter_dmg = maxi(8, (d_stam / 2) - (selected_attacker.get("stam") / 4) + randi() % 15)
		selected_attacker.hp = maxi(0, selected_attacker.hp - counter_dmg)
		_write_log("[反擊] %s 不甘示弱回擊！造成 %s 體力下降了 %d 點。" % [target_member.name, selected_attacker.name, counter_dmg], "red")
	else:
		_write_log(">> %s 已經精疲力竭，被迫離開舞台！ <<" % target_member.name, "orange")
		
	# Update health bar metrics across the entire board visually
	_update_all_hp_bars()
	
	# 3. Check for immediate match termination criteria
	if _check_battle_over():
		return
		
	# 4. Turn Phase Resolution Routing
	if _has_available_attackers():
		# Shift focus back to selection step for remaining characters
		selected_attacker = null
		current_state = TurnState.CHOOSE_ATTACKER
		prompt_label.text = "請選擇下一位尚未表演的團員進行突破。"
		_refresh_card_filters()
	else:
		# If everyone has performed, cycle down directly to next full game engine step
		_write_log(">> 全體團員表演結束，換幕處理中... <<", "gray")
		await get_tree().create_timer(1.5).timeout
		_start_new_round()

## Ensures button click permissions accurately match current action logic states
func _refresh_card_filters() -> void:
	for card in attacker_container.get_children():
		if card.member_data.hp <= 0: continue
		# Disable button interaction if they already performed this turn round cycle
		card.disabled = (current_state != TurnState.CHOOSE_ATTACKER or acted_this_turn.has(card.member_data))
		
	for card in defender_container.get_children():
		if card.member_data.hp <= 0: continue
		# Only allow targeting choices when an attacker has been selected
		card.disabled = (current_state != TurnState.CHOOSE_TARGET)

func _update_all_hp_bars() -> void:
	for card in attacker_container.get_children(): card.update_hp_display()
	for card in defender_container.get_children(): card.update_hp_display()

func _has_available_attackers() -> bool:
	for member in attacker_band.members:
		if member.hp > 0 and not acted_this_turn.has(member):
			return true
	return false

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
	prompt_label.text = "戰鬥結束！"
	_write_log("\n==================================================", "yellow")
	
	if attacker_won:
		_write_log(" RESULT: 勝利！ %s 成功攻佔了舞台！" % attacker_band.band_name, "green")
		# Swap operational territory vectors
		defender_band.remove_venue(target_venue) if defender_band.has_method("remove_venue") else null
		attacker_band.add_venue(target_venue) if attacker_band.has_method("add_venue") else null
		target_venue.owner = attacker_band
	else:
		_write_log(" RESULT: 戰敗... %s 堅守住了 Livehouse 陣地！" % defender_band.band_name, "red")
		
	_write_log("==================================================\n", "yellow")
	
	# Restore health tracking states to clean baselines
	_reset_band_hp(attacker_band)
	_reset_band_hp(defender_band)
	GameStateBang.data.bands[GameStateBang.attacker] = attacker_band
	GameStateBang.data.bands[GameStateBang.defender] = defender_band
	GameStateBang.data.worldMap[target_venue.name]
	# Spawn a confirmation exit button to return cleanly back to the global map screen
	var exit_btn = Button.new()
	exit_btn.text = "確認並返回地圖 (Confirm & Return)"
	exit_btn.custom_minimum_size = Vector2(200, 50)
	$VBoxContainer/FooterPanel.add_child(exit_btn)
	exit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_game.tscn"))

func _reset_band_hp(band: Band) -> void:
	for m in band.members:
		if m.hp < 0: m.hp = 0

func _write_log(msg: String, color_tag: String = "white") -> void:
	log_box.append_text("[color=%s]%s[/color]\n" % [color_tag, msg])
