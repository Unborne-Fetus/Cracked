# Vector Velocity changelog

## Grounded lightcycle
- Removed jump, double-jump, dive and glider deployment from gameplay and controls.
- Permanent track adhesion through hills, banks and loops; edge bounds and grounded obstacle impacts.
- Former jump gaps are bridged; legacy animation fields cannot deploy wings.

## Three-wheel anti-gravity lightcycle
- One front wheel and a rear pair, animated rigid ninety-degree wheel swivels and glowing hover pads on walls and ceilings.
- Remove spider and gyro geometry; preserve normal wheel orientation in loops and the glider catch.

## Smooth loop chase and adaptive rock
- Continuous loop-relative chase arm, obstruction-aware selection, stable roll axis and exit hysteresis.
- Original hard-rock score with synchronized adaptive stems; browser-local audio picker with speed-dependent filter and gain.

## Distant mountains, motorcycle freefall and loop flight
- Move the background ring five times farther from the rider and extend the camera horizon.
- Add freefall pitch, suspension and articulated body poses, including replay.
- Exclusive real-mesh loop flight collision, including adjoining roads; local impact response and physically validated loss checks.

## Loop motorcycle and broader terrain
- Keep lightcycle through the entire loop; exact-contact landings and trajectory-preserving impacts.
- Keep chase camera aimed at the player during loops, including replay.
- Seven new speed-scaled flowing track profiles, with frequent long sweeping turns.

## Loop clipping and chase camera
- Match grounded loop contact to the actual emitted triangles and sweep airborne feet/body against both loop faces.
- Refine loop projection and route metric; preserve a full third-person chase arm at loops.
- Add actual generated-loop collision and camera regression checks.

## Lightcycle ground vehicle
- Dark monocoque with luminous hubless wheels and seated articulated rider; steering lean, suspension, wheel rotation and short-hop pitch.
- Folding wheel carriers for glider handoff; original gyro and ceiling rig retained. Movement rules unchanged.

## Movement-only testing
- Removed combat actors, damage, controls, mode and aiming HUD. Restored right bumper sliding.
- Increased optional loop frequency with a dedicated cadence while preserving recovery and sustained bank sequences.

## 2026-11-24 — Minimal HUD and momentum-only combat
- Show only distance, time and best during normal gameplay; retain aiming and touch controls as needed.
- Removed shields, shield recovery and shield-depletion defeats. Drone hits reduce speed and reserve only.

## 2026-11-24 — Deck sweeps, transformation handoffs and mesh mountains
- Stacked-route flight checks upper and lower decks independently, selecting the earliest actual swept contact.
- Ceiling spider legs suspend the rider 2.5 m below the surface.
- Faster glider catch, reverse deployment, direct glider-to-gyro handoff and dedicated glider dive.
- Animated tessellated neon mountain mesh with continuous movement and extreme speed-dependent elevation.

## 2026-11-24 — Replay rates, cosmetics and glider recovery
- Fixed replay speed cycling (0.5x, 1x, 2x); recorded poses follow replay time.
- Restored original, amber, violet and emerald cosmetic palettes, saved unlocks and replay selection.
- Enlarged spider leg contact span to 8.5 metres, with longer articulated limbs and wider stride.
- Glider release separates the rider, flies away, swoops underneath and catches the feet before folding wings.

## 2026-11-24 — Mechanical gyro deployment and build repair
- Twenty-four rigid curved rim segments slide from the board rails, unfold, and lock into two rotating rings; the deck remains the pilot platform.
- Reverse deployment folds the wheel away before glider wings extend.
- Guarded collapsed limb transforms and enforced camera clearance after orbit and landing blends.
- Regression tests verify rigid panel motion and bank camera clearance.

## 2026-11-23 — Transformation trick sets, jet wings and storm confirmation
- Eight glider trick variants and six gyro trick variants; animated jet nacelles on both wings.
- Eight large articulated ceiling spider legs replace treads.
- Glider orientation corrects inherited wall roll; first-person cockpit clears obstructing transformation meshes.
- Storm catches require sustained track-relative proximity; high-altitude projection alone cannot cause a catch. Replay ends show the saved defeat reason.

## 2026-11-23 — Transforming board and evolving skyline
- Mountains rise and recede with course progress, with increasing peak height deeper into a run.
- Grounded inverted riding deploys animated ceiling treads; sideways wall riding transforms the deck into a gyro wheel.
- Swept wall/ceiling contacts can attach and reorient upright airborne riders to the actual contacted face.
- High-altitude glider tricks rotate the full rig; the return animation releases the grips, arcs the board underneath, catches it and then folds the wings.

## 2026-11-23 — Pursuit drones, fullpipe seam, synthwave sky and glider
- Drones match pace and stay ahead; telegraphed hits remove 40% momentum and reserve, eliminations restore speed and reserve.
- More frequent sustained wall and ceiling segments, unique sidewall grip pose.
- Low-speed traction suppresses sideways drift until forward speed recovers.
- Closed fullpipe crown with continuous wrapped steering.
- Longer high-speed chunks, cheaper board clearance and bank-contact probes, reduced ordinary camera sightline samples.
- Speed-reactive striped sunset, neon mountains and perspective grid; cosmetic high-altitude hanging glider with folding wings.

## 2026-11-23 — Default combat, restart traction and first-person corrections
- Robotic enemies and pulse controls are enabled automatically in every run; Practice does not end from shield depletion.
- Mouse cursor becomes a precise crosshair during play and returns to normal in menus, replays and defeat screens.
- Grounded riders regain minimum speed after stalling, including uphill.
- Shallow bank contacts can recover onto the correct rideable face; fall confirmation is less sensitive to brief projection errors.
- First-person camera moved forward, with consistent screen-relative horizontal and vertical look controls.

## 2026-11-23 — Loop routes, rider hanging poses, camera and arcade combat
- Falls require sustained downward movement beneath nearby supported road; high or sideways flight alone cannot kill the rider.
- Track-aligned camera does not rotate with carving; revised first-person eye placement and field of view.
- Joint and board transform crossfades, sideways riding poses and retractable upside-down grip handles.
- Optional vertical loop branch with safe bypass, minimum speed at the crown and one-time momentum reward.
- Optional Combat run mode with robotic drones, energy pulse tagging and shield depletion.

## 2026-11-23 — First-person body, sky, drift and camera
- Visible animated legs, boots and hoverboard in first person.
- Procedural neon twilight skybox with stars, aurora and distant silhouettes.
- Eased orbit, recenter, chase-arm and orientation changes.
- Remappable Q/E left/right drifting independent of A/D carving.
- 24 airborne idle tricks and six ground idles, plus contextual riding animations.

## 2026-11-23 — Steering, branch safety and animation expansion
- Heading-based carving on ground and directional air steering, with stronger response at speed.
- Gold inner-edge fork guidance keeps a rider on the selected supported branch; outer edges and deliberate transfers remain open.
- Falling between branches no longer immediately ends the run while the lower deck is still reachable.
- Nine air idle trick variants: shifty, grab, one-foot, heelflip, shove-it, frontflip, backflip, scissor kick and barrel roll.
- Ground hop/spin, inverted riding brace, replay-recorded turning and animation states.
- Changelog linked from the pause menu and published alongside the browser build.

## 2026-11-23 — Asymmetric forks and NIGHT CIRCUIT
- Elevated narrow rolling ridge versus wide sunken channel; flyover and lower bowl.
- Three initial air idle tricks, bank compensation, landing brace and gate celebration.
- New 174 BPM original soundtrack with longer harmonic progression and distinct drops.

## 2026-11-23 — Contact, rider and audio
- Removed eight-second airborne death timeout; road-proximity fall checks.
- Solid obstacle rebounds and persistent obstacle collision.
- Taller block rider, curved board nose and tail, terrain-aware clearance.
- Kickflip footwork, crouching, dive, carving, landing and impact animation.
- Browser-native continuous soundtrack; pause resumes at the same timestamp.

## Earlier development — Core systems
- Procedural terrain, banks, halfpipes, corkscrews, gaps, branching routes and slipstreams.
- Momentum reserve, double jump, diving, perfect landings and clean route gates.
- Circular elevation minimap, first/third-person camera, free orbit and recenter.
- Controller and touch controls, key remapping, daily seeds, practice and challenge modes.
- Local replay recording and playback; local profiles and achievements.
- Web builds with unique release paths, cached soundtrack and headless regression tests.
