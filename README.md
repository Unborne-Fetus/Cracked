# VECTOR VELOCITY — Flow reboot

A streamlined high-speed third-person running game, inspired by the movement loop of Haste (no copied assets or code). Restored Godot and the original generated soundtrack from the previous Vector Velocity project, and replaced the feature-heavy runner with a focused movement prototype.

- Run automatically, steer left/right, launch naturally from crests, and hold dive to meet descending terrain. Perfect and good landings generate energy for a short aerial boost.
- Wide continuous procedural hills, sparse obstacles, a pursuing collapse and finite worlds. Clear a world to advance.
- Minimal distance/time/best HUD and boost meter, pause, restart, soundtrack toggle and keyboard/controller/touch input.
- No permanent vehicles, combat, shields, stunts, upside-down tracks, currency, loadouts, replays, cosmetics, or online systems.

Controls: A/D or arrows steer, Space or Shift dive, F or left mouse boost, Escape pause, R restart. Controller left stick, A or LT dive, RB boost, Start pause.

Play: https://unborne-fetus.github.io/Cracked/

Development: Godot 4.7.2, Web export preset. Generate the original soundtrack using tools/render_soundtrack.py (NumPy and FFmpeg) before local builds. Run godot --headless --path . --script res://tests/flow.gd. CI renders audio, runs tests and publishes to Pages.

Prior momentum version: 8de9f3d399cf39e72a358b9536435e6603918ff8. Rhythm-action experiment: 36fce16eb0447bdcc243344e38b84398b1c073be. Both remain in Git history. This is a movement prototype, not a full recreation of Haste.

Three attempts per expedition, deterministic retry terrain, completion grades and consecutive worlds. Original music and art; controls and values are independently implemented.

Flow expansion: true procedural ravines with alternate corridors, support-aware flight, a colored landing prediction ring, articulated knees and elbows, landing-chain rewards, speed-sensitive camera, floating spires and two seeded route choices between stages. Terrain and route visuals use original procedural assets.

## Shard expedition
Ten unlockable shards, each with three worlds and a final guardian escape challenge. Choose one of three route profiles; collect sparks, buy from a seeded three-item shop, and build upgrades that persist through the shard (but not into a new expedition). Failed attempts discard unbanked sparks. Guardian waves are telegraphed terrain hazards, avoidable by steering or staying airborne. Shard unlocks persist locally. All values and content are original, and this is still a prototype, not full parity with Haste.

## Expanded gameplay
Five worlds per shard, five route profiles, four selectable active abilities (Burst, Glide, Surge, Phase), 40 stackable items and one-time recovery choices, paid shop rerolls, and three-phase guardian challenges with four patterns. Items affect real physics, collection, economy, energy or hazard response; some stack with one another. The guardians share a pattern framework rather than ten bespoke bosses. No story or graphics expansion is required.

## Gameplay depth and continuity
52 items, four set synergies, ten distinct guardian pattern programs and six hazard types. Ten terrain motifs, alternating ravines, four optional trial objectives with performance-based rewards, build inventory, and checkpoint continuation at the start of a world or the shop. Press M to return to the title and resume the saved expedition; unbanked mid-world pickups are intentionally not persisted. The 10 guardians still use a shared procedural hazard engine. Story and art are intentionally excluded. CI exercises actual scene transitions using controlled finish positions, not a full hands-on playthrough.

The regression suite also drives the actual 120 Hz runner physics along a complete seeded rest route, including acceleration, flight and ability use; it does not claim full manual playtesting or full coverage of all routes.

## Movement and encounter polish
Shared swept landing contact for the live runner and its prediction, corrected high-speed item caps, visible ravine bypass guidance and pickup trails, airborne pickups on riskier routes, differentiated guardian penalties (energy drain, crosswind, ability jam, downdraft), safe-corridor-aware guardian placement, clean streaks and guardian grades. Trial HUD shows actual progress. The title can be reopened using M or the pause menu. New tests cover guardian effects, landing caps, geometry and a full guided ravine traversal.

## Endless and difficulty
Clear shard 10 to unlock continuous procedural worlds without shops, bosses or intermission menus. Endless records and checkpoints are persisted, and clearing a world carries forward some speed and energy. Choose Flow, Standard or Expert at the title; the settings alter initial attempts and collapse pressure. Endless has one attempt regardless of difficulty. No co-op implementation is included.

The pre-reboot white articulated rider's exact body dimensions, colors and two-bone joint helpers have been restored. Its on-foot running, dive and landing poses are adapted to current movement; no vehicle hardware is instantiated. The speed trail returns to cyan.
