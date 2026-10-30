"use client";

import { useEffect, useRef } from "react";

// Frames are 2:1 renders letterboxed in the hero's 1.357:1 box, like the still's object-fit: contain.
const BOX_ASPECT = 1.357;
const FRAME_ASPECT = 2;
// The lowest point of the film and canister in any frame, as a share of the still's box (frames are letterboxed 2:1
// in a 1.357:1 box; the subject reaches 81 % down the frame). The turn ends as that point passes the top of the viewport.
const SUBJECT_BOTTOM = 0.71;
// Share of the scroll spent easing in; after that the turn runs at a constant rate until the subject has left.
const EASE_IN = 0.3;
// Frames were rendered along a smoothstep, so frame t shows smoothstep(t) of the full turn; this inverts it.
const frameForTurn = (turn: number) => 0.5 - Math.sin(Math.asin(1 - 2 * turn) / 3);
const FRAME_COUNT = 32;
// Ease in, then linear, with no slow-down at the end.
const turnForProgress = (p: number) => {
  const slope = 1 / (1 - EASE_IN / 2);
  return p < EASE_IN ? (slope * p * p) / (2 * EASE_IN) : slope * (p - EASE_IN / 2);
};

type Props = {
  // Folders holding f00.avif ... f31.avif at 2048 and 3072 pixels wide.
  standard: string;
  dense: string;
};

// The order frames load in: every 4th frame first so the whole scroll range plays early, then the gaps.
function loadOrder(count: number) {
  const coarse: number[] = [];
  for (let i = 0; i < count; i += 4) coarse.push(i);
  if (coarse[coarse.length - 1] !== count - 1) coarse.push(count - 1);
  const rest = Array.from({ length: count }, (_, i) => i).filter((i) => !coarse.includes(i));
  return [...coarse, ...rest];
}

// Turns the hero slightly in space as the opening section scrolls away. The still stays in the page as the
// poster and for screen readers; the canvas takes over once frames have decoded and the page has scrolled, never
// on small screens, with reduced motion, with Save-Data, or if a frame fails to load.
export default function HeroSequence({ standard, dense }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    const figure = canvas?.parentElement;
    const section = figure?.closest("section");
    const still = figure?.querySelector("img");
    const context = canvas?.getContext("2d", { alpha: false });
    if (!canvas || !figure || !section || !still || !context) return;

    const wide = window.matchMedia("(min-width: 641px)");
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const saveData = (navigator as Navigator & { connection?: { saveData?: boolean } }).connection?.saveData;
    if (!wide.matches || reducedMotion.matches || saveData) return;

    const folder = window.devicePixelRatio > 1.25 ? dense : standard;
    const frames: (HTMLImageElement | undefined)[] = new Array(FRAME_COUNT);
    let loaded = 0;
    let cancelled = false;
    let failed = false;
    let ready = false;
    let frame = 0;
    let drawn = -1;

    // 0 at the top of the page, 1 as the last of the film and canister scrolls past the top of the viewport.
    const progress = () => {
      // The figure is rotated, so take the box's layout height around its on-screen centre.
      const rect = still.getBoundingClientRect();
      const height = still.offsetHeight;
      // The section clips the hero, so whichever leaves first, the subject or the section, ends the turn.
      const subject = rect.top + rect.height / 2 + (SUBJECT_BOTTOM - 0.5) * height;
      const bottom = Math.min(subject, section.getBoundingClientRect().bottom) + window.scrollY;
      return Math.max(0, Math.min(1, window.scrollY / Math.max(1, bottom)));
    };

    const nearest = (position: number, step: 1 | -1) => {
      for (let i = position; i >= 0 && i < FRAME_COUNT; i += step) if (frames[i]) return i;
      return -1;
    };

    const render = () => {
      frame = 0;
      if (failed || !ready) return;
      const amount = progress();
      // At the top of the page the still itself shows, so the hand-over is invisible.
      figure.classList.toggle("is-sequenced", amount > 0);
      if (amount === 0) return;
      const position = frameForTurn(Math.min(1, turnForProgress(amount))) * (FRAME_COUNT - 1);
      const height = canvas.width / FRAME_ASPECT;
      const top = (canvas.height - height) / 2;

      if (loaded === FRAME_COUNT) {
        // Every frame is in: show the nearest one. Neighbouring frames differ too much for a blend to read as motion.
        const index = Math.round(position);
        if (index === drawn) return;
        drawn = index;
        context.globalAlpha = 1;
        context.drawImage(frames[index]!, 0, top, canvas.width, height);
        return;
      }

      // Still loading: cross-fade across the gaps in the coarse set so the turn doesn't jump.
      const low = nearest(Math.floor(position), -1);
      const high = nearest(Math.ceil(position), 1);
      const mix = high > low ? (position - low) / (high - low) : 0;
      const key = low + mix;
      if (key === drawn) return;
      drawn = key;
      context.globalAlpha = 1;
      context.drawImage(frames[low]!, 0, top, canvas.width, height);
      if (high > low && mix > 0) {
        context.globalAlpha = mix;
        context.drawImage(frames[high]!, 0, top, canvas.width, height);
      }
    };

    const schedule = () => {
      if (!frame) frame = window.requestAnimationFrame(render);
    };

    const stop = () => {
      failed = true;
      ready = false;
      figure.classList.remove("is-sequenced");
    };

    const start = () => {
      if (cancelled || !wide.matches || reducedMotion.matches) return;
      canvas.width = frames[0]!.naturalWidth;
      canvas.height = Math.round(frames[0]!.naturalWidth / BOX_ASPECT);
      context.fillStyle = "#000";
      context.fillRect(0, 0, canvas.width, canvas.height);
      ready = true;
      drawn = -1;
      render();
    };

    const load = async () => {
      for (const index of loadOrder(FRAME_COUNT)) {
        if (cancelled || failed) return;
        const image = new Image();
        image.decoding = "async";
        image.src = `${folder}/f${String(index).padStart(2, "0")}.avif`;
        try {
          await image.decode();
        } catch {
          stop();
          return;
        }
        frames[index] = image;
        loaded += 1;
        if (index === 0) start();
        else {
          drawn = -1;
          schedule();
        }
      }
    };

    const idle = window.requestIdleCallback ?? ((callback: () => void) => window.setTimeout(callback, 600));
    const begin = () => idle(() => void load());
    if (document.readyState === "complete") begin();
    else window.addEventListener("load", begin, { once: true });

    const settings = () => {
      if (!wide.matches || reducedMotion.matches) {
        ready = false;
        figure.classList.remove("is-sequenced");
      } else if (frames[0] && !failed) start();
    };

    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    wide.addEventListener("change", settings);
    reducedMotion.addEventListener("change", settings);

    return () => {
      cancelled = true;
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("load", begin);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      wide.removeEventListener("change", settings);
      reducedMotion.removeEventListener("change", settings);
      figure.classList.remove("is-sequenced");
    };
  }, [standard, dense]);

  return <canvas ref={canvasRef} className="opening-sequence" aria-hidden="true" />;
}
