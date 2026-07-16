class_name RuleBook

## 🆕 終極複合乘數計算器
static func get_final_combat_modifier(subject: Object, opponent: Object, sub_band: Band, opp_band: Band, venue: Venue, is_attacking: bool) -> float:
	var multiplier = 1.0
	var venue_mods = venue.modifiers if venue else {}
	
	# 1. 🎸 樂團流派屬性加成 (Type vs Type)
	if is_attacking:
		if sub_band.get("type") == "professional_agency": multiplier += 0.1
		if sub_band.get("type") == "indie_underground" and opp_band.get("type") == "professional_agency": multiplier += 0.15
	else:
		if sub_band.get("type") == "school_band": multiplier += 0.2 # 校園防守特化

	# 2. 🎻 樂器部件互克 (Part vs Part)
	# 利用全域矩陣查表
	if GameStateBang.counter_matrix.has(subject.part):
		multiplier += GameStateBang.counter_matrix[subject.part].get(opponent.part, 0.0)

	# 3. 🏟️ 場地環境特定樂器優化與干擾 (Part vs Venue)
	var perf_bonus_dict = venue_mods.get("perf_bonus", {})
	if perf_bonus_dict.has(subject.part):
		multiplier += perf_bonus_dict[subject.part]
		
	# 傳統古典廳壓制搖滾主唱
	if venue_mods.get("vocal_throttle", false) and subject.part == "Vo/Gt":
		multiplier *= 0.65 

	return multiplier
