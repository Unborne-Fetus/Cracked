(() => {
  "use strict";
  const audio = new Audio(new URL("soundtrack.ogg", document.baseURI).href);
  audio.loop = true;
  audio.preload = "auto";
  audio.volume = 0;
  let enabled = false, started = false, pending = false, target = 0;
  let timer = 0;
  function fade() {
    target = enabled ? 0.42 : 0;
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
    if (!enabled || started || pending) return;
    pending = true;
    // Do not set currentTime, call load(), pause(), or play() again after
    // success. Audio keeps its place across all in-game states.
    Promise.resolve(audio.play()).then(() => {
      started = true; pending = false; fade();
    }, () => { pending = false; });
  }
  window.velocityMusic = {
    start,
    setEnabled(value) { enabled = Boolean(value); fade(); },
  };
  window.addEventListener("pointerdown", start, {capture:true, passive:true});
  window.addEventListener("keydown", start, {capture:true});
  window.addEventListener("touchend", start, {capture:true, passive:true});
})();
