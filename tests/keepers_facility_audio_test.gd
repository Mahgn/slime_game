extends SceneTree

var failed := false
var output_folder := "res://output/keepers_f06_2026_10_08/audio/"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("BLOCKED mechanism audio needs a native driver")
		quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=res://output/"):
			output_folder = arg.trim_prefix("--output=").trim_suffix("/")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_folder))
	SlimeGameSettings.current().load_settings(output_folder+"settings.cfg")
	for round_index in 3:
		change_scene_to_file("res://scenes/keepers/keepers_facility.tscn")
		await _ticks(20)
		var level = current_scene
		var weak_streams: Array[WeakRef] = []
		var listener_ref: WeakRef = weakref(level.ambience.listener)
		_check(level.ambience.listener.is_current(),"Reloaded level owns the current hero listener")
		for source: Dictionary in level.ambience.sources:
			_check(source.player.playing and source.player.bus==&"Ambience","Local room loop starts on Ambience")
			_check(is_equal_approx(source.player.pitch_scale,1.0),"Ambient loops retain original pitch")
			weak_streams.append(weakref(source.player.stream))
		for hazard in level.hazards:
			hazard._play_cue(true)
			_check(hazard.audio_player.playing and hazard.audio_player.stream==hazard.warning_sound,"Separate warning cue starts")
			_check(is_equal_approx(hazard.audio_player.pitch_scale,1.0),"Warning cue starts at original pitch")
			weak_streams.append(weakref(hazard.warning_sound))
			hazard.introduced = true
			hazard.clock = hazard.SAFE+hazard.WARNING
			hazard._physics_process(0.016)
			_check(hazard.audio_player.playing and hazard.audio_player.bus==&"Effects","Native hazard cue starts on Effects")
			weak_streams.append(weakref(hazard.audio_player.stream))
			var low: float = INF
			var high: float = -INF
			for repeat in 32:
				hazard._play_cue(false)
				low = minf(low,hazard.audio_player.pitch_scale)
				high = maxf(high,hazard.audio_player.pitch_scale)
			if hazard.spec.kind == "steam":
				_check(is_equal_approx(low,1.0) and is_equal_approx(high,1.0),"Steam cue is not opted into random pitch")
			else:
				_check(low>=0.98 and high<=1.02 and high-low>0.01,"Mechanical trap impact varies within plus/minus 2 percent without drift")
			hazard._play_cue(true)
			_check(hazard.audio_player.stream==hazard.warning_sound and is_equal_approx(hazard.audio_player.pitch_scale,1.0),"Reused trap voice resets warning pitch after varied impacts")
		current_scene = null
		level.queue_free()
		await _ticks(30)
		_check(listener_ref.get_ref()==null,"Scene teardown releases the hero listener")
		for stream_ref: WeakRef in weak_streams:
			_check(stream_ref.get_ref()==null,"Scene teardown releases synthesized stream")
		print("AUDIO_LIFECYCLE_ROUND ",round_index+1)
	quit(1 if failed else 0)

func _check(value: bool, label: String) -> void:
	failed = failed or not value
	print("PASS " if value else "FAIL ",label)

func _ticks(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame
		paused = false
