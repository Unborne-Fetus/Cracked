# Cracked — VECTOR VELOCITY

An endless 3D neon momentum runner built with Godot 4.7.2 for WebGL 2.

**Play:** https://unborne-fetus.github.io/Cracked/

## Controls

| Input | Action |
| --- | --- |
| A / D or Left / Right | Steer across the track |
| Hold Shift, Ctrl, S or Down | Slide |
| Space | Jump |
| V or C | First-person / third-person |
| R | Restart |
| Controller left stick / A / B | Steer / jump / slide |
| Touch buttons | Steer, slide, jump, camera |

Sliding on flat or downhill track builds momentum while grip is available. Holding slide drains grip in about 2.4 seconds; release on the ground to recover it. Sliding at zero grip slows the runner, and jumping cannot refill grip. Sliding trades lateral steering precision for speed. Sliding uphill is allowed but rapidly drains speed on ordinary hills. Faster movement produces higher jumps; jumping never adds forward speed. Running and jumping do not accelerate the player. There is no maximum speed. Obstacles take away 70% of current speed without ending the run. Jump over low barriers or steer around taller ones. The pursuing storm accelerates more aggressively; being caught ends the run. Tall route gates have alternating side openings that require steering rather than jumping. Air drag and brief landing recovery discourage repeated jumping.

## Endless track

The course is generated in connected 192-meter sections. The track is 44 meters wide. Hills, sweeping turns, steeply banked corners, 180-degree half-roll banks with an upside-down stretch, and complete 360-degree barrel-roll banks are generated from continuous local frames; vertical loops are removed. A finely subdivided, thick ribbon reduces twisting artifacts. Track and obstacle colors gradually cycle over 12 kilometers of distance. Ten obstacle silhouettes include cones, columns, crystals, spheres, hurdles, arches, steps, hexagonal prisms, paired spires and blocks, with shape-aware collision and open passages. After an introductory sequence, the track uses seeded random sections. The runner adheres to the track in its local orientation, including upside down. The chase camera samples the actual trailing bank frame and shortens its arm if a sightline crosses the track; first-person is aligned to the runner's local frame. Track chunks are created ahead and removed behind; world coordinates are periodically rebased to keep precision stable. The storm follows arc-length progress instead of world X. Records track longest distance.

## Development

Open project.godot with Godot 4.7.2 and press F5. The Web export uses Compatibility rendering and single-threaded templates. GitHub Actions checks startup, ground contact, bank orientation, continuous track colors, shape variety, track seams, endless chunk recycling, momentum, obstacle and storm rules before deploying a unique versioned browser build to GitHub Pages.
