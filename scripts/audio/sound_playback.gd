extends RefCounted
class_name SlimeSoundPlayback

# Opt in per sound. No global bus effect and no changes to ambient loops.
# A dedicated RNG keeps cosmetic variation out of gameplay random sequences.
static var _pitch_rng: RandomNumberGenerator

static func pitch_for(variation: float = 0.0, base_pitch: float = 1.0, rng: RandomNumberGenerator = null) -> float:
	var width := clampf(variation, 0.0, 0.08)
	var base := maxf(0.01, base_pitch)
	if is_zero_approx(width):
		return base
	if rng == null:
		if _pitch_rng == null:
			_pitch_rng = RandomNumberGenerator.new()
			_pitch_rng.randomize()
		rng = _pitch_rng
	return base * rng.randf_range(1.0 - width, 1.0 + width)

static func play_existing(voice: Node, variation: float = 0.0, base_pitch: float = 1.0) -> void:
	if not is_instance_valid(voice) or not (voice is AudioStreamPlayer or voice is AudioStreamPlayer2D or voice is AudioStreamPlayer3D):
		return
	# Assign from base each time: variation never compounds over repetitions.
	voice.pitch_scale = pitch_for(variation, base_pitch)
	voice.play()

static func play_3d(parent: Node, stream: AudioStream, at: Vector3, options: Dictionary = {}) -> AudioStreamPlayer3D:
	if stream == null or not is_instance_valid(parent) or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return null
	var voice := AudioStreamPlayer3D.new()
	voice.process_mode = Node.PROCESS_MODE_PAUSABLE
	voice.stream = stream
	voice.bus = options.get("bus", SlimeGameSettings.EFFECTS_BUS)
	voice.unit_size = float(options.get("unit_size", 4.0))
	voice.volume_db = float(options.get("volume_db", 0.0))
	parent.add_child(voice)
	voice.global_position = at
	voice.finished.connect(voice.queue_free)
	play_existing(voice, float(options.get("pitch_variation", 0.0)), float(options.get("pitch_base", 1.0)))
	return voice
