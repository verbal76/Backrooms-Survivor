class_name NullAudio
extends Node
## No-op audio API so systems can call game.audio.* before the real audio system is loaded.
func play(_sound: String, _world_px = null, _volume := 1.0, _pitch := 1.0) -> void: pass
func play_music(_track: String) -> void: pass
func stop_music() -> void: pass
