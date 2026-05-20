# LiveBattleScreen.gd
extends Control

enum TurnState { CHOOSE_ATTACKER, CHOOSE_DEFENDER }
var current_state = TurnState.CHOOSE_ATTACKER

var attacker_band: Band
var defender_band: Band
var target_venue: Venue
var retreat_btn: Button

var card_scene = preload("res://scenes/battle_member_card.tscn")

# Track which members have already acted during the current round
var acted_this_turn: Array = []
var selected_attacker = null
var venue_database: Dictionary = {}
var is_processing_action: bool = false # The Input Lock Guard Gate

# Ensure these points reference your newly updated GridContainers now!
@onready var attacker_container: GridContainer = $SceneLayout/StageLayout/LeftTeamBox/AttackerRoster
@onready var defender_container: GridContainer = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
@onready var log_box = $SceneLayout/FooterPanel/BattleLog
@onready var prompt_label = $SceneLayout/FooterPanel/ActionPrompt
@onready var background_sprite = $Battlefield

# Inside your combat controller script

var counter_matrix: Dictionary = {}
# Inside live_battle_scene.gd

@onready var groove_meter: ProgressBar = $SceneLayout/HeaderPanel/GrooveMeter
@onready var encore_button: Button = $SceneLayout/HeaderPanel/EncoreButton
@onready var sonic_boom_button: Button = $SceneLayout/HeaderPanel/SonicBoomButton

var stratagem_db: Dictionary = {}
var current_groove_energy: float = 0.0
const MAX_GROOVE_ENERGY: float = 100.0

func _load_stratagems() -> void:
	var file_path = "res://data/stratagems.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			stratagem_db = json.data

## Adds energy to the meter based on performance damage output dealt
func gain_groove_energy(amount: float) -> void:
	current_groove_energy = clamp(current_groove_energy + amount, 0.0, MAX_GROOVE_ENERGY)
	_update_groove_ui()

## Synchronizes the Progress Bar and filters button click capabilities on the fly
func _update_groove_ui() -> void:
	groove_meter.value = current_groove_energy
	
	# Read costs straight out of configuration file settings
	var encore_cost = stratagem_db.get("encore", {}).get("cost", 50.0)
	var sonic_cost = stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	
	# Only unlock buttons if player has gathered sufficient collective band energy
	encore_button.disabled = current_groove_energy < encore_cost
	sonic_boom_button.disabled = current_groove_energy < sonic_cost
	encore_button.pressed.connect(_on_encore_button_pressed)
	sonic_boom_button.pressed.connect(_on_sonic_boom_button_pressed)

func _load_venue_database() -> void:
	var file_path = "res://data/venues.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			venue_database = json.data
		else:
			print("JSON Venue Database Parse Failure.")

## Triggers context loading and visually updates the background layout image frame
func setup_battle_environment(venue_id: String) -> void:
	if not venue_database.has(venue_id): 
		print("Error: Venue key not found in JSON data dictionary file.")
		return
	target_venue.load_from_dict(venue_id, venue_database[venue_id])
	
	# Swap visual assets instantly based on configuration path variables
	if ResourceLoader.exists(target_venue.background_path):
		background_sprite.texture = load(target_venue.background_path)
		
		# Option B: STRETCH_KEEP_ASPECT_COVERED (Keeps aspect ratio perfect, crops edges if needed)
		# background_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		
		# Explicitly pin the node boundaries to your exact targeted engine scale
		background_sprite.custom_minimum_size = Vector2(1920, 1080)
		background_sprite.size = Vector2(1920, 1080)
	_write_log("▶ 當前演出舞台已切換為: %s" % target_venue.display_name, "yellow")
# Safely load and parse the JSON matrix asset file
func _load_counter_matrix() -> void:
	var file_path = "res://data/instrument_matrix.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)
		if error == OK:
			counter_matrix = json.data
		else:
			print("JSON Parse Error: ", json.get_error_message())
	else:
		print("Warning: instrument_matrix.json not found! Defaulting to neutral values.")

# Inside live_battle_scene.gd

## Checks if a Member data object belongs to a card sitting in the back row
func _is_member_in_back_row(member_data: Object, container: GridContainer) -> bool:
	if member_data == null or container == null: 
		return false
	var name = member_data.name
	# Look through all BattleMemberCard buttons inside the grid layout
	for child in container.get_children():
		var child_name = child.member_data.name
		# Option A: Check if your card script has a data object property we can match
		if name == child_name:
			return (child.get_index() % 2) == 1
	# Default to front row if no matching visual card is found on stage
	return false

## Checks if there are any conscious front-row members still protecting the stage
func _has_front_row_defenders(container: GridContainer) -> bool:
	for child in container.get_children():
		# Pull the Member data object out of the UI card node safely
		var card_member = child.get("member_data") if "member_data" in child else null
		
		if card_member and card_member.hp > 0:
			var index = child.get_index()
			if (index % 2) == 0: # Column 1 (Front Stage Row)
				return true
				
	return false
## Validates if the selected attacker is legally allowed to target the chosen defender
func is_target_legal(attacker, defender, defender_container: GridContainer) -> bool:
	# Rule 1: You can always target anyone if they are in the Front Row
	if not _is_member_in_back_row(defender, defender_container):
		return true
		
	# Rule 2: If the target is in the Back Row, check the attacker's weapon/part class range capabilities
	var long_range_parts = ["Vo/Gt", "Vo", "Gt", "Ba"] # Parts that can pierce/reach the back row
	if attacker.part in long_range_parts:
		return true # Pierces directly to the back row!
		
	# Rule 3: For melee/short-range parts, they can only strike the back row IF the front row is wiped clean
	if _has_front_row_defenders(defender_container):
		_write_log("[無效目標] 前排仍有隊員在阻擋護航！%s 無法直接突擊後排。" % attacker.name, "orange")
		return false
		
	return true # Front row is dead; back row is vulnerable to everyone

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
		_write_log("[環境干擾] 傳統古典音樂廳的音響設計壓制了搖滾主唱的爆發力！", "purple")
		return 0.65 # Throttles raw performance output to 65%
	return 1.0
# --- YOUR REFACTORED COMBAT FUNCTION ---
func execute_combat_turn(selected_attacker, target_member) -> void:
	var venue_mods = target_venue.modifiers if target_venue else {}
	
	# ==========================================
	# 1. CALCULATE ATTACKER MODIFIERS (PERF)
	# ==========================================
	var a_perf = selected_attacker.get("perf")
	
	var matrix_mod = _get_matrix_modifier(selected_attacker.part, target_member.part)
	var environment_perf_mod = _get_venue_perf_modifier(selected_attacker.part, venue_mods)
	var special_throttle_multiplier = _get_venue_throttle_multiplier(selected_attacker.part, venue_mods)
		
	# Final Aggregation for Attacker Score
	var total_attack_multiplier = 1.0 + matrix_mod + environment_perf_mod
	var final_attacker_perf = (a_perf * total_attack_multiplier) * special_throttle_multiplier

	# ==========================================
	# 2. CALCULATE DEFENDER MODIFIERS (STAMINA)
	# ==========================================
	var d_stam = target_member.get("stam")
	
	var environment_stam_mod = 0.0
	var stam_nerf_dict = venue_mods.get("stam_nerf", {})
	if stam_nerf_dict.has(target_member.part):
		environment_stam_mod = stam_nerf_dict[target_member.part]
		
	var total_defense_multiplier = 1.0 + environment_stam_mod
	var final_defender_stam = d_stam * total_defense_multiplier

	# ==========================================
	# 3. DAMAGE EXECUTION PIPELINE
	# ==========================================
	var dmg = maxi(8, (final_attacker_perf / 2) - (final_defender_stam / 4) + randi() % 15)
	target_member.hp = maxi(0, target_member.hp - dmg)
	
	var env_tag = "[環境加成] " if environment_perf_mod > 0.0 else ""
	_write_log("%s[進攻] %s 進行了極致演奏！造成 %s 體力下降了 %d 點。" % [env_tag, selected_attacker.name, target_member.name, dmg], "cyan")
	
	acted_this_turn.append(selected_attacker)
	# BUILD ENERGY: Add a fraction of damage dealt straight into the collective gauge meter
	if current_state == TurnState.CHOOSE_DEFENDER: # Only player hits charge the tactical meter
		gain_groove_energy(dmg * 0.4) # Converts 40% of damage score directly into groove power
	# ==========================================
	# 4. COUNTER-STRIKE RESOLUTION
	# ==========================================
	if target_member.hp > 0:
		# Using our new helpers makes the counter calculation elegant and readable!
		var counter_matrix_mod = _get_matrix_modifier(target_member.part, selected_attacker.part)
		var counter_env_perf_mod = _get_venue_perf_modifier(target_member.part, venue_mods)
		var counter_throttle = _get_venue_throttle_multiplier(target_member.part, venue_mods)
			
		var total_counter_multiplier = 1.0 + counter_matrix_mod + counter_env_perf_mod
		var decay_rate = venue_mods.get("stamina_decay_multiplier", 1.0)
		
		var base_counter_score = (d_stam * total_counter_multiplier) * counter_throttle
		
		var counter_dmg = maxi(8, (base_counter_score / 2) - (selected_attacker.get("stam") / 4) + randi() % 15)
		counter_dmg = int(counter_dmg * decay_rate)
		
		selected_attacker.hp = maxi(0, selected_attacker.hp - counter_dmg)
		_write_log("[反擊] %s 不甘示弱回擊！造成 %s 體力下降了 %d 點。" % [target_member.name, selected_attacker.name, counter_dmg], "red")
	else:
		_write_log(">> %s 已經精疲力竭，被迫離開舞台！ <<" % target_member.name, "orange")

## Replaces your old standalone handle_battle method! Called on scene transition initialization.
func start_interactive_battle(attacker: Band, defender: Band, venue: Venue) -> void:
	attacker_band = attacker
	defender_band = defender
	target_venue = venue
	retreat_button()
	_load_stratagems()
	_update_groove_ui()
	_load_counter_matrix()
	_load_venue_database()
	setup_battle_environment(target_venue.id)

	_write_log("LIVE BATTLE ENGAGED: %s VS %s" % [attacker.band_name, defender.band_name], "yellow")
	_write_log("Location: %s" % venue.name, "white")
	# 2. Configure the teams to aggressively expand into available screen real estate
	# This pushes LeftTeamBox all the way left and RightTeamBox all the way right
	$SceneLayout/StageLayout/LeftTeamBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$SceneLayout/StageLayout/RightTeamBox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# 3. Ensure the VS Label remains locked and tightly centered
	$SceneLayout/StageLayout/VSLabel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# ---------------------------------------------

	# 3. Keep the Header and Footer bounded to their own compact sizes
	$SceneLayout/HeaderPanel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	$SceneLayout/FooterPanel.size_flags_vertical = Control.SIZE_SHRINK_END
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
		card.card_clicked.connect(_on_target_clicked)
		
	# Spawn Defenders
	for member in defender_band.members:
		var card = card_scene.instantiate()
		defender_container.add_child(card)
		card.setup(member)
		card.card_clicked.connect(_on_target_clicked)

# Inside live_battle_scene.gd

## Automatically finds and highlights the next eligible attacker from your team
func select_next_attacker() -> void:
	var attacker_grid
	if(current_state == TurnState.CHOOSE_ATTACKER): attacker_grid = $SceneLayout/StageLayout/LeftTeamBox/AttackerRoster
	else: attacker_grid = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
	selected_attacker = null # Reset current selection slot
	
	# Loop through the grid children in order of their placement
	for card in attacker_grid.get_children():
		var member_data = card.get("member_data") if "member_data" in card else null
		
		# Find the first member who is alive and hasn't performed yet
		if member_data and member_data.hp > 0 and not (member_data in acted_this_turn):
			selected_attacker = member_data
			
			# Visual Highlight: Make the auto-selected attacker's card pop out!
			card.modulate = Color(1.5, 1.5, 1.0, 1.0) # Gives a bright spotlight glow
			_write_log("★ 輪到 [ %s ] (%s) 進行演出準備！" % [selected_attacker.name, selected_attacker.part], "yellow")
			break
			
	# If no attackers are found, the round is over! Trigger the automated turn transition
	if selected_attacker == null:
		_write_log("▶ 全體團員本輪演出完畢。回合結束！", "gray")
		refresh_targetable_overlays()
		_start_new_round()
		return
		
	# Refresh target overlays to immediately show the player which enemy rows are legal
	refresh_targetable_overlays()

func _start_new_round() -> void:
	if(current_state == TurnState.CHOOSE_ATTACKER): current_state = TurnState.CHOOSE_DEFENDER
	else: current_state = TurnState.CHOOSE_ATTACKER
	acted_this_turn.clear()
	selected_attacker = null
	_refresh_card_filters()
	select_next_attacker()
	# prompt_label.custom_minimum_size = Vector2(80, 15)
	# log_box.custom_minimum_size = Vector2(80, 15)

## Callback handling targeted structural damage routing
func _on_target_clicked(target_member) -> void:
	if is_processing_action: return
	is_processing_action = true
	if target_member.hp <= 0 or selected_attacker == null: return

	# Run our new Row-Proximity Guard Gate validation check
	var defender_grid = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
	if not is_target_legal(selected_attacker, target_member, defender_grid):
		# Flash target UI red or play an error sound asset effect here
		return
	execute_combat_turn(selected_attacker, target_member)
	# Update health bar metrics across the entire board visually
	_update_all_hp_bars()
	
	# 3. Check for immediate match termination criteria
	if _check_battle_over():
		return
		
	# 4. Turn Phase Resolution Routing
	if _has_available_attackers():
		# Shift focus back to selection step for remaining characters
		selected_attacker = null
		is_processing_action = false
		select_next_attacker()
	else:
		# If everyone has performed, cycle down directly to next full game engine step
		_write_log(">> 全體團員表演結束，換幕處理中... <<", "gray")
		is_processing_action = false
		_start_new_round()

func refresh_targetable_overlays() -> void:
	if selected_attacker == null: return
	var defender_grid
	if(current_state == TurnState.CHOOSE_ATTACKER): defender_grid = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
	else:  defender_grid = $SceneLayout/StageLayout/LeftTeamBox/AttackerRoster
	for defender_card in defender_grid.get_children():
		var defender = defender_card.member_data
		if is_target_legal(selected_attacker, defender, defender_grid) && defender.hp>0:
			defender_card.modulate = Color(0.4, 0.8, 0.7, 1.0) # Fully interactive
			defender_card.disabled = false
		else:
			# Dim the card out visually so the player instantly knows it's guarded by a high-stamina tank!
			defender_card.modulate = Color(0.4, 0.4, 0.4, 0.8)
			defender_card.disabled = true

## Resets all member cards in both rosters back to their original full opacity state
func reset_all_card_modulations() -> void:
	var left_grid = $SceneLayout/StageLayout/LeftTeamBox/AttackerRoster
	var right_grid = $SceneLayout/StageLayout/RightTeamBox/DefenderRoster
	
	# Reset Player Side
	for card in left_grid.get_children():
		card.modulate = Color(1.0, 1.0, 1.0, 1.0)
		
	# Reset Enemy Side
	for card in right_grid.get_children():
		card.modulate = Color(1.0, 1.0, 1.0, 1.0)

## Ensures button click permissions accurately match current action logic states
func _refresh_card_filters() -> void:
	var container_a
	var container_b
	if(current_state == TurnState.CHOOSE_DEFENDER):
		container_a = attacker_container
		container_b = defender_container
	else:
		container_a = defender_container
		container_b = attacker_container
	for card in container_a.get_children():
		if card.member_data.hp <= 0: continue
		# Disable button interaction if they already performed this turn round cycle
		card.disabled = acted_this_turn.has(card.member_data)
		
	for card in container_b.get_children():
		if card.member_data.hp <= 0: continue
		# Only allow targeting choices when an attacker has been selected
		card.disabled = true
		reset_all_card_modulations()

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
	exit_button()

func retreat_button() -> void:
	retreat_btn = Button.new()
	retreat_btn.text = "逃跑 (Retreat)"
	retreat_btn.custom_minimum_size = Vector2(200, 50)
	# Restore health tracking states to clean baselines
	_reset_band_hp(attacker_band)
	_reset_band_hp(defender_band)
	GameStateBang.data.bands[GameStateBang.attacker] = attacker_band
	GameStateBang.data.bands[GameStateBang.defender] = defender_band
	GameStateBang.data.worldMap[target_venue.name]
	$SceneLayout/FooterPanel.add_child(retreat_btn)
	retreat_btn.pressed.connect(Global.event_facade.stop_invation)

func exit_button() -> void:
	if(retreat_btn):
		retreat_btn.queue_free()
		retreat_btn = null
	# Spawn a confirmation exit button to return cleanly back to the global map screen
	var exit_btn = Button.new()
	exit_btn.text = "確認並返回地圖 (Confirm & Return)"
	exit_btn.custom_minimum_size = Vector2(200, 50)
	# Restore health tracking states to clean baselines
	_reset_band_hp(attacker_band)
	_reset_band_hp(defender_band)
	GameStateBang.data.bands[GameStateBang.attacker] = attacker_band
	GameStateBang.data.bands[GameStateBang.defender] = defender_band
	GameStateBang.data.worldMap[target_venue.name]
	$SceneLayout/FooterPanel.add_child(exit_btn)
	exit_btn.pressed.connect(Global.event_facade.stop_invation)

func _reset_band_hp(band: Band) -> void:
	for m in band.members:
		if m.hp < 0: m.hp = 0

func _write_log(msg: String, color_tag: String = "white") -> void:
	log_box.append_text("[color=%s]%s[/color]\n" % [color_tag, msg])

# Inside live_battle_scene.gd

## Triggered when pressing the Encore! Button
func _on_encore_button_pressed() -> void:
	var cost = stratagem_db.get("encore", {}).get("cost", 50.0)
	if current_groove_energy < cost: return
	
	# Find a team member whose HP is currently sitting at 0
	var target_to_revive = null
	for card in attacker_container.get_children():
		if card.member_data and card.member_data.hp <= 0:
			target_to_revive = card.member_data
			break
			
	if target_to_revive == null:
		_write_log("沒有處於精疲力竭狀態的團員，無法發動安可！", "orange")
		return
		
	# Pay energy points cost deduction
	current_groove_energy -= cost
	
	# Revive character back with a solid 30% calculation boundary
	var max_hp = target_to_revive.max_hp
	target_to_revive.hp = int(max_hp * 0.30)
	
	_write_log("✦ [戰術安可] 全場歡呼！%s 重新回到舞台並恢復了 30%% 體力！" % target_to_revive.name, "pink")
	_update_all_hp_bars()

## Triggered when pressing the Sonic Boom Button
func _on_sonic_boom_button_pressed() -> void:
	var cost = stratagem_db.get("sonic_boom", {}).get("cost", 100.0)
	if current_groove_energy < cost: return
	
	# Pay energy points cost deduction
	current_groove_energy -= cost
	
	_write_log("💥 [戰術狂轟] 樂團發動全屏音爆！狂暴的聲波衝擊全場防守者！", "red")
	
	# AOE Strike: Target every conscious defender child card in the roster simultaneously
	for card in defender_container.get_children():
		var enemy = card.get("member_data")
		if enemy and enemy.hp > 0:
			# Apply flat stamina damage or strip active base stats
			var base_nerf = randi() % 15 + 10
			enemy.hp = maxi(0, enemy.hp - base_nerf)
			_write_log(">> %s 受音爆震撼，體力滑落 %d 點！" % [enemy.name, base_nerf], "red")
	_update_all_hp_bars()
