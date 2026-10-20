extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scripts/main.gd").new()
 game.pad_persistence_enabled=false
 root.add_child(game)
 game.set_physics_process(false)
 game.set_process(false)
 var path="user://desktop-save-qa.json"
 assert(game._save_pad_settings(path))
 var file=FileAccess.open(path,FileAccess.READ)
 assert(file!=null)
 var data=JSON.parse_string(file.get_as_text())
 file.close()
 game.pad.model.look_speed=3.1
 assert(game._import_pad_settings(data))
 assert(is_equal_approx(game.pad.model.look_speed,float(data.pad.look_speed)))
 assert(not game.audio_scene.web_sample_active)
 assert(game.pad.haptics.status(0).available==false)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
 print("NATIVE_SAVE_ROUNDTRIP_PASS; native audio mode; no native vibration")
 game.queue_free()
 await process_frame
 quit()
