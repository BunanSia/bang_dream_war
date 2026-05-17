class_name DialogueSystem
extends Node

# Signals to notify the UI or Game Engine
signal dialogue_started
signal dialogue_line_displayed(speaker: String, text: String)
signal dialogue_finished

var current_dialogue: Array = []
var current_step: int = 0
var is_active: bool = false

# A structured dialogue sequence
var example_story = [
	{"speaker": "CHU2", "text": "Listen up! RAISE A SUILEN is taking over this venue."},
	{"speaker": "Kasumi", "text": "No way! We won't give up our stage without a fight!"},
	{"speaker": "CHU2", "text": "Then let the music do the talking. Prepare yourself!"}
]

func start_dialogue(lines: Array) -> void:
	current_dialogue = lines
	current_step = 0
	is_active = true
	dialogue_started.emit()
	show_current_line()

func show_current_line() -> void:
	if current_step >= current_dialogue.size():
		end_dialogue()
		return
		
	var data = current_dialogue[current_step]
	# Emit signal so the UI knows what to render
	dialogue_line_displayed.emit(data["speaker"], data["text"])

func advance_dialogue() -> void:
	if not is_active:
		return
	current_step += 1
	show_current_line()

func end_dialogue() -> void:
	is_active = false
	current_dialogue.clear()
	dialogue_finished.emit()
	print("Dialogue finished. Game resumes.")
