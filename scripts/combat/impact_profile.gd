extends Resource
class_name SlimeImpactProfile

# Shared authoring data only. Burst ages, hit targets and clocks live in nodes.
enum ParticleStyle { SHARDS, DROPLETS, THREADS, SPIKES }

@export var profile_id: StringName = &"generic"
@export var particle_style: ParticleStyle = ParticleStyle.SHARDS
@export var primary_color := Color("ffe9aa")
@export var accent_color := Color("fffdf0")
@export_range(0.05, 1.0) var burst_seconds := 0.30
@export_range(0.1, 8.0) var particle_speed := 2.8
@export var particle_size := Vector3(0.05, 0.05, 0.12)
@export var flash_color := Color(1.0, 0.98, 0.90, 0.98)
@export_range(0.0, 0.15) var flash_seconds := 0.055
@export_range(0.0, 1.5) var recoil_strength := 1.0
@export_range(0.0, 1.0) var camera_strength := 0.65
@export_range(0.0, 1.0) var kill_camera_strength := 1.0
@export_range(0.0, 0.08) var hitstop_seconds := 0.045
@export_range(0.0, 0.08) var kill_hitstop_seconds := 0.060
@export var impact_sound: AudioStream
@export_range(0.8, 1.2) var pitch_base := 1.0
@export_range(0.0, 0.08) var pitch_variation := 0.035
@export_range(-24.0, 3.0) var volume_db := 0.0

# Optional spell stages. All zero/default fields keep legacy attacks unchanged.
@export_enum("None", "Orb", "Ground", "Shell") var charge_style: int = 0
@export_range(0.0, 1.0) var charge_size := 0.0
@export_range(0.05, 0.4) var release_seconds := 0.16
@export var charge_sound: AudioStream
@export var release_sound: AudioStream
@export_range(0.0, 0.08) var cast_pitch_variation := 0.02
@export_range(0.0, 0.4) var projectile_core_scale := 0.0
@export_range(0.0, 0.5) var trail_seconds := 0.0
@export_range(0.005, 0.1) var trail_width := 0.03
@export_enum("Drops", "Threads") var trail_style: int = 0
@export_range(0.0, 0.8) var aftermath_seconds := 0.0
@export var aftermath_color := Color(1.0, 1.0, 1.0, 0.0)
