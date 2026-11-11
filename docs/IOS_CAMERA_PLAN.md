# iOS camera mode plan

Status: research notes, nothing built. Written 2026-10-31.

A third mode for the iOS app, beside Instant and Edit: a live camera that
captures single-frame raw, previews the recipe live, and develops the raw
through a scene-referred film negative + print model.

## Goals

- **Capture:** single-frame Bayer RAW through `AVCapturePhotoOutput`, with no
  computational merge (the same idea as Halide's Process Zero). Save a DNG and
  a developed HEIC.
- **Non-destructive:** store the recipe with the DNG, so a frame can be
  re-developed later with another recipe or EV.
- **Live preview:** show the recipe applied to the viewfinder, like Apple's
  Photographic Styles.
- **Finger controls:** vertical swipe on the viewfinder sets EV ±
  (`AVCaptureDevice.setExposureTargetBias`). Tap sets the focus/exposure point,
  long-press locks it (AE/AF-L), and a manual focus control is available.
- **Look:** a negative → print film model running on scene-linear light, after
  Steve Yedlin's display-prep approach.

## Reference apps and reading

- **Halide (Lux):** don't decompile it. The App Store license forbids reverse
  engineering, and the structure is public: Process Zero develops a single raw
  exposure with Lux's own tone curve and skips Apple's processing. It saves a
  DNG plus a JPEG/HEIC, and Image Lab re-develops the DNG at other exposures.
  [PetaPixel](https://petapixel.com/2024/08/14/halides-anti-intelligent-update-makes-iphone-photos-truly-natural),
  [Michael Tsai](https://mjtsai.com/blog/2024/08/15/halide-2-15-process-zero)
- **Chromagraph Camera** (Rian Johnson + Steve Yedlin, $12.99, stills only):
  develops the raw sensor data with Yedlin's film processing, skipping Apple's,
  and has color, tone, exposure, grain and halation controls.
  [No Film School](https://nofilmschool.com/rian-johnson-steve-yedlin-app)
- **Yedlin's writing:**
  [On Color Science for Filmmakers](https://yedlin.net/OnColorScience),
  [Display Prep Demo FAQ](https://www.yedlin.net/NerdyFilmTechStuff/DispPrepDemoFAQ/).
  What carries over to Granular:
  - The look is in the display-prep transform from camera data to screen, not
    in the camera.
  - One fixed transform applies to every shot. Per-shot changes are limited to
    overall color balance and brightness, which here means EV and white balance.
  - His target data came from contact prints read with a densitometer. He
    publishes the method, not his transforms or data.

## Film data without our own measurements

| Source | License | Use |
|---|---|---|
| [spectral_film_lut](https://github.com/JanLohse/spectral_film_lut) | MIT | Already bakes `Sources/GranularCore/FilmStocks` via `Scripts/bake-film-stocks.py`. Build on this. |
| [spektrafilm](https://github.com/andreavolpato/spektrafilm) (formerly agx-emulsion) | GPL-3 | The most complete spectral simulation, including how the color layers affect each other and grain. Can't ship in the app, so use it on the Mac as a reference renderer for the same DNGs. |
| [raw2film](https://github.com/JanLohse/raw2film) | MIT | A raw editor with film emulation. Working code for the raw → film path. |
| [Filmulator](https://github.com/CarVac/filmulator-gui) | Unclear on GitHub | Simulates how developer chemistry builds tone. Read it for highlight rolloff ideas; don't copy code. |

Datasheet curves are idealized. spektrafilm's author says datasheets alone
aren't enough for a convincing look, which is why it models more. Without our
own film measurements, spektrafilm renders stand in as the reference.

### The change to the stock cubes

The current cubes take display sRGB in and give display sRGB out, which fits
photos Apple has already processed. For the camera, rebake them with scene
input. The pinned spectral_film_lut 0.18.2 accepts any `colour` RGB colourspace
as `input_colorspace`, ACEScct included. The camera path would be:

1. Raw DNG, or an Apple Log preview frame
2. → extended linear Rec. 2020 (already Granular's working space; see `HDR_PIPELINE.md`)
3. → ACEScct in the shader
4. → the stock cube, baked with `input_colorspace="ACEScct"`

First step: rebake Vision3 250D this way and compare it with the sRGB cube and a
spektrafilm render of the same DNG. About 30 minutes.

## Build order

| # | Piece | Approach | Estimate |
|---|---|---|---|
| 1 | Capture | `AVCapturePhotoOutput`, Bayer RAW, one frame → DNG | 2–3 days |
| 2 | Non-destructive output | Store the recipe with the DNG and render a HEIC; re-develop = load the DNG + recipe | 2–3 days |
| 3 | Live preview | Run film tone on the video frames. On iPhone 15 Pro and later, Apple Log frames are scene-referred, so the preview can match the raw render | About 1 week; the hardest piece |
| 4 | Controls | Swipe EV, tap/long-press AE/AF lock, manual focus, recipe strip, finishing drawer | 3–4 days |
| 5 | Calibrated stocks | Scene-referred cubes as above. Fit to measured film later if we ever shoot charts | Open-ended |

Rows 1–4 come to about 3 weeks.

**Main risk:** the live preview (video frames) and the final render (raw DNG)
must look the same, or the live preview stops being a promise of the result.
Plan a calibration step between the two.

**Performance:** halation, diffusion and grain currently run at full
resolution. The live preview needs versions that run at screen resolution and
frame rate.

## Next: UI mockup

Planned as its own session. Build a clickable, iPhone-sized (393×852 pt) HTML
mockup published as an Artifact, plus `docs/IOS_CAMERA_UI_MOCKUP.md` listing
each control, its gesture, and the AVFoundation call it maps to. Don't change
the Swift app. Screens:

1. Viewfinder with the live recipe and a stock strip (Vision3 250D, 500T,
   Eterna 500, Portra 400, …) that swaps the look.
2. Vertical swipe anywhere = EV ±, with a readout that shows during the drag
   and then fades. This gesture matters most.
3. Tap for the focus/exposure point, long-press for the AE/AF-L lock, and a
   manual focus dial.
4. Shutter, last-frame thumbnail, and a RAW DNG + HEIC indicator. The thumbnail
   opens re-develop: change the recipe or EV after capture.
5. A swipe-up drawer for halation, diffusion and grain amounts.

Match the existing iOS visual language (camera back, alloy surface, nameplate,
exposure counter) from `iOS/Granular/CameraView.swift`, `InstantView.swift`,
`FilmChamber.swift`, `EditControls.swift` and `EditEffect.swift`. Take
gestures from Halide, but not its look.
