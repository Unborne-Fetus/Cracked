(() => {
  "use strict";
  const audio = new Audio(new URL("soundtrack.ogg", document.baseURI).href);
  audio.loop = true;
  audio.preload = "auto";
  audio.volume = 0;
  let enabled = false, adaptive = true, speed = 0, started = false, pending = false, paused = false, target = 0;
  let timer = 0;
  function fade() {
    const t = Math.max(0, Math.min(1, (speed - 20) / 160));
    const blend = t * t * (3 - 2 * t);
    target = enabled ? (adaptive ? 0.34 + 0.28 * blend : 0.42) : 0;
    if (timer) return;
    timer = window.setInterval(() => {
      const remaining = target - audio.volume;
      audio.volume = Math.max(0, Math.min(1, audio.volume + remaining * 0.13));
      if (Math.abs(remaining) < 0.002) {
        audio.volume = target;
        clearInterval(timer); timer = 0;
      }
    }, 40);
  }
  function start() {
    if (!enabled || paused || started || pending) return;
    pending = true;
    // Do not set currentTime, call load(), pause(), or play() again after
    // success. Audio keeps its place across all in-game states.
    Promise.resolve(audio.play()).then(() => {
      started = true; pending = false;
      if (paused) audio.pause();
      fade();
    }, () => { pending = false; });
  }
  window.velocityMusic = {
    start,
    configure(on, adapt, value) {
      enabled = Boolean(on); adaptive = Boolean(adapt);
      speed = Number.isFinite(value) ? Math.max(0, value) : 0;
      fade();
    },
    setEnabled(value) { enabled = Boolean(value); fade(); },
    setSpeed(value) {
      speed = Number.isFinite(value) ? Math.max(0, value) : 0;
      if (enabled && adaptive) fade();
    },
    setPaused(value) {
      value = Boolean(value);
      if (paused === value) return;
      paused = value;
      if (!started) return;
      if (paused) audio.pause();
      else {
        // Resume from currentTime; never reload or seek.
        Promise.resolve(audio.play()).catch(() => { started = false; });
      }
    },
  };
  window.addEventListener("pointerdown", start, {capture:true, passive:true});
  window.addEventListener("keydown", start, {capture:true});
  window.addEventListener("touchend", start, {capture:true, passive:true});
})();
