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

Sliding on flat or downhill track builds momentum. Sliding uphill is allowed but rapidly drains speed. Running and jumping do not accelerate the player. There is no maximum speed. Obstacles take away 70% of current speed without ending the run. Jump over low barriers or steer around taller ones. The pursuing storm continuously accelerates; being caught ends the run.

## Endless track

The course is generated in connected 192-meter sections. Hills, sweeping turns, steeply banked corners and full vertical inversions are generated from continuous local frames. After an introductory sequence, the track uses seeded random sections. The runner adheres to the track in its local orientation, including upside down. Track chunks are created ahead and removed behind; world coordinates are periodically rebased to keep precision stable. The storm follows arc-length progress instead of world X. Records track longest distance.

## Development

Open project.godot with Godot 4.7.2 and press F5. The Web export uses Compatibility rendering and single-threaded templates. GitHub Actions checks startup, ground contact, inversion orientation, track seams, endless chunk recycling, momentum, obstacle and storm rules before deploying a unique versioned browser build to GitHub Pages.
