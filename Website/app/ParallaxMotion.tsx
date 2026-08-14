"use client";

import { useEffect } from "react";

export default function ParallaxMotion() {
  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const layers = Array.from(document.querySelectorAll<HTMLElement>("[data-parallax]"));
    let frame = 0;

    const render = () => {
      frame = 0;

      if (reducedMotion.matches) {
        layers.forEach((layer) => layer.style.removeProperty("--parallax-y"));
        return;
      }

      const viewportHeight = window.innerHeight;

      layers.forEach((layer) => {
        const rect = layer.getBoundingClientRect();
        const distance = (rect.top + rect.height / 2 - viewportHeight / 2) / viewportHeight;
        const range = Number(layer.dataset.parallax ?? 12);
        const limit = Math.abs(range);
        const offset = Math.max(-limit, Math.min(limit, distance * range));
        layer.style.setProperty("--parallax-y", `${offset.toFixed(2)}px`);
      });
    };

    const schedule = () => {
      if (!frame) frame = window.requestAnimationFrame(render);
    };

    schedule();
    window.addEventListener("scroll", schedule, { passive: true });
    window.addEventListener("resize", schedule);
    reducedMotion.addEventListener("change", schedule);

    return () => {
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("scroll", schedule);
      window.removeEventListener("resize", schedule);
      reducedMotion.removeEventListener("change", schedule);
      layers.forEach((layer) => layer.style.removeProperty("--parallax-y"));
    };
  }, []);

  return null;
}
