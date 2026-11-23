# Cracked — VECTOR VELOCITY

An endless 3D neon momentum runner built with Godot 4.7.2 for WebGL 2.

**Play:** https://unborne-fetus.github.io/Cracked/

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Steer across the track |
| Hold Shift, Ctrl, C, S or Down | Slide |
| Space | Jump |
| Tab | First-person / third-person |
| Escape | Pause / resume; return from Options |
| R | Restart |
| Controller left stick / A / B | Steer / jump / slide |
| Touch buttons | Steer, slide, jump, camera |

Sliding on flat or downhill track builds momentum rapidly and indefinitely, without a grip meter or fatigue. Flat acceleration is 8 m/s²; a 20% downhill grade adds 28 m/s² total. Air drag is reduced to preserve speed during jumps. Sliding trades lateral steering precision for speed. Sliding uphill still drains speed, but the braking force is gentler and the uphill coasting floor is higher. Steep climbs have shorter ascents and shallow downhill approaches. Faster movement produces higher jumps; jumping never adds forward speed. Running and jumping do not accelerate the player. There is no maximum speed. Obstacles take away 70% of current speed without ending the run. Jump over low barriers or steer around taller ones. The pursuing storm accelerates more aggressively; being caught ends the run. Tall route gates have alternating side openings that require steering rather than jumping. Air drag and brief landing recovery discourage repeated jumping.

## Pause and Options

Escape freezes the runner, storm, and clock. Resume continues the same run. Options lets you choose metric or imperial measurements, saved across sessions. Speed, distance, records, storm HUD and defeat summaries use the chosen units; simulation and saved records remain in SI units.

## Endless track

The course is generated in connected 192-meter sections. The standard track is 72 meters wide, narrows to 36 meters on bridges, and expands to 96 meters in wide basins. Partial-width sculpted ramps occupy alternating side lanes with a flat bypass. Both faces of the ribbon have physical running surfaces and luminous grids; land on either face, including the underside of a bank. Hills, sweeping turns, steeply banked corners, 180-degree half-roll banks with an upside-down stretch, and complete 360-degree barrel-roll banks are generated from continuous local frames; vertical loops are removed. A finely subdivided, thick ribbon reduces twisting artifacts. Track and obstacle colors gradually cycle over 12 kilometers of distance. Ten obstacle silhouettes include cones, columns, crystals, spheres, hurdles, arches, steps, hexagonal prisms, paired spires and blocks, with shape-aware collision and open passages. Ten additional terrain profiles include long descents, steep climbs, S curves, chicanes, narrow bridges, wide basins, rolling ridges, camber waves, banked descents, and drop-and-recovery sections. A seeded shuffle bag and varied terrain strengths prevent monotonous repetitions. Many technical sections leave the track clear so terrain itself is the challenge. The runner follows the track orientation only when grounded. Jumps, natural crest takeoffs, and running off an edge enter free world-space flight with the takeoff orientation, momentum, gravity and limited air steering. Landing requires crossing the actual running surface within its width. Physical contact is immediate, while body orientation and the camera arm ease into the grounded pose over half a second. The camera also eases from its exact pre-launch relative offset into the flight view over 0.45 seconds. Falling far below or outside the road ends the run. Natural takeoff uses longitudinal grade curvature, not bank twist; separation impulses are small and automatic launches are suppressed during extreme rolls. Manual jumps retain their speed scaling. Normal acceleration accounts for the changing track curvature, and harder landings cost momentum. The chase camera samples the actual trailing bank frame and shortens its arm if a sightline crosses the track; both camera modes damp rotation with quaternions, chase height is damped, and speed-dependent FOV is gentler. In flight, the camera follows the player's own orientation rather than the banking road. Track chunks are created ahead and removed behind; world coordinates are periodically rebased to keep precision stable. The storm follows arc-length progress instead of world X. Records track longest distance.

## Development

Open project.godot with Godot 4.7.2 and press F5. The Web export uses Compatibility rendering and single-threaded templates. GitHub Actions checks startup, ground contact, bank orientation, continuous track colors, shape variety, track seams, endless chunk recycling, momentum, obstacle and storm rules before deploying a unique versioned browser build to GitHub Pages.
