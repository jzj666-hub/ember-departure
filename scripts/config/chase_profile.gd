class_name ChaseProfile
extends Resource
## Difficulty knobs for one chase encounter. Shared by chase_mode / chase_game / chase_multiplayer.
## Authored as .tres under config/chase/. Defaults reproduce the original hard-coded values,
## so an empty .tres changes nothing.

## Seconds the runner gets to escape before the pursuer is released.
@export_range(1.0, 120.0, 0.5) var escape_countdown := 15.0
## Seconds the runner must survive to win.
@export_range(10.0, 900.0, 1.0) var chase_time_limit := 120.0
## Pursuer repath period while runner is on the same platform (tight tracking).
@export_range(0.01, 1.0, 0.01) var fast_repath_interval := 0.06
## Pursuer repath period otherwise.
@export_range(0.01, 2.0, 0.01) var slow_repath_interval := 0.25
## Seconds of stale position the pursuer chases after losing line of sight.
@export_range(0.0, 3.0, 0.01) var los_delay_seconds := 0.20
## Horizontal distance at which the pursuer catches the runner, in metres.
@export_range(0.2, 10.0, 0.1) var catch_distance := 1.5
