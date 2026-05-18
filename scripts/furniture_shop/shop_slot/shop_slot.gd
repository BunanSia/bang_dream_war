# ShopSlot.gd
extends Button

signal slot_focused(item_data: Dictionary)

var current_data: Dictionary

func setup(data: Dictionary) -> void:
	current_data = data
	$VBoxContainer/ItemName.text = data.get("name", "Unknown")
	$VBoxContainer/ItemPrice.text = "$%d" % data.get("cost", 0)
	
	var texture_path = "res://assets/furniture/%s.png" % data.get("name")
	if ResourceLoader.exists(texture_path):
		$VBoxContainer/ItemIcon.texture = load(texture_path)
		
	# Connect Godot's built-in focus/hover signals to display description automatically
	focus_entered.connect(_on_focused)
	mouse_entered.connect(_on_focused)

func _on_focused() -> void:
	slot_focused.emit(current_data)
