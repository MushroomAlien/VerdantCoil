## build_info.gd

extends Node

@export var major: int = 0
@export var minor: int = 1
@export var patch: int = 5
@export var include_build_date: bool = true
@export var tag: String = ""   # e.g. "a" / "b"

func version_string() -> String:
    var core := "%d.%d.%d" % [major, minor, patch]
    if include_build_date:
        core += "." + _yymmdd_today()
    if tag.strip_edges() != "":
        core += tag
    return core

func _yymmdd_today() -> String:
    var dt := Time.get_datetime_dict_from_system(false)
    var yy := int(dt["year"]) % 100
    var mm := int(dt["month"])
    var dd := int(dt["day"])
    return "%02d%02d%02d" % [yy, mm, dd]

## end build_info.gd
