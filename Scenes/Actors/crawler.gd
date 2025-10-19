## crawler.gd
# Movement logic for the crawler using centralized grid logic
# Godot 4.4.1

extends Area2D

const GridUtil := preload("res://System/grid.gd")

@export var base_layer:   TileMapLayer
@export var wall_layer:   TileMapLayer
@export var hazard_layer: TileMapLayer
@export var marker_layer: TileMapLayer

# --- Movement Settings ---
@export var move_speed: float = 5.0  # Tiles per second

# --- Internal State ---
var _is_moving: bool = false
var _move_direction: Vector2 = Vector2.ZERO

# Simple input-skip slow (Sticky uses this to "eat" N inputs after entry)
var _skip_inputs: int = 0

func _ready() -> void:
    if base_layer == null: push_error("Crawler.base_layer not set")
    if wall_layer == null: push_error("Crawler.wall_layer not set")
    if hazard_layer == null: push_error("Crawler.hazard_layer not set")
    if marker_layer == null: push_error("Crawler.marker_layer not set")
    print("Crawler ready at ", position)

    var camera: Camera2D = get_node("Camera2D")
    if camera:
        camera.make_current()

    # Listen for global death to stop movement immediately
    if has_node("/root/HealthSystem"):
        var hs := get_node("/root/HealthSystem")
        if hs.has_signal("died"):
            hs.connect("died", Callable(self, "_on_global_death"))

func _get_tile_data(layer: TileMapLayer, coords: Vector2i) -> TileData:
    if layer.get_cell_source_id(coords) == -1:
        return null
    return layer.get_cell_tile_data(coords)

# --- Safe metadata readers (string/int/bool) ---
func _get_str(td: TileData, key: String, default_val: String = "") -> String:
    # Returns key as String if present & typed; otherwise default_val
    var v: Variant = td.get_custom_data(key)
    return (v as String) if (v is String) else default_val

func _get_int(td: TileData, key: String, default_val: int = 0) -> int:
    # Returns key as int if present & typed; otherwise default_val
    var v: Variant = td.get_custom_data(key)
    return (v as int) if (typeof(v) == TYPE_INT) else default_val

func _get_bool(td: TileData, key: String, default_val: bool = false) -> bool:
    # Returns key as bool if present & typed; otherwise default_val
    var v: Variant = td.get_custom_data(key)
    return (v as bool) if (v is bool) else default_val

#func _unhandled_input(event: InputEvent) -> void:
    ## --- 0) STICKY / SLOW GUARD ---
    ## If Sticky applied N slow "ticks", we ignore the next N inputs (ANY input: toggles or movement).
    #if _skip_inputs > 0:
        #_skip_inputs -= 1
        #print("[STICKY] Skipped one input. Remaining:", _skip_inputs)
        #return
    ## --- 1) ABILITY TOGGLES (ALWAYS ALLOWED) ---
    ## Pressing 1/2/3 uses your turn without moving. HUD updates via UpgradeController signals.
    #var upgrade_controller: Node = get_node_or_null("UpgradeController")
    #if upgrade_controller != null:
        ## 1 = Hardened Skin
        #if event.is_action_pressed("toggle_upgrade_1"):
            #upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.HARDENED_SKIN)
            #_consume_turn_no_move()   # Spend one turn for the toggle
            #return
        ## 2 = Acid Sac
        #if event.is_action_pressed("toggle_upgrade_2"):
            #upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.ACID_SAC)
            #_consume_turn_no_move()
            #return
        ## 3 = Ghost Trail
        #if event.is_action_pressed("toggle_upgrade_3"):
            #upgrade_controller.toggle_upgrade(upgrade_controller.Upgrade.GHOST_TRAIL)
            #_consume_turn_no_move()
            #return
#
    ## --- 2) BLOCK WHILE MOVING ---
    ## Prevent new inputs while the tween is running.
    #if _is_moving:
        #return
#
    ## --- 3) MOVEMENT INPUT ---
    ## Arrow/WASD mapped to move_* actions in the Input Map.
    #if event.is_action_pressed("move_up"):
        #_move_direction = Vector2.UP
    #elif event.is_action_pressed("move_down"):
        #_move_direction = Vector2.DOWN
    #elif event.is_action_pressed("move_left"):
        #_move_direction = Vector2.LEFT
    #elif event.is_action_pressed("move_right"):
        #_move_direction = Vector2.RIGHT
    #else:
        #return
#
    #_start_move()

func _unhandled_input(event: InputEvent) -> void:
    # --- 0) STICKY / SLOW GUARD ---
    if _skip_inputs > 0:
        _skip_inputs -= 1
        print("[STICKY] Skipped one input. Remaining:", _skip_inputs)
        return

    # --- 1) ABILITY TOGGLES (DEFERRED) ---
    # We only schedule a toggle; the actual toggle happens next idle frame.
    if event.is_action_pressed("toggle_upgrade_1"):
        _request_toggle(0)  # 0 = Hardened Skin
        return
    if event.is_action_pressed("toggle_upgrade_2"):
        _request_toggle(1)  # 1 = Acid Sac
        return
    if event.is_action_pressed("toggle_upgrade_3"):
        _request_toggle(2)  # 2 = Ghost Trail
        return

    # --- 2) BLOCK WHILE MOVING ---
    if _is_moving:
        return

    # --- 3) MOVEMENT INPUT ---
    if event.is_action_pressed("move_up"):
        _move_direction = Vector2.UP
    elif event.is_action_pressed("move_down"):
        _move_direction = Vector2.DOWN
    elif event.is_action_pressed("move_left"):
        _move_direction = Vector2.LEFT
    elif event.is_action_pressed("move_right"):
        _move_direction = Vector2.RIGHT
    else:
        return

    _start_move()


func _start_move() -> void:
    _is_moving = true

    # Safety guard – helpful during wiring
    if base_layer == null or wall_layer == null or hazard_layer == null or marker_layer == null:
        push_error("Crawler layers not assigned. Check ExploreMode exports & assignment.")
        _is_moving = false
        return

    # 1) Where are we trying to go?
    var current_tile: Vector2i = GridUtil.to_tile_coords(position)
    var next_tile: Vector2i = current_tile + Vector2i(_move_direction)

    # 2) Bounds check (use Base as the canonical footprint)
    var base_used: Rect2i = base_layer.get_used_rect()
    if not base_used.has_point(next_tile):
        print("[BLOCK] Outside map bounds →", next_tile)
        _is_moving = false
        return

    # 3) Must have Flesh (walkable) on Base
    var base_td := _get_tile_data(base_layer, next_tile)
    if base_td == null:
        print("[BLOCK] No Base tile at", next_tile, "(sticky sits on Hazard layer only)")
        _is_moving = false
        return

    var base_walkable: bool = _get_bool(base_td, "walkable", false)
    if base_walkable != true:
        print("[BLOCK] Base not walkable at", next_tile)
        _is_moving = false
        return

    # 4) Walls over Flesh can block (digestible is gated by Acid Sac)
    var wall_td := _get_tile_data(wall_layer, next_tile)
    if wall_td != null:
        var wall_walkable: bool = _get_bool(wall_td, "walkable", false) # usually false
        var wall_digestible: bool = _get_bool(wall_td, "digestible", false)
        var upgrades := get_node_or_null("UpgradeController")
        var acid_on: bool = false
        if upgrades != null:
            acid_on = upgrades.has_upgrade(upgrades.Upgrade.ACID_SAC)

        var can_pass_wall: bool = wall_walkable or (wall_digestible and acid_on)
        if not can_pass_wall:
            print("[BLOCK] Wall at", next_tile, "(digestible:", wall_digestible, " acid_on:", acid_on, ")")
            _is_moving = false
            return

    # 5) All checks passed → move
    print("[MOVE] From", current_tile, "to", next_tile)
    var target_pos: Vector2 = GridUtil.to_world(next_tile)
    var tween: Tween = create_tween()
    tween.tween_property(self, "position", target_pos, 1.0 / move_speed)
    # When we arrive, resolve tile effects, then re-enable input
    tween.finished.connect(func():
        _on_arrived_at(next_tile)
    )

func _on_arrived_at(tile: Vector2i) -> void:
    # We have arrived: unlock input by default.
    # If we win during effects, _win_and_return() will set _is_moving = true again.
    _is_moving = false
    print("[ARRIVE] At tile:", tile)

    # Apply end-of-action effects (acid, sticky, dissolve, goal).
    _apply_tile_effects(tile)
    # Nothing else to do here. If not winning, we remain unlocked for the next input.

func _win_and_return() -> void:
    _is_moving = true
    print("🏆 Reached Heartroot — WIN!")
    if has_node("/root/CoilSession"):
        get_node("/root/CoilSession").call("end_coil")
    else:
        get_tree().change_scene_to_file("res://Scenes/BuilderMode/BuilderMode.tscn")

# Increments the number of movement inputs to ignore (used by Sticky slow)
func _consume_future_inputs(n: int) -> void:
    _skip_inputs += n

# Use up one turn without moving (ability activation time budget).
# Also applies end-of-action tile effects at the current position (acid, sticky, etc.).
#func _consume_turn_no_move() -> void:
    #_is_moving = true
#
    ## Apply tile effects where we stand, since a turn passes.
    #var current_tile: Vector2i = GridUtil.to_tile_coords(position)
    #_apply_tile_effects(current_tile)
#
    ## If we won due to standing on goal (edge case), _apply_tile_effects() already called _win_and_return().
    #if _is_moving:
        ## _is_moving remains true during win transition.
        #return
#
    ## Wait the same duration as a normal step so pacing is consistent.
    #var step_duration: float = 1.0 / move_speed
    #var t: Tween = create_tween()
    #t.tween_interval(step_duration)
    #t.finished.connect(func() -> void:
        #_is_moving = false
    #)

# Use up one turn without moving (ability activation time budget).
# Also applies end-of-action tile effects at the current position (acid, sticky, etc.).
func _consume_turn_no_move() -> void:
    # Lock input for the duration of this "turn"
    _is_moving = true

    # 1) Apply tile effects where we stand, since a turn passes.
    var current_tile: Vector2i = GridUtil.to_tile_coords(position)
    _apply_tile_effects(current_tile)

    # 2) If we won during effects, the scene transition will take over.
    #    We still create a tiny tween safely; if the scene changes, it won't matter.
    var step_duration: float = 1.0 / move_speed

    # 3) Wait exactly one step duration, then unlock input.
    var t: Tween = create_tween()
    t.tween_interval(step_duration)
    t.finished.connect(func() -> void:
        # Only unlock if we are still in this scene and not transitioning.
        # (If _win_and_return() ran, we typically won't get here in the same scene.)
        if is_inside_tree():
            _is_moving = false
    )


## Apply all end-of-action effects for the given tile.
## This is called after a MOVE (on arrival) and after a NO-MOVE TURN (e.g., ability toggle).
func _apply_tile_effects(tile: Vector2i) -> void:
    # 1) Hazards
    var hazard_td := _get_tile_data(hazard_layer, tile)
    if hazard_td != null:
        var hazard: String = _get_str(hazard_td, "hazard", "")

        if hazard == "acid":
            var dmg: int = _get_int(hazard_td, "damage_per_step", 0)

            # Hardened Skin mitigation
            var upgrades: Node = get_node_or_null("UpgradeController")
            var hardened_on: bool = false
            if upgrades != null:
                hardened_on = upgrades.has_upgrade(upgrades.Upgrade.HARDENED_SKIN)

            if hardened_on:
                dmg = dmg - 1
                if dmg < 0:
                    dmg = 0

            if dmg > 0 and has_node("/root/HealthSystem"):
                var hs: Node = get_node("/root/HealthSystem")
                print("[ACID] Tile:", tile, "damage:", dmg)
                hs.call("apply_damage", dmg, "acid")

        elif hazard == "sticky":
            var slow_ticks: int = _get_int(hazard_td, "slow_ticks", 0)
            if slow_ticks > 0:
                print("[STICKY] Entered", tile, "→ will skip", slow_ticks, "future inputs")
                _consume_future_inputs(slow_ticks)

    # 2) Dissolve digestible wall on entry/stand if Acid Sac is active
    var wall_td := _get_tile_data(wall_layer, tile)
    if wall_td != null and _is_digest_wall(wall_td):
        var upgrades2: Node = get_node_or_null("UpgradeController")
        var acid_on: bool = false
        if upgrades2 != null:
            acid_on = upgrades2.has_upgrade(upgrades2.Upgrade.ACID_SAC)
        if acid_on:
            # IMPORTANT: Defer TileMap mutation to avoid re-entrancy/framing issues.
            print("[DIGEST] Erasing wall at", tile, "(deferred)")
            wall_layer.call_deferred("erase_cell", tile)

    # 3) Goal check (do this last; it may trigger a scene change)
    var marker_td := _get_tile_data(marker_layer, tile)
    if marker_td != null:
        var reached_goal: bool = _get_bool(marker_td, "is_goal", false)
        if reached_goal:
            print("[GOAL] Reached at", tile)
            _win_and_return()

func _is_digest_wall(td: TileData) -> bool:
    if td == null:
        return false
    # Primary: explicit boolean
    if _get_bool(td, "digestible", false):
        return true
    # Fallback: string kind
    var kind := _get_str(td, "wall_kind", "")
    return kind == "DIGEST" or kind == "DIGESTIBLE"

# Pending toggle index; -1 means none queued.
var _pending_toggle: int = -1

# Queue a toggle to run on the next idle frame. Avoids re-entrancy inside input callbacks.
func _request_toggle(index: int) -> void:
    # Ignore if we are already moving or a toggle is already queued.
    if _is_moving:
        print("[TOGGLE] Ignored; currently moving.")
        return
    if _pending_toggle != -1:
        print("[TOGGLE] Ignored; a toggle is already queued.")
        return

    _pending_toggle = index
    call_deferred("_apply_pending_toggle")
    print("[TOGGLE] Queued index:", index)

# Runs on idle; performs the toggle and consumes one turn without moving.
func _apply_pending_toggle() -> void:
    var index: int = _pending_toggle
    _pending_toggle = -1

    var uc: Node = get_node_or_null("UpgradeController")
    if uc == null:
        print("[TOGGLE] UpgradeController not found; abort.")
        return

    # Map index → enum explicitly (no inferred Variants).
    if index == 0:
        print("[TOGGLE] Hardened Skin")
        uc.call("toggle_upgrade", uc.Upgrade.HARDENED_SKIN)
    elif index == 1:
        print("[TOGGLE] Acid Sac")
        uc.call("toggle_upgrade", uc.Upgrade.ACID_SAC)
    elif index == 2:
        print("[TOGGLE] Ghost Trail")
        uc.call("toggle_upgrade", uc.Upgrade.GHOST_TRAIL)
    else:
        print("[TOGGLE] Unknown index:", index)
        return

    # Spend a turn and apply end-of-action effects on our current tile (acid, sticky, etc.).
    _consume_turn_no_move()

func _on_global_death() -> void:
    # Disable new inputs and movement
    _is_moving = true
    _skip_inputs = 999999  # large number so accidental inputs are effectively ignored

## end crawler.gd
