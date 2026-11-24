# Cracked — VECTOR VELOCITY

An endless 3D neon momentum runner built with Godot 4.7.2 for WebGL 2.

**Play:** https://unborne-fetus.github.io/Cracked/

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Turn and carve the board |
| Hold Shift, Ctrl, C, S or Down | Slide |
| Space | Jump; press again for one midair jump |
| F (hold in air) | Dive |
| Tab | First-person / third-person |
| G | Recenter the current camera (remappable) |
| L3 / left stick click | Recenter the current camera (remappable) |
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

## Run modes and profile

Pause > Run & Profile opens daily seeded runs (UTC date, deterministic layout), no-jump, first-person, fast-storm and storm-free practice challenges. Competitive local records are separated by mode and daily date; practice never posts records or unlocks achievements. Eight achievements are retained; cosmetic selection is deferred while the new monochrome rider set is in use. The post-run summary records top speed, airtime, sliding time and momentum loss. Keyboard and gamepad button bindings can be changed and reset in the same menu. Analog steering and trigger slide remain available. The original 64-bar drum-and-bass score uses a pre-mixed browser-native audio sample; speed streaks and controller impact/landing vibration can be disabled.

Online daily score submission is supported through a configured `velocity/leaderboard_url` project setting. The server implementation is provided separately and must be deployed before public ranking works. Client scores are unverified; never treat them as cheat-proof.

## Replays

Completed runs automatically save a local replay of their actual motion and generated track, including adaptive geometry, obstacles, storm position and origin rebases. Choose Watch Replay after defeat or Watch Last Replay from Run & Profile. Playback offers pause, a timeline, five-second skips, 0.5x/1x/2x speeds and either camera perspective. Space/A plays or pauses; left/right seeks, Tab/Y switches view, Up changes speed, and Escape/B exits to a new run. Playback does not simulate or submit scores. The recording is bounded to roughly 30 minutes or 768 generated chunks, whichever is reached first, and displays a recording-limit notice if truncated. Only the most recent completed replay is retained locally.

Bank flight collision uses short swept substeps and relative signed surface crossings so a twisting road cannot be ignored merely because the player's world-space velocity points away from its final normal.

## Momentum tools

Clean sliding earns a reserve (up to 30 m/s of stored speed) that automatically absorbs uphill braking, without protecting against obstacle impacts. A clean gate gives 4 m/s while sliding or adds 4 m/s to the reserve otherwise; each gate rewards once. One extra jump is available per airborne period. Hold F or R3 in flight to dive downward, with no forward-speed injection. Blue side channels bypass major hills and ridges with gentler grades; green recovery lanes remain separate. The optional hypsometric minimap implementation (hidden in the minimal HUD) shows the actual forward course, with blue for lower terrain, green for near-level, yellow/red for higher terrain, white shortcut markers, and green recovery markers.

## Pause and Options

Escape freezes the runner, storm, and clock. Resume continues the same run. Options lets you choose metric or imperial measurements, saved across sessions. Speed, distance, records, storm HUD and defeat summaries use the chosen units; simulation and saved records remain in SI units.

## Endless track

The course is generated in connected sections of at least 192 meters. Newly generated banks stretch with the player's current speed (up to eight times their usual length) while preserving their full rotation and existing geometry. The standard track is 120 meters wide, narrows to 60 meters on bridges, and expands to 156 meters in wide basins. First-person sliding lowers the eye height smoothly without extra HUD text. Partial-width sculpted ramps occupy alternating side lanes with a flat bypass. Both faces of the ribbon have physical running surfaces and luminous grids; land on either face, including the underside of a bank. Hills, sweeping turns, steeply banked corners, 180-degree half-roll banks with an upside-down stretch, and complete 360-degree barrel-roll banks are generated from continuous local frames; optional vertical loop branches provide a safe bypass. Sustained wall runs and ceiling runs use three connected chunks: a smooth entrance, a 192-meter straight held exactly at 90 or 180 degrees, and a smooth exit. The entry and exit use the entire 192-meter chunk to ease into and out of the sustained orientation, and walls can tilt in either direction. All extreme banks use smoothly ramped angular velocity with a lower peak rotation rate; ordinary corner banks have gentler tilt. These sections recur in the seeded terrain shuffle. A finely subdivided, thick ribbon reduces twisting artifacts. Track and obstacle colors gradually cycle over 12 kilometers of distance. Ten obstacle silhouettes include cones, columns, crystals, spheres, hurdles, arches, steps, hexagonal prisms, paired spires and blocks, with shape-aware collision and open passages. Ten additional terrain profiles include long descents, steep climbs, S curves, chicanes, narrow bridges, wide basins, rolling ridges, camber waves, banked descents, and drop-and-recovery sections. A seeded shuffle bag and varied terrain strengths prevent monotonous repetitions. Many technical sections leave the track clear so terrain itself is the challenge. The runner follows the track orientation only when grounded. Jumps, natural crest takeoffs, and running off an edge enter free world-space flight with the takeoff orientation, momentum, gravity and limited air steering. Landing requires crossing the actual running surface within its width. Physical contact is immediate, while body orientation and the camera arm ease into the grounded pose over half a second. The camera also eases from its exact pre-launch relative offset into the flight view over 0.45 seconds. Falling far below or outside the road ends the run. In curled and stacked sections, fall detection measures proximity to the actual rideable faces instead of the centerline, preventing false falls inside corkscrew tunnels. Natural takeoff uses longitudinal grade curvature, not bank twist; separation impulses are small and automatic launches are suppressed during extreme rolls. Manual jumps retain their speed scaling. Normal acceleration accounts for the changing track curvature, and harder landings cost momentum. The chase camera samples the actual trailing bank frame and shortens its arm if a sightline crosses the track; both camera modes damp rotation with quaternions, chase height is damped, and speed-dependent FOV is gentler. The camera preserves a world-level horizon in both perspectives, on the road and in flight, so sideways and inverted sections remain visually distinct. Camera position still follows the correct face. A/D uses screen-relative steering on horizontal faces, with a stable mapping and slight downhill drift on walls. Airborne torso and visor volumes sweep against both faces and deflect head-first impacts instead of allowing the player to clip through the slab. Track chunks are created ahead and removed behind; world coordinates are periodically rebased to keep precision stable. The storm follows arc-length progress instead of world X. Records track longest distance.

## Route expansion

Split routes open a real central gap and reconnect. Gap crossings have a jumpable opening and an intact alternate lane. Corkscrew tunnels curl the road around its longitudinal axis; halfpipes have rideable curved walls. Stacked routes overlap an elevated deck and lower deck. Purple slipstreams follow a curving lane and accelerate players who stay inside the current. Five distance-based terrain biomes change the palette and HUD label. Perfect landings preserve momentum and grant a small reserve reward. Downhill landings convert actual downward velocity into forward motion; controlled dives onto a descent earn a bounded bonus. The minimap omits unsupported sections.

## Fair procedural routes

The generator previews several reachable lanes using the same sliding acceleration and storm progression as gameplay. It forecasts the already-generated lookahead from the live runner and storm, and evaluates new terrain before committing its geometry. From the first live section, it removes unsafe obstacle layouts and attempts varied clear downhill terrain when the forecast is poor. The old fixed opening is now only a regression-test fixture. Live courses choose seeded opening terrain, randomized section order, lengths, grades and obstacle timing; daily seeds reproduce the same choices. Demanding terrain sequences trigger recovery runs. The preview is a conservative grounded model, not a guarantee against every possible player mistake or airborne trajectory.

Major climbs have a sculpted side bypass with a gentler central grade. Green recovery strips on climbs and descents provide up to 18 m/s² extra acceleration only while grounded and sliding on the top face. Recovery runs and demanding hills are clear of obstacles; ordinary late-run obstacles respect speed-dependent spacing, avoid blind crests, and leave a broad clear corridor. The storm is never artificially slowed by the validator.

## Versions

Browser releases display a readable version number, `V. 0.x`, in the game and browser title. The minor number follows the GitHub Actions workflow run number; failed builds may leave gaps. Unique internal release paths still prevent stale cached engine files.

## Soundtrack

"Through the Neon" is an original 160 BPM drum-and-bass racing score, with a 96-second arrangement, a single pre-mixed stereo loop, contrasting breakdowns, chord changes and a melodic hook. The browser uses native Web Audio sample playback and smooth speed-dependent volume changes to reduce crackling. All sounds are synthesized offline from the included composition; no third-party recordings are used. CI renders and checks the Vorbis assets before importing Godot. For a local editor build, install NumPy and FFmpeg and run `python tools/render_soundtrack.py` before opening the project. The existing soundtrack toggle still works.

## Development

Open project.godot with Godot 4.7.2 and press F5. The Web export uses Compatibility rendering and single-threaded templates. GitHub Actions checks startup, ground contact, bank orientation, continuous track colors, shape variety, track seams, endless chunk recycling, momentum, obstacle and storm rules before deploying a unique versioned browser build to GitHub Pages.

CI caches the deterministic soundtrack, frees recycled track meshes between regression-test phases, and sets bounded test/deployment timeouts. A pending commit status links to the running build from the beginning of the job.

The player uses three white, 36×32 hoverboard sprite poses derived from the approved pixel-silhouette concept. Nearest-neighbor filtering preserves hard pixel edges, and the sprite turns toward the camera around the actual bank-relative up axis. Cruise, carve and speed/dive poses respond to movement; first-person hides the sprite. Collision, movement, profile unlock data and replay physics are unchanged.

Camera: hold right mouse and drag, use controller right stick, or drag an unoccupied touch area to orbit/look freely; scroll wheel adjusts chase zoom. G / L3 / CENTER restores default framing. The white rider has rear-facing poses and separate side profiles for orbit views. The circular elevation radar clips all terrain to its round boundary and uses faster surface-position sampling. Branch sections are deliberately prioritized every few ordinary chunks, subject to route validation. Mesh generation reuses cross-section vertices and colors without reducing collision resolution.

Music is a continuous 148 BPM melodic electronic loop, with softer percussion, sustained chord transitions and a warm lead. The browser uses a single native HTML audio element, started once on a browser gesture; gameplay input, death, retry and pause never restart or pause it. Mute fades independently. The player uses slim rear three-quarter pixel silhouettes with original side art and uncompressed crouch poses. Ground contact immediately realigns the board and physical rider; free flight from curved walls gradually recovers upright roll.

Forks now spread outward by up to 48m per deck, and crossover sections use full-length eased approach and exit geometry. Live obstacle rows contain staggered groups, with a reserved route and fallback thinning, and use complementary-color dark grid materials. The soundtrack is a 96-bar 170 BPM composition with contrasting driving and breakdown sections; pause resumes at the same timestamp while retry does not interrupt playback. Rear sprites are revised three-quarter silhouettes, and the original side poses are retained.

The new default chase art is centered, truly rear-facing, with a separate 3D hoverboard. Original profile sprites remain for side-on camera views. Manual jumps and double jumps animate a 0.42-second board-only kickflip, recorded in replays; landing resets the board and physics is unaffected. REDLINE FRACTURE is an original 190 BPM industrial breakcore/metal soundtrack with ten changing sections, synthesized distorted power chords, double-kick patterns and chopped drum breaks. No external music or samples are used.

The rider now uses articulated block geometry rather than billboards. White limbs and a dark cyan-edged bobsled-style deck have a separate board flip pivot. Ground recovery handles shallow sideways floor contact before repeated body deflection, without permitting underside snapping or head-first ceiling attachment. TERMINAL VELOCITY revises the industrial soundtrack with simulated guitar cabinet filtering, stronger rhythmic transients, expanded harmonic sections and softer final limiting.

The articulated rider is taller, with longer limbs and a higher neutral stance. Two-bone limb posing animates front-foot flick, rear-foot lift, knee tuck, board catch, landing compression, speed crouch, steering balance, free-flight/diving and obstacle recoil. Animation timing is simulated and saved in replays; deck size, collision bounds and movement rules are unchanged.

Fall detection now uses nearby supported road geometry and a short confirmed escape interval rather than an airtime timeout. Solid obstacle sweeps stop the board at the first contact and reflect its motion even after the obstacle has been hit. The taller model has an upturned tail, terrain-sampled board clearance, and an animated nose-down diving pose with swept-back arms. AFTERIMAGE revises the soundtrack toward lower-register dark drum-and-bass, reduced piercing highs, and less constant lead/guitar layering.

Split routes now have contrasting terrain: a narrow high rolling ridge and broad low banked channel, plus a rolling upper flyover and a lower bowl on stacked routes. Geometry, normals, projection and forecast all use these independent branch profiles. Air idle tricks cycle through a shifty, a grab and a one-foot extension; diving, landing and impact override tricks. Bank compensation, landing brace and gate flourishes are replay-recorded visual states. NIGHT CIRCUIT is a new 174 BPM original soundtrack built around longer harmonic progressions, a recurring theme, separate drops and a bridge, with distorted guitar used only for accents.

**Changelog:** [Latest changes](https://unborne-fetus.github.io/Cracked/changelog.html) ([repository history](CHANGELOG.md)). Open Pause → Options → Changelog. Forks use visible gold inner-edge guidance, and heading-based steering rotates the physical rider and momentum vector. Air tricks cycle across nine variants; ground idles and inverted braces are visual-only and replayed.

First-person mode renders the animated legs, boots and hoverboard; upper body is hidden. A procedural twilight skybox includes stars, aurora, sunset and distant ridgelines. Camera orbit and chase arm are damped with surface checks. Q/E drift left/right independently of A/D carving (remappable). 24 air tricks and six ground idle variants are replay-recorded.

Optional left loop branches have a safe right bypass; complete the inverted loop without detaching for +24 m/s and 12 reserve. The camera follows track heading rather than board steering. Inverted riders deploy two handles and hang below the board; model joints blend across visual transitions.

Combat is removed from all modes to focus testing on movement and track geometry. Normal obstacle contact still reduces momentum. First-person camera moved forward and look direction is screen-relative even inverted. Grounded riders automatically recover from stalling, and shallow bank contact can settle onto the correct face.

Wall/ceiling sections recur more frequently. The fullpipe closes and wraps at the crown; low-speed traction suppresses sideways drift. High-altitude glider wings and hanging pose are visual only and replayed. The synthwave sky grows more intense with speed; high-speed chunk length and reduced redundant probes target performance.

The skyline's mountain height grows and oscillates with progress. Contact-only ceiling treads and a rotating sidewall gyro wheel are independent of airborne glider wings. Rideable walls and ceilings can magnetically reorient a rider on swept contact. Glider double jumps and periodic tricks rotate the whole rig; returning to the deck uses a timed release, transfer, catch and wing fold. All glider animation phases are captured in replay frames.

The ceiling form now uses eight articulated spider legs. Glider wings have two jet nacelles, eight idle trick variants, and a world-upright visual mount independent of gyro roll. Gyro form has six visual tricks. First-person special forms use clear cockpit framing rather than obstructing wheel and wing geometry. Storm catch confirmation requires sustained proximity and rejects high airborne projection errors; replays retain the defeat reason.

Gyro deployment now articulates 24 fixed-size curved rim panels from rail cassettes into the wheel instead of scaling a torus. Reverse motion folds them into the deck; wing deployment is gated by clearance. Folded leg rotation and final camera clearance are guarded against invalid transforms and bank intersections.

Replay speed cycles through 0.5x, 1x and 2x using numeric state. Restored cosmetic selection in Options, with the original achievement unlocks and colors shared across transformations. Spider feet now extend 4.25 m to either side. Glider return includes a distinct separated free-fall interval, swoop underneath, catch and wing fold; this visual sequence does not alter flight physics.

Overpasses use independent swept deck contacts. Spider form has 2.5 m visual ceiling standoff. Glider catch is 1.1 s, reverse deployment is 1.2 s and direct gyro transfer is 0.78 s. A separate glider diving pose retains the grip/wing configuration. The skyline uses a deforming annular neon grid mesh, with terrain height and motion driven by speed.

Soundtrack and Adaptive soundtrack are separate preferences: disabling adaptation keeps a constant-volume score, while disabling Soundtrack mutes it. Rider speed trail uses a tapered world-space ribbon following the rider's actual recent path. Options contains measurement units, cosmetics, audio, effects, controller vibration, control bindings and the changelog; Run & Profile contains run selection, replays and records.

The in-run HUD shows only distance, elapsed time and best distance. Desktop input buttons and extra telemetry are hidden; touch controls remain available on touch devices. End-of-run summaries and replay controls remain available.

## Movement-only testing
Drone combat, aiming, firing and pulse controls are removed. Right bumper is again available for sliding. Optional vertical loops now have an independent seeded schedule: after two intervening sections they are eligible, strongly favored after three, and prioritized after five when no recovery or committed wall/ceiling sequence prevents them. Existing safe bypass, route validation and loop rewards remain unchanged.

## Lightcycle ground vehicle
The regular ground and short-hop visual is now a dark hubless-wheel lightcycle with neon cosmetic trim. The articulated rider sits on the saddle, grips handlebars, leans into turns and compresses on landing. Short jumps pitch the bike instead of performing skateboard kickflips. Wheel carriers fold into the existing glider platform on extended flight and unfold as it catches the rider. Gyro and ceiling spider rigs retain their original geometry. This is a visual change only; motion, collision and track generation remain unchanged.

## Loop collision and camera
Loop riding positions interpolate the actual mesh triangles; airborne contacts sweep those same triangles across both loop arms and both faces. The third-person loop camera uses physical-distance trailing positions and an elevated fallback instead of collapsing onto the rider. The camera's loop sightline tests use the actual loop geometry. Existing loop rewards, safe bypass and momentum rules remain.

## Loop vehicle and terrain variety
The lightcycle stays active throughout a grounded vertical loop, including its crown; ceiling and wall hardware are reserved for actual ceiling/wall routes. Loop landings require exact swept foot contact, while body impacts deflect at the impact position. New speed-scaled track profiles include grand turns, descending sweeps, double bends, wave runs, crest runs, wide slaloms and banked bowls. Recovery and loop scheduling remain in place.

The mountain ring now starts 1,900 units from the rider (previously 380), with an extended camera horizon. Motorcycle freefall has a distinct eased nose-down pose, floating rider stance and extended suspension, recorded in replays. Airborne movement near loops uses an exclusive swept-mesh collision corridor covering the adjoining road as well; approximate landing/obstacle recovery is not used there. Fall and storm checks consult physical geometry rather than trusting a wrong-arm progress estimate.
