"use client";

import { useState } from "react";
import type { CSSProperties } from "react";

const asset = (path: string) => `${process.env.NEXT_PUBLIC_BASE_PATH ?? ""}${path}`;

const comparisons = [
  { before: asset("/result-one-before.jpeg"), after: asset("/result-one-after.jpeg"), label: "Bedroom" },
  { before: asset("/result-two-before.jpeg"), after: asset("/result-two-after.jpeg"), label: "Doorway" },
  { before: asset("/result-three-before.jpeg"), after: asset("/result-three-after.jpeg"), label: "Living room" },
];

export default function ResultComparison() {
  const [position, setPosition] = useState(52);
  const [selected, setSelected] = useState(0);
  const current = comparisons[selected];

  return (
    <div className="comparison-gallery">
      <div
        className="comparison"
        style={{ "--position": `${position}%` } as CSSProperties}
      >
        <img className="comparison-before" src={current.before} alt={`Original ${current.label.toLowerCase()} photograph`} />
        <div className="comparison-after-wrap">
          <img className="comparison-after" src={current.after} alt={`Filmify-finished ${current.label.toLowerCase()} photograph`} />
        </div>
        <span className="comparison-label comparison-label-before">ORIGINAL</span>
        <span className="comparison-label comparison-label-after">FILMIFY</span>
        <input
          aria-label="Compare original image with Filmify result"
          className="comparison-control"
          max="100"
          min="0"
          onChange={(event) => setPosition(Number(event.target.value))}
          type="range"
          value={position}
        />
        <span className="comparison-handle" aria-hidden="true"><i /><i /></span>
      </div>
      <div className="comparison-thumbnails" aria-label="Choose a photo to compare">
        {comparisons.map((comparison, index) => (
          <button
            aria-label={`Show ${comparison.label} before and after`}
            aria-pressed={selected === index}
            className={selected === index ? "comparison-thumb is-selected" : "comparison-thumb"}
            key={comparison.label}
            onClick={() => setSelected(index)}
            type="button"
          >
            <img src={comparison.after} alt="" />
          </button>
        ))}
      </div>
    </div>
  );
}
