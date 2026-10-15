extends RefCounted
class_name SlimeImpactProfiles

# Defaults for existing attacks. New AbilityDefinitions can supply a Resource
# directly, without adding a renderer branch or a new entry to this table.
const GENERIC: SlimeImpactProfile = preload("res://data/combat/impact_profiles/generic.tres")
const WHIP: SlimeImpactProfile = preload("res://data/combat/impact_profiles/whip.tres")
const ACID: SlimeImpactProfile = preload("res://data/combat/impact_profiles/acid.tres")
const WEB: SlimeImpactProfile = preload("res://data/combat/impact_profiles/web.tres")
const SPIKES: SlimeImpactProfile = preload("res://data/combat/impact_profiles/spikes.tres")
const SHELL: SlimeImpactProfile = preload("res://data/combat/impact_profiles/shell.tres")

static func for_ability(ability_id: StringName) -> SlimeImpactProfile:
	match ability_id:
		&"slime_whip": return WHIP
		&"acid_spit": return ACID
		&"sticky_spit": return WEB
		&"slime_spikes": return SPIKES
		&"elastic_shell": return SHELL
		_: return GENERIC
