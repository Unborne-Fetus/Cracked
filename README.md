# Cracked — VECTOR VELOCITY

An endless 3D neon momentum runner built with Godot 4.7.2 for WebGL 2.

**Play:** https://unborne-fetus.github.io/Cracked/

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Steer across the track |
| Hold Shift, Ctrl, C, S or Down | Slide |
| Space | Jump; press again for one midair jump |
| F (hold in air) | Dive |
| Tab | First-person / third-person |
| Escape | Pause / resume; return from Options |
| R | Restart |
| Controller left stick / D-pad | Steer; navigate menus |
| A / Cross | Jump / double jump; select; retry after defeat |
| R3 (right stick click, hold) | Dive |
| B / Circle, either shoulder or trigger | Hold to slide; B backs out of menu |
| Y / Triangle | Switch camera |
| X / Square | Restart |
| Start / Options | Pause / resume |
| Left / right in Options | Switch units |
| Touch buttons | Steer, slide, jump, camera |

Sliding on flat or downhill track builds momentum rapidly and indefinitely, without a grip meter or fatigue. Flat acceleration is 8 m/s²; a 20% downhill grade adds 28 m/s² total. Air drag is reduced to preserve speed during jumps. Sliding trades lateral steering precision for speed. Sliding uphill still drains speed, but the braking force is gentler and the uphill coasting floor is higher. Steep climbs have shorter ascents and shallow downhill approaches. Faster movement produces higher jumps; jumping never adds forward speed. Running and jumping do not accelerate the player. There is no maximum speed. Obstacles take away 70% of current speed without ending the run. Jump over low barriers or steer around taller ones. The pursuing storm starts at 14 m/s, accelerates at 1.05 m/s² initially, and increases its acceleration by 0.012 m/s³ as the run progresses; being caught ends the run. Tall route gates have alternating side openings that require steering rather than jumping. Air drag and brief landing recovery discourage repeated jumping.

## Momentum tools

Clean sliding earns a reserve (up to 30 m/s of stored speed) that automatically absorbs uphill braking, without protecting against obstacle impacts. A clean gate gives 4 m/s while sliding or adds 4 m/s to the reserve otherwise; each gate rewards once. One extra jump is available per airborne period. Hold F or R3 in flight to dive downward, with no forward-speed injection. Blue side channels bypass major hills and ridges with gentler grades; green recovery lanes remain separate. The top-right hypsometric minimap shows the actual forward course, with blue for lower terrain, green for near-level, yellow/red for higher terrain, white shortcut markers, and green recovery markers.

## Pause and Options

Escape freezes the runner, storm, and clock. Resume continues the same run. Options lets you choose metric or imperial measurements, saved across sessions. Speed, distance, records, storm HUD and defeat summaries use the chosen units; simulation and saved records remain in SI units.

## Endless track

The course is generated in connected sections of at least 192 meters. Newly generated banks stretch with the player's current speed (up to eight times their usual length) while preserving their full rotation and existing geometry. The standard track is 120 meters wide, narrows to 60 meters on bridges, and expands to 156 meters in wide basins. First-person sliding lowers the eye height smoothly and displays a distinct cyan SLIDING indicator. Partial-width sculpted ramps occupy alternating side lanes with a flat bypass. Both faces of the ribbon have physical running surfaces and luminous grids; land on either face, including the underside of a bank. Hills, sweeping turns, steeply banked corners, 180-degree half-roll banks with an upside-down stretch, and complete 360-degree barrel-roll banks are generated from continuous local frames; vertical loops are removed. Sustained wall runs and ceiling runs use three connected chunks: a smooth entrance, a 192-meter straight held exactly at 90 or 180 degrees, and a smooth exit. The entry and exit use the entire 192-meter chunk to ease into and out of the sustained orientation, and walls can tilt in either direction. All extreme banks use smoothly ramped angular velocity with a lower peak rotation rate; ordinary corner banks have gentler tilt. These sections recur in the seeded terrain shuffle. A finely subdivided, thick ribbon reduces twisting artifacts. Track and obstacle colors gradually cycle over 12 kilometers of distance. Ten obstacle silhouettes include cones, columns, crystals, spheres, hurdles, arches, steps, hexagonal prisms, paired spires and blocks, with shape-aware collision and open passages. Ten additional terrain profiles include long descents, steep climbs, S curves, chicanes, narrow bridges, wide basins, rolling ridges, camber waves, banked descents, and drop-and-recovery sections. A seeded shuffle bag and varied terrain strengths prevent monotonous repetitions. Many technical sections leave the track clear so terrain itself is the challenge. The runner follows the track orientation only when grounded. Jumps, natural crest takeoffs, and running off an edge enter free world-space flight with the takeoff orientation, momentum, gravity and limited air steering. Landing requires crossing the actual running surface within its width. Physical contact is immediate, while body orientation and the camera arm ease into the grounded pose over half a second. The camera also eases from its exact pre-launch relative offset into the flight view over 0.45 seconds. Falling far below or outside the road ends the run. Natural takeoff uses longitudinal grade curvature, not bank twist; separation impulses are small and automatic launches are suppressed during extreme rolls. Manual jumps retain their speed scaling. Normal acceleration accounts for the changing track curvature, and harder landings cost momentum. The chase camera samples the actual trailing bank frame and shortens its arm if a sightline crosses the track; both camera modes damp rotation with quaternions, chase height is damped, and speed-dependent FOV is gentler. The camera preserves a world-level horizon in both perspectives, on the road and in flight, so sideways and inverted sections remain visually distinct. Camera position still follows the correct face. A/D uses screen-relative steering on horizontal faces, with a stable mapping and slight downhill drift on walls. Airborne torso and visor volumes sweep against both faces and deflect head-first impacts instead of allowing the player to clip through the slab. Track chunks are created ahead and removed behind; world coordinates are periodically rebased to keep precision stable. The storm follows arc-length progress instead of world X. Records track longest distance.

## Route expansion

Split routes open a real central gap and reconnect. Gap crossings have a jumpable opening and an intact alternate lane. Corkscrew tunnels curl the road around its longitudinal axis; halfpipes have rideable curved walls. Stacked routes overlap an elevated deck and lower deck. Purple slipstreams follow a curving lane and accelerate players who stay inside the current. Five distance-based terrain biomes change the palette and HUD label. Perfect landings preserve momentum and grant a small reserve reward. Downhill landings convert actual downward velocity into forward motion; controlled dives onto a descent earn a bounded bonus. The minimap omits unsupported sections.

## Fair procedural routes

The generator previews several reachable lanes using the same sliding acceleration and storm progression as gameplay. It forecasts the already-generated lookahead from the live runner and storm, and evaluates new terrain before committing its geometry. After the introductory showcase, it removes unsafe obstacle layouts and substitutes clear downhill recovery terrain when the forecast is poor. Demanding terrain sequences trigger recovery runs. The preview is a conservative grounded model, not a guarantee against every possible player mistake or airborne trajectory.

Major climbs have a sculpted side bypass with a gentler central grade. Green recovery strips on climbs and descents provide up to 18 m/s² extra acceleration only while grounded and sliding on the top face. Recovery runs and demanding hills are clear of obstacles; ordinary late-run obstacles respect speed-dependent spacing, avoid blind crests, and leave a broad clear corridor. The storm is never artificially slowed by the validator.

## Versions

Browser releases display a readable version number, `V. 0.x`, in the game and browser title. The minor number follows the GitHub Actions workflow run number; failed builds may leave gaps. Unique internal release paths still prevent stale cached engine files.

## Development

Open project.godot with Godot 4.7.2 and press F5. The Web export uses Compatibility rendering and single-threaded templates. GitHub Actions checks startup, ground contact, bank orientation, continuous track colors, shape variety, track seams, endless chunk recycling, momentum, obstacle and storm rules before deploying a unique versioned browser build to GitHub Pages.
