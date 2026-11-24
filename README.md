# VECTOR VELOCITY — Flow reboot

A streamlined high-speed third-person running game, inspired by the movement loop of Haste (no copied assets or code). Restored Godot and the original generated soundtrack from the previous Vector Velocity project, and replaced the feature-heavy runner with a focused movement prototype.

- Run automatically, steer left/right, jump from hills, dive to meet descending terrain and preserve momentum with good landings.
- Wide continuous procedural hills, sparse obstacles, a pursuing collapse and finite worlds. Clear a world to advance.
- Minimal distance/time/best HUD, pause, restart, soundtrack toggle and keyboard/controller/touch input.
- No vehicles, combat, shields, stunts, upside-down tracks, currency, loadouts, replays, cosmetics, or online systems.

Controls: A/D or arrows steer, Space jump, Shift or F dive, Escape pause, R restart. Controller left stick, A jump, RB/right trigger dive, Start pause.

Play: https://unborne-fetus.github.io/Cracked/

Development: Godot 4.7.2, Web export preset. Generate the original soundtrack using tools/render_soundtrack.py (NumPy and FFmpeg) before local builds. Run godot --headless --path . --script res://tests/flow.gd. CI renders audio, runs tests and publishes to Pages.

Prior momentum version: 8de9f3d399cf39e72a358b9536435e6603918ff8. Rhythm-action experiment: 36fce16eb0447bdcc243344e38b84398b1c073be. Both remain in Git history. This is a movement prototype, not a full recreation of Haste.
