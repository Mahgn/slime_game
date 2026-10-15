extends SlimeController
class_name SlimeDungeonPlayer

const DUNGEON_ABILITIES: Array[StringName] = [&"sticky_spit", &"acid_spit"]
var _rank_definitions: Dictionary = {}
var _sticky_seconds: float = 0.0
var _sticky_speed: float = 1.0
var water_flow: Vector3 = Vector3.ZERO


func get_known_abilities() -> Array[StringName]:
	return DUNGEON_ABILITIES


func can_absorb_ability(ability_id: StringName) -> bool:
	return DUNGEON_ABILITIES.has(ability_id)


func get_ability_level(ability_id: StringName) -> int:
	return int(learned_abilities.get(ability_id, 0))


func grant_ability(ability_id: StringName) -> bool:
	if not can_absorb_ability(ability_id):
		return false
	learned_abilities[ability_id] = get_ability_level(ability_id) + 1
	_rank_definitions.erase(ability_id)
	var already_equipped: bool = get_slot_ability(1)==ability_id or get_slot_ability(2)==ability_id
	if not already_equipped and equipped_ability == &"":
		equipped_ability = ability_id
	elif not already_equipped and unlocked_slots >= 2 and second_slot_ability == &"":
		second_slot_ability = ability_id
	ability_unlocked.emit(ability_id)
	loadout_changed.emit()
	return true


func get_ability_definition(ability_id: StringName) -> AbilityDefinition:
	if not DUNGEON_ABILITIES.has(ability_id):
		return super.get_ability_definition(ability_id)
	if _rank_definitions.has(ability_id):
		return _rank_definitions[ability_id] as AbilityDefinition
	var definition: AbilityDefinition
	if ability_id == &"sticky_spit":
		# Rank values are local; immutable impact/audio Resources stay shared.
		definition = ABILITY.duplicate(false) as AbilityDefinition
		definition.description = "Замедляет врага. Удерживает открытый привод в текущем положении."
	else:
		definition = AbilityDefinition.new()
		definition.ability_id = &"acid_spit"
		definition.display_name = "Кислотный плевок"
		definition.description = "Разъедает органическую перепонку и повреждает врага."
		definition.player_damage = 18
		definition.player_cooldown = 2.8
		definition.player_projectile_speed = 14.0
		definition.player_projectile_range = 18.0
		definition.slow_factor = 1.0
		definition.slow_seconds = 0.0
	definition.impact_profile = SlimeImpactProfiles.for_ability(ability_id)
	var rank: int = maxi(1, get_ability_level(ability_id))
	definition.player_damage += 3 * (rank - 1)
	if ability_id == &"sticky_spit":
		definition.slow_seconds += 0.5 * float(rank - 1)
	_rank_definitions[ability_id] = definition
	return definition


func apply_sticky(factor: float, seconds: float) -> void:
	if seconds <= 0.0 or not is_alive():
		return
	_sticky_seconds = maxf(_sticky_seconds, seconds)
	_sticky_speed = clampf(factor, 0.3, 1.0)


func _physics_process(delta: float) -> void:
	_sticky_seconds = maxf(0.0, _sticky_seconds - delta)
	if _sticky_seconds <= 0.0:
		_sticky_speed = 1.0
	super._physics_process(delta)


func _update_horizontal_velocity(target: Vector3, axes: Vector2, grounded: bool, delta: float) -> void:
	super._update_horizontal_velocity(target * _sticky_speed + water_flow, axes, grounded, delta)
