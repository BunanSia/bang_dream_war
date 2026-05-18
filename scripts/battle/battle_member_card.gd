# BattleMemberCard.gd
extends Button

signal card_clicked(member_ref)

var member_data # Reference pointing straight back to the underlying dict/object structure

# Inside BattleMemberCard.gd
# Inside BattleMemberCard.gd

func setup(member) -> void:
	member_data = member
	$VBoxContainer/NameLabel.text = member.name
	$VBoxContainer/HPProgress.max_value = member.get("max_hp") if member.has_method("get_total_max_hp") else 100
	$VBoxContainer/HPProgress.value = member.hp
	
	var icon: TextureRect = $VBoxContainer/IconRect
	
	# --- CONFIGURE VERTICALLY TALL PORTRAIT SCALING ---
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	# Force an exact portrait bounding container ratio (e.g., 90 wide by 120 tall)
	icon.custom_minimum_size = Vector2(200, 200)
	
	# Let the image expand horizontally/vertically inside its grid cell room limits
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Optional layout preservation rule
	$VBoxContainer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# --------------------------------------------------
	
	var path = "res://assets/icons/%s.png" % member.name
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	pressed.connect(func(): card_clicked.emit(member_data))

func update_hp_display() -> void:
	$VBoxContainer/HPProgress.value = member_data.hp
	if member_data.hp <= 0:
		disabled = true
		modulate = Color(0.3, 0.3, 0.3, 1.0) # Gray out defeated members
