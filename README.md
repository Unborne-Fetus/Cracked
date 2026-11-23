# Cracked — VECTOR VELOCITY

**A playable 3D momentum-running prototype in Godot 4.7.2**, designed for WebGL 2 browsers. Inspired by the *feel* of downhill speedrunners and the simplicity of vector arcade visuals, but with original movement code and generated geometry.

## ▶ Browser build

Once the **Build & Publish Browser Prototype** GitHub Action succeeds and GitHub Pages is set to **GitHub Actions**:

**https://unborne-fetus.github.io/Cracked/**

The workflow also produces a downloadable \`vector-velocity-web\` artifact. The web build uses the Godot **Compatibility** renderer with **threads disabled**, so it can run on standard HTTPS GitHub Pages without COOP/COEP headers.

> If Pages is not yet enabled, open **Settings → Pages → Build and deployment → Source: GitHub Actions**.

## Controls

| Input | Action |
| --- | --- |
| A / D or ← / → | Steer sideways |
| Space | Jump |
| V or C | Toggle first-person / third-person |
| Hold Shift, Ctrl, S or ↓ | Slide on flat/downhill ground; uphill sliding is blocked |
| R | Restart |
| Controller left stick | Steer |
| Controller A | Jump |
| Hold controller B | Slide |
| Touch arrows, SLIDE, JUMP, VIEW | Mobile / tablet browsers |

You move automatically in the +X direction. **Hold slide on flat or downhill terrain to gain speed**. Running, jumping, and landing do not grant horizontal speed. **Uphill inclines disable sliding**, and friction slows you down when not sliding. There is **no upper speed cap**. Avoid glowing columns and barriers (or jump over the short hurdles). A translucent neon storm starts behind you and **accelerates over time**; it ends the run if it catches you. Reach the gold gate at 1035 meters to set a time. Your best time is saved locally in the browser.

## Technical features

- 3D \`CharacterBody3D\` player with uncapped horizontal speed, slide-only acceleration on flat/downhill slopes, uphill slide lockout, air steering and speed-dependent camera field of view.
- Dynamically generated dark terrain mesh; neon grid lines and physics collision share one mathematical height function.
- Lightweight unshaded materials; no external models, images or commercial assets.
- First-person and third-person follow cameras.
- Neon obstacle hazards with continuous movement collision sweep, glowing course arches, a finish gate, on-screen HUD, touch buttons and saved best times.
- A visible storm wall that chases the player and increases its speed continuously, restarting from its initial speed with each run.
- GitHub Actions CI: import check, startup smoke test, terrain grounding regression, slide/storm/obstacle regression, Web export and GitHub Pages deployment.

## Open locally

1. Install **Godot 4.7.2 (standard, not .NET)**.
2. Clone this repository and open \`project.godot\`.
3. Press **F6** or **F5** to play (F5 runs the main scene).
4. To export manually: install the matching **Web export templates**, choose **Project → Export → Web**, and export to \`build/web/index.html\`.
5. Serve the \`build/web\` directory over HTTP(S); opening \`index.html\` directly as a \`file://\` URL will not work.

### Prototype scope / known limitations

This is a first-pass movement test with one handcrafted mathematical terrain profile (not infinite procedural generation). Multiplayer, menus, audio, graphical postprocessing, and level selection are future work. Desktop keyboard or controller is the recommended first test; mobile uses basic button controls.
