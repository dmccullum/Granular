// Granular's Core Image kernels. The CompileFilmKernels package plugin builds
// this file into a metallib per platform, linked against Core Image's kernel
// library; FilmRenderer loads each kernel by function name. Kernels use
// straight RGB unless they say otherwise.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

namespace {

constant float3 rec2020Luma = float3(0.2627002, 0.6779981, 0.0593017);

/// Core Image Kernel Language's mod: the result takes the divisor's sign.
float floorMod(float x, float y) {
    return x - y * floor(x / y);
}

float srgbEncode(float value) {
    float linear = max(value, 0.0);
    return linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1.0 / 2.4) - 0.055;
}

float srgbDecode(float value) {
    float encoded = max(value, 0.0);
    return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4);
}

float srgbToLinear(float value) {
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}

} // namespace

// Grading the SDR rendition and carrying over the photo's own HDR-to-SDR
// brightness ratio keeps both renditions identical wherever the photo's are,
// and keeps the tone response smooth through reference white: the SDR curve's
// fixed white point never meets an HDR value. One luminance ratio for all
// channels keeps the stock's hue.
[[stitchable]] float4 hdrTone(
    coreimage::sample_t sdr, coreimage::sample_t hdr, coreimage::sample_t graded,
    float exposure, float shoulder
) {
    float4 look = coreimage::unpremultiply(graded);
    float sdrY = max(dot(coreimage::unpremultiply(sdr).rgb, rec2020Luma), 0.0);
    float hdrY = max(dot(coreimage::unpremultiply(hdr).rgb, rec2020Luma), 0.0);
    // The offset keeps ratios near black, where both renditions are mostly
    // noise and encoding offsets, close to 1.
    float ratio = (hdrY + 0.015625) / (sdrY + 0.015625);
    float extra = pow(max(ratio, 1.0), shoulder) - 1.0;
    float gain = min(ratio, 1.0) * (1.0 + extra * exp2(exposure));
    return coreimage::premultiply(float4(max(look.rgb, float3(0.0)) * gain, look.a));
}

[[stitchable]] float4 prepareFilmStock(coreimage::sample_t pixel, float knee) {
    float3 rec2020 = max(pixel.rgb, float3(0.0));
    float3 rgb = float3(
        1.6604910 * rec2020.r - 0.5876411 * rec2020.g - 0.0728499 * rec2020.b,
        -0.1245505 * rec2020.r + 1.1328999 * rec2020.g - 0.0083494 * rec2020.b,
        -0.0181508 * rec2020.r - 0.1005789 * rec2020.g + 1.1187297 * rec2020.b
    );

    // The spectral cubes describe display-referred sRGB. Compress wide-gamut
    // excursions toward neutral before lookup instead of clipping individual
    // channels, which would create hard, synthetic hue changes.
    float y = max(dot(rgb, float3(0.2126, 0.7152, 0.0722)), 0.0);
    if (y > knee) {
        float width = max(1.0 - knee, 0.02);
        float rolledY = knee + width * (1.0 - exp(-(y - knee) / width));
        rgb *= rolledY / max(y, 0.000001);
        y = rolledY;
    }
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float maximum = max(rgb.r, max(rgb.g, rgb.b));
    float lowScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
    float highScale = maximum > 1.0
        ? (1.0 - y) / max(maximum - y, 0.000001)
        : 1.0;
    rgb = mix(float3(y), rgb, clamp(min(lowScale, highScale), 0.0, 1.0));

    return float4(srgbEncode(rgb.r), srgbEncode(rgb.g), srgbEncode(rgb.b), pixel.a);
}

namespace {

float sectorWeight(float hue, float center) {
    float difference = floorMod(hue - center + 3.14159265, 6.28318531) - 3.14159265;
    return max(1.0 - abs(difference) / 1.04719755, 0.0);
}

float characterCurve(float value, float k0, float k1, float k2, float k3, float k4, float k5) {
    float x = clamp(value, 0.0, 1.0);
    if (x < 0.125) { return mix(k0, k1, x / 0.125); }
    if (x < 0.25) { return mix(k1, k2, (x - 0.125) / 0.125); }
    if (x < 0.5) { return mix(k2, k3, (x - 0.25) / 0.25); }
    if (x < 0.75) { return mix(k3, k4, (x - 0.5) / 0.25); }
    return mix(k4, k5, (x - 0.75) / 0.25);
}

} // namespace

[[stitchable]] float4 filmCharacter(
    coreimage::sample_t pixel,
    float3 c0, float3 c1, float3 c2, float3 c3, float3 c4, float3 c5,
    float3 red, float3 yellow, float3 green, float3 cyan, float3 blue, float3 magenta,
    float2 saturation
) {
    float3 rgb = clamp(pixel.rgb, float3(0.0), float3(1.0));
    float3 linear = float3(srgbToLinear(rgb.r), srgbToLinear(rgb.g), srgbToLinear(rgb.b));
    float3 lms = float3(
        0.4122214708 * linear.r + 0.5363325363 * linear.g + 0.0514459929 * linear.b,
        0.2119034982 * linear.r + 0.6806995451 * linear.g + 0.1073969566 * linear.b,
        0.0883024619 * linear.r + 0.2817188376 * linear.g + 0.6299787005 * linear.b
    );
    lms = pow(max(lms, float3(0.0)), float3(0.33333333));
    float lightness = 0.2104542553 * lms.x + 0.7936177850 * lms.y - 0.0040720468 * lms.z;
    float a = 1.9779984951 * lms.x - 2.4285922050 * lms.y + 0.4505937099 * lms.z;
    float b = 0.0259040371 * lms.x + 0.7827717662 * lms.y - 0.8086757660 * lms.z;

    float chroma = length(float2(a, b));
    float hue = atan2(b, a);
    // Hue edits fade out toward neutral so grays keep only the curves' tint.
    float colorWeight = clamp(chroma / 0.08, 0.0, 1.0);
    float w0 = sectorWeight(hue, 0.52359878);
    float w1 = sectorWeight(hue, 1.57079633);
    float w2 = sectorWeight(hue, 2.61799388);
    float w3 = sectorWeight(hue, 3.66519143);
    float w4 = sectorWeight(hue, 4.71238898);
    float w5 = sectorWeight(hue, 5.75958653);
    float3 edit = (w0 * red + w1 * yellow + w2 * green + w3 * cyan + w4 * blue + w5 * magenta)
        * colorWeight;

    lightness += edit.x;
    chroma *= exp(edit.y);
    chroma *= (1.0 - saturation.x * clamp((lightness - 0.6) / 0.4, 0.0, 1.0))
        * (1.0 + saturation.y * clamp((0.6 - lightness) / 0.6, 0.0, 1.0));
    hue += edit.z;
    a = chroma * cos(hue);
    b = chroma * sin(hue);

    float3 root = float3(
        lightness + 0.3963377774 * a + 0.2158037573 * b,
        lightness - 0.1055613458 * a - 0.0638541728 * b,
        lightness - 0.0894841775 * a - 1.2914855480 * b
    );
    lms = root * root * root;
    linear = float3(
        4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z,
        -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z,
        -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z
    );
    rgb = clamp(
        float3(srgbEncode(linear.r), srgbEncode(linear.g), srgbEncode(linear.b)),
        float3(0.0),
        float3(1.0)
    );

    return float4(
        characterCurve(rgb.r, c0.x, c1.x, c2.x, c3.x, c4.x, c5.x),
        characterCurve(rgb.g, c0.y, c1.y, c2.y, c3.y, c4.y, c5.y),
        characterCurve(rgb.b, c0.z, c1.z, c2.z, c3.z, c4.z, c5.z),
        pixel.a
    );
}

[[stitchable]] float4 finishFilmStock(
    coreimage::sample_t source,
    coreimage::sample_t graded,
    float toneRetention,
    float colorAmount,
    float toneAmount
) {
    float3 srgb = float3(srgbDecode(graded.r), srgbDecode(graded.g), srgbDecode(graded.b));
    float3 rec2020 = float3(
        0.6274039 * srgb.r + 0.3292830 * srgb.g + 0.0433131 * srgb.b,
        0.0690973 * srgb.r + 0.9195404 * srgb.g + 0.0113623 * srgb.b,
        0.0163914 * srgb.r + 0.0880133 * srgb.g + 0.8955953 * srgb.b
    );
    float3 positiveGrade = max(rec2020, float3(0.0));
    float sourceY = max(dot(source.rgb, rec2020Luma), 0.0);
    float gradedY = max(dot(positiveGrade, rec2020Luma), 0.000001);

    // These spectral cubes include a complete film density response, but Film
    // Tone's own controls stay in charge of tone. Each stock keeps its own
    // share of the cube's luminance move, so slide film reads denser than a
    // soft negative, while its chromatic signature is kept whole.
    float restrainedY = mix(sourceY, gradedY, toneRetention);
    float3 colorGrade = positiveGrade * (restrainedY / gradedY);
    float3 rgb = mix(source.rgb, colorGrade, colorAmount);

    // Color and tone share one amount except for black-and-white stocks,
    // whose color cannot be extrapolated past gray without inverting hues.
    float mixedY = dot(rgb, rec2020Luma);
    float targetY = max(mix(sourceY, restrainedY, toneAmount), 0.0);
    if (abs(mixedY) > 0.000001) {
        rgb *= targetY / mixedY;
    }
    return float4(rgb, source.a);
}

namespace {

float filmShoulder(float value) {
    float a = 0.15;
    float b = 0.50;
    float c = 0.10;
    float d = 0.20;
    float e = 0.02;
    float f = 0.30;
    return ((value * (a * value + c * b) + d * e)
        / (value * (a * value + b) + d * f)) - e / f;
}

float3 rec2020ToOklab(float3 rgb) {
    float x = 0.6369580 * rgb.r + 0.1446169 * rgb.g + 0.1688809 * rgb.b;
    float y = 0.2627002 * rgb.r + 0.6779981 * rgb.g + 0.0593017 * rgb.b;
    float z =                         0.0280727 * rgb.g + 1.0609851 * rgb.b;

    float l = 0.8190224 * x + 0.3619063 * y - 0.1288738 * z;
    float m = 0.0329837 * x + 0.9292868 * y + 0.0361447 * z;
    float s = 0.0481772 * x + 0.2642395 * y + 0.6335478 * z;
    float lRoot = pow(max(l, 0.0), 0.3333333);
    float mRoot = pow(max(m, 0.0), 0.3333333);
    float sRoot = pow(max(s, 0.0), 0.3333333);

    return float3(
        0.2104543 * lRoot + 0.7936178 * mRoot - 0.0040720 * sRoot,
        1.9780000 * lRoot - 2.4285922 * mRoot + 0.4505937 * sRoot,
        0.0259040 * lRoot + 0.7827718 * mRoot - 0.8086758 * sRoot
    );
}

float3 oklabToRec2020(float3 lab) {
    float lRoot = lab.x + 0.3963378 * lab.y + 0.2158038 * lab.z;
    float mRoot = lab.x - 0.1055613 * lab.y - 0.0638542 * lab.z;
    float sRoot = lab.x - 0.0894842 * lab.y - 1.2914855 * lab.z;
    float l = lRoot * lRoot * lRoot;
    float m = mRoot * mRoot * mRoot;
    float s = sRoot * sRoot * sRoot;

    float x = 1.2268799 * l - 0.5578150 * m + 0.2813911 * s;
    float y = -0.0405757 * l + 1.1122868 * m - 0.0717111 * s;
    float z = -0.0763729 * l - 0.4214933 * m + 1.5869240 * s;

    return float3(
        1.7166512 * x - 0.3556708 * y - 0.2533663 * z,
        -0.6666844 * x + 1.6164812 * y + 0.0157685 * z,
        0.0176399 * x - 0.0427706 * y + 0.9421031 * z
    );
}

} // namespace

[[stitchable]] float4 filmTone(
    coreimage::sample_t pixel, float exposure, float contrast, float saturation,
    float vibrance, float warmth
) {
    float3 source = max(pixel.rgb, float3(0.0));
    float sourceY = max(dot(source, rec2020Luma), 0.000001);

    // Exposure uses a bounded photographic density curve. The family composes
    // cleanly around fixed black and white points: +1 EV gives deep tones about
    // three times their input density, then progressively reduces that gain
    // through the mids and highlights. This matches the response of modern raw
    // editors much more closely than multiplying RGB and applying a late knee.
    float densityGain = pow(3.05, exposure);
    float exposedY = sourceY * densityGain
        / max(1.0 + (densityGain - 1.0) * sourceY, 0.000001);
    float adjustedStops = log2(max(exposedY, 0.000001) / 0.18);

    // Contrast is an S-curve around 18% gray. A bounded soft-sign curve limits
    // toward both endpoints instead of driving highlights and shadows into clips.
    float contrastPosition = adjustedStops * 0.62;
    float contrastCurve = contrastPosition / (1.0 + abs(contrastPosition));
    adjustedStops += contrast * 1.15 * contrastCurve;
    float adjustedY = 0.18 * exp2(adjustedStops);

    // Contrast adds a normalized film response without making exposure itself
    // collide with a second shoulder.
    float filmY = filmShoulder(adjustedY)
        * (0.18 / max(filmShoulder(0.18), 0.000001));
    float rolloff = clamp(abs(contrast) * 0.23, 0.0, 0.36);
    adjustedY = mix(adjustedY, filmY, rolloff);

    // Retain a hair of printable separation below display white at positive
    // exposure instead of letting the last highlight values quantize together.
    adjustedY -= 0.0035
        * clamp(max(exposure, 0.0), 0.0, 1.0)
        * smoothstep(0.85, 1.0, adjustedY);

    // SDR source values remain below white by construction. Compress only
    // genuinely extended input rather than flattening ordinary upper mids.
    adjustedY = adjustedY > 1.0 ? 0.995 : adjustedY;
    float3 rgb = source * (adjustedY / sourceY);

    // Saturation and Vibrance live in OKLab so equal slider moves feel much more
    // even across hues. Vibrance favors restrained colors, protects skin-like
    // orange hues, and eases off in the brightest part of the image.
    float3 lab = rec2020ToOklab(max(rgb, float3(0.0)));
    float chroma = length(lab.yz);

    // Raising exposure on photographic material does not preserve electronic
    // RGB saturation all the way to white. Compress dye separation gradually
    // through the raised mids, then more firmly in the shoulder. At +1 EV this
    // is calibrated against a Lightroom reference; the user's Saturation and
    // Vibrance controls remain available afterward for intentional color moves.
    float exposureColorWeight = clamp(max(exposure, 0.0), 0.0, 1.0);
    float raisedMidCompression = smoothstep(0.10, 0.75, adjustedY);
    float shoulderCompression = smoothstep(0.75, 0.98, adjustedY);
    float exposureChromaScale = 1.0 - exposureColorWeight
        * (0.45 * raisedMidCompression + 0.18 * shoulderCompression);
    lab.yz *= max(0.30, exposureChromaScale);

    float saturationScale = saturation >= 0.0
        ? 1.0 + saturation * 1.35
        : 1.0 + saturation;
    lab.yz *= saturationScale;

    float directionLength = max(length(lab.yz), 0.000001);
    float2 hueDirection = lab.yz / directionLength;
    float skinDirection = clamp(dot(hueDirection, normalize(float2(0.78, 0.62))), 0.0, 1.0);
    float skinProtection = smoothstep(0.70, 0.94, skinDirection)
        * smoothstep(0.008, 0.055, chroma)
        * (1.0 - smoothstep(0.25, 0.38, chroma));
    float chromaProtection = smoothstep(0.035, 0.28, chroma);
    float highlightProtection = 1.0 - 0.35 * smoothstep(0.72, 1.08, lab.x);
    float vibranceScale = vibrance >= 0.0
        ? 1.0 + vibrance * 1.25 * (1.0 - chromaProtection)
            * (1.0 - 0.92 * skinProtection) * highlightProtection
        : exp2(vibrance * 1.05);
    lab.yz *= max(0.0, vibranceScale);

    // Warmth leans toward a Kodak Gold-like palette: yellow-gold density through
    // the mids and highlights, with cleaner, less-red shadow color separation.
    float highlightTone = smoothstep(0.42, 0.96, lab.x);
    float shadowTone = 1.0 - smoothstep(0.08, 0.46, lab.x);
    float midtoneTone = smoothstep(0.16, 0.52, lab.x)
        * (1.0 - smoothstep(0.68, 1.02, lab.x));
    lab.y += warmth * (0.007 + 0.006 * midtoneTone
        + 0.004 * highlightTone - 0.006 * shadowTone);
    lab.z += warmth * (0.027 + 0.021 * midtoneTone
        + 0.022 * highlightTone - 0.014 * shadowTone);

    // A small density response keeps newly saturated colors rich rather than
    // electronic, then pulls out-of-gamut negative channels toward neutral.
    float colorIncrease = max(0.0, saturationScale * vibranceScale - 1.0);
    lab.x -= min(0.012, colorIncrease * min(chroma, 0.25) * 0.05);
    rgb = oklabToRec2020(lab);
    float y = max(dot(rgb, rec2020Luma), 0.000001);
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float gamutScale = minimum < 0.0 ? y / max(y - minimum, 0.000001) : 1.0;
    rgb = max(float3(0.0), mix(float3(y), rgb, clamp(gamutScale, 0.0, 1.0)));

    // As luminance enters the shoulder, compress only the chroma that no longer
    // fits below display white. This gives film-like highlight desaturation and
    // prevents one channel from clipping early and producing a colored edge.
    float maximum = max(rgb.r, max(rgb.g, rgb.b));
    float colorExcursion = max(maximum - y, 0.0);
    float availableExcursion = max(1.0 - y, 0.0);
    float highlightGamutScale = colorExcursion > availableExcursion
        ? availableExcursion / max(colorExcursion, 0.000001)
        : 1.0;
    rgb = mix(float3(y), rgb, clamp(highlightGamutScale, 0.0, 1.0));
    if (sourceY > 1.0) {
        rgb = min(rgb, float3(0.99));
    }

    return float4(rgb, pixel.a);
}

[[stitchable]] float4 lightShape(
    coreimage::sample_t pixel, float4 extent, float amount, float focus, float pop,
    float bias, float roundness, float2 center, coreimage::destination dest
) {
    float2 uv = (dest.coord() - extent.xy) / extent.zw;
    float2 delta = uv - center;
    float aspect = extent.z / max(extent.w, 1.0);
    delta.x *= mix(1.0, aspect, clamp(roundness, 0.0, 1.0));
    float corner = length(float2(0.5 * mix(1.0, aspect, clamp(roundness, 0.0, 1.0)), 0.5));
    float distanceFromCenter = length(delta) / max(corner, 0.001);
    float inner = mix(0.08, 0.82, clamp(focus, 0.0, 1.0));
    float falloff = smoothstep(inner, 1.0, distanceFromCenter);
    float centerLift = (bias - 0.5) * amount * 0.35 * (1.0 - falloff);
    float edgeLoss = amount * falloff * mix(1.15, 0.8, bias);
    float gain = exp2(centerLift - edgeLoss);
    float3 rgb = pixel.rgb * gain;
    float contrast = 1.0 + (pop - 0.5) * amount * 0.16;
    rgb = max(float3(0.0), (rgb - float3(0.18)) * contrast + float3(0.18));
    return float4(rgb, pixel.a);
}

namespace {

/// How far a point sits into the lens's soft edge, 0 in the focus area.
float lensEdge(float2 coordinate, float4 extent, float falloff, float2 center) {
    float2 uv = (coordinate - extent.xy) / extent.zw;
    float2 delta = uv - center;
    float aspect = extent.z / max(extent.w, 1.0);
    float2 opticalDelta = float2(delta.x, delta.y / max(aspect, 0.0001));
    float cornerRadius = length(float2(0.5, 0.5 / max(aspect, 0.0001)));
    float radius = length(opticalDelta) / max(cornerRadius, 0.0001);
    float inner = mix(0.08, 0.70, clamp(falloff, 0.0, 1.0));
    float outer = mix(0.80, 1.02, clamp(falloff, 0.0, 1.0));
    return smoothstep(inner, outer, radius);
}

} // namespace

[[stitchable]] float4 lensRadialBlur(
    coreimage::sampler source,
    float4 extent,
    float maximumOffset,
    float falloff,
    float2 center,
    coreimage::destination dest
) {
    float2 coordinate = dest.coord();
    float edge = lensEdge(coordinate, extent, falloff, center);

    float2 pixelCenter = extent.xy + center * extent.zw;
    float2 pixelDelta = coordinate - pixelCenter;
    float pixelRadius = length(pixelDelta);
    float2 radial = pixelRadius > 0.0001 ? pixelDelta / pixelRadius : float2(0.0);

    // This is Kromo's polar-space Gaussian expressed directly in Cartesian
    // coordinates: convolution follows the radial axis, and its radius grows
    // continuously as the image leaves the focus area. Forty-nine bilinear
    // samples eliminate the discrete echoes visible in the former 7-tap pass.
    float span = maximumOffset * edge;
    float4 accumulated = float4(0.0);
    float weightSum = 0.0;
    for (int index = -24; index <= 24; index++) {
        float position = float(index) / 24.0;
        float gaussianPosition = position * 2.75;
        float weight = exp(-0.5 * gaussianPosition * gaussianPosition);
        float2 sampleCoordinate = coordinate + radial * position * span;
        accumulated += source.sample(source.transform(sampleCoordinate)) * weight;
        weightSum += weight;
    }
    return accumulated / max(weightSum, 0.000001);
}

[[stitchable]] float4 lensChromatic(
    coreimage::sampler blurredSource,
    float4 extent,
    float falloff,
    float colorFringing,
    float2 center,
    coreimage::destination dest
) {
    float2 coordinate = dest.coord();
    float edge = lensEdge(coordinate, extent, falloff, center);

    float2 pixelCenter = extent.xy + center * extent.zw;
    float2 pixelDelta = coordinate - pixelCenter;

    // Match Kromo's continuous channel enlargement: red remains anchored,
    // green expands slightly, and blue expands farther. Because this samples
    // the already-continuous radial convolution, no colored tap bands appear.
    float separation = clamp(colorFringing, 0.0, 2.0) * edge;
    float greenScale = 0.018 * separation;
    float blueScale = 0.044 * separation;
    float2 greenCoordinate = coordinate - pixelDelta * (greenScale / (1.0 + greenScale));
    float2 blueCoordinate = coordinate - pixelDelta * (blueScale / (1.0 + blueScale));

    float4 anchored = blurredSource.sample(blurredSource.transform(coordinate));
    float green = blurredSource.sample(blurredSource.transform(greenCoordinate)).g;
    float blue = blurredSource.sample(blurredSource.transform(blueCoordinate)).b;
    return float4(max(float3(anchored.r, green, blue), float3(0.0)), anchored.a);
}

[[stitchable]] float4 diffuse(
    coreimage::sample_t source, coreimage::sample_t detail, coreimage::sample_t bloom,
    coreimage::sample_t wide, float amount, float bloomCharacter, float veil,
    float sourceBias, float warmth
) {
    float sourceY = dot(source.rgb, float3(0.2126, 0.7152, 0.0722));
    float haloY = dot(bloom.rgb, float3(0.2126, 0.7152, 0.0722));
    float strength = 1.0 - exp(-3.5 * clamp(amount, 0.0, 1.0));

    float kneeStart = mix(0.02, 0.35, clamp(sourceBias, 0.0, 1.0));
    float kneeEnd = min(1.5, kneeStart + 0.65);
    float flareGate = mix(0.30, 1.0, smoothstep(kneeStart, kneeEnd, haloY));

    // Black diffusion particles retain substantially more shadow density while
    // still allowing nearby practicals to spill into dark surroundings.
    float blackRetention = mix(0.62, 1.0, smoothstep(0.025, 0.25, sourceY));
    float bloomMix = clamp(bloomCharacter, 0.0, 1.0);
    float nearWeight = strength * mix(0.18, 0.30, bloomMix);
    float bloomWeight = strength * mix(0.18, 0.46, bloomMix) * flareGate * blackRetention;
    float wideWeight = strength * mix(0.08, 0.30, bloomMix) * flareGate * blackRetention;
    float veilWeight = strength * clamp(veil, 0.0, 0.5) * 0.35 * blackRetention;

    float rawScatterWeight = nearWeight + bloomWeight + wideWeight + veilWeight;
    float scatterScale = min(1.0, 0.82 / max(rawScatterWeight, 0.0001));
    float scatteredWeight = rawScatterWeight * scatterScale;
    float sourceWeightFinal = 1.0 - scatteredWeight;
    float3 warmthScale = float3(1.0 + warmth * 0.08, 1.0, 1.0 - warmth * 0.04);
    float3 scattered = (detail.rgb * nearWeight
        + bloom.rgb * warmthScale * bloomWeight
        + wide.rgb * warmthScale * (wideWeight + veilWeight)) * scatterScale;
    float3 rgb = max(float3(0.0), source.rgb * sourceWeightFinal + scattered);
    return float4(rgb, source.a);
}

namespace {

/// Straight RGB, black where nothing covers the pixel.
float3 straightRGB(float4 premultiplied) {
    return premultiplied.a > 0.000001 ? premultiplied.rgb / premultiplied.a : float3(0.0);
}

} // namespace

// Premultiplied in and out.
[[stitchable]] float4 halate(
    coreimage::sample_t source, coreimage::sample_t nearBlur, coreimage::sample_t middleBlur,
    coreimage::sample_t farBlur, coreimage::sample_t greenNearBlur, float amount, float tail,
    float colorShift, float saturation, float greenLeakage
) {
    float3 sourceRGB = straightRGB(source);
    float farWeight = mix(0.08, 0.26, clamp(tail, 0.0, 1.0));
    float middleWeight = 0.32;
    float nearWeight = 1.0 - middleWeight - farWeight;
    // Normalize each PSF, then divide by its filtered coverage. Transparent
    // pixels are missing image coverage, not black film exposure. For opaque
    // photographs this reduces to an energy-preserving linear convolution.
    float4 redBlur = nearBlur * nearWeight + middleBlur * middleWeight + farBlur * farWeight;
    float4 greenBlur = greenNearBlur * 0.8 + nearBlur * 0.2;
    float3 redScattered = straightRGB(redBlur);
    float3 greenScattered = straightRGB(greenBlur);
    float redScatter = clamp(amount * mix(0.55, 0.92, saturation), 0.0, 0.85);
    float greenScatter = clamp(
        amount * greenLeakage * mix(0.8, 0.35, saturation) * mix(1.2, 0.75, colorShift),
        0.0, 0.35
    );
    float3 rgb;
    rgb.r = mix(sourceRGB.r, redScattered.r, redScatter);
    rgb.g = mix(sourceRGB.g, greenScattered.g, greenScatter);
    rgb.b = sourceRGB.b;
    return float4(rgb * source.a, source.a);
}

// Premultiplied in and out.
[[stitchable]] float4 landscapeGlowSource(coreimage::sample_t source) {
    float alpha = source.a;
    float3 rgb = max(straightRGB(source), float3(0.0));
    float y = max(dot(rgb, rec2020Luma), 0.0);

    // A wide luminosity selection keeps upper midtones involved while making
    // direct light the dominant emitter. Dark structures contribute no shadow
    // halo to the blur, which is the main failure mode of a global Orton layer.
    float highlightGate = smoothstep(0.14, 0.78, y);
    float emission = highlightGate * mix(0.55, 1.0, highlightGate);
    return float4(rgb * emission * alpha, alpha);
}

// Premultiplied in and out.
[[stitchable]] float4 landscapeGlow(
    coreimage::sample_t source,
    coreimage::sample_t overallBlur,
    coreimage::sample_t middleBlur,
    coreimage::sample_t wideBlur,
    float amount,
    float shadowProtection,
    float detail,
    float preserveHDR
) {
    float sourceAlpha = source.a;
    float3 sourceRGB = max(straightRGB(source), float3(0.0));
    float sourceY = max(dot(sourceRGB, rec2020Luma), 0.0);

    // Two highlight-only scales produce a luminous body and a long atmospheric
    // tail. Because shadows were excluded before the blur, this layer can add
    // light without averaging the source toward gray or creating dark halos.
    float3 glowRGB = max(straightRGB(mix(float4(middleBlur), float4(wideBlur), 0.38)), float3(0.0));

    float normalizedAmount = (1.0 - exp(-2.2 * clamp(amount, 0.0, 1.0)))
        / (1.0 - exp(-2.2));

    // Rebuild the image from a broad color/tonal layer plus its original
    // high-frequency luminance residual. This is the full-frame Orton body:
    // cohesive low-frequency color and light without sacrificing crisp detail.
    float3 overallRGB = max(straightRGB(overallBlur), float3(0.0));
    float overallY = max(dot(overallRGB, rec2020Luma), 0.000001);
    float lowStops = log2(overallY / 0.18);
    float contrastPosition = lowStops * 0.58;
    float contrastCurve = contrastPosition / (1.0 + abs(contrastPosition));
    float ortonLowY = 0.18 * exp2(lowStops + normalizedAmount * 0.16 * contrastCurve);
    float luminousMidtones = smoothstep(0.06, 0.38, overallY)
        * (1.0 - smoothstep(0.68, 1.08, overallY));
    ortonLowY *= 1.0 + normalizedAmount * 0.045 * luminousMidtones;

    float detailResidual = sourceY - overallY;
    float detailRetention = mix(0.82, 1.02, clamp(detail, 0.0, 1.0));
    float reconstructedY = max(
        0.0,
        mix(sourceY, ortonLowY + detailResidual * detailRetention, normalizedAmount)
    );
    float3 tonedSource = sourceY > 0.000001
        ? sourceRGB * (reconstructedY / sourceY)
        : float3(0.0);
    float3 ortonColor = overallRGB * (reconstructedY / overallY);
    float colorMeld = normalizedAmount * mix(0.20, 0.08, clamp(detail, 0.0, 1.0));
    float3 baseRGB = mix(tonedSource, ortonColor, colorMeld);

    // Protect a progressively wider receiving shadow range without a hard mask.
    // Glow remains strongest beside light, then eases near white to retain sky
    // gradients and illuminated cloud structure.
    float shadowKnee = mix(0.008, 0.15, clamp(shadowProtection, 0.0, 1.0));
    float shadowGate = smoothstep(shadowKnee * 0.35, shadowKnee + 0.16, sourceY);
    float highlightProtection = 1.0 - 0.48 * smoothstep(0.72, 1.10, sourceY);
    float glowWeight = normalizedAmount * 0.22 * shadowGate * highlightProtection;
    float headroom = 1.0 - smoothstep(0.58, 1.08, sourceY);
    float3 rgb = max(float3(0.0), baseRGB + glowRGB * glowWeight * mix(0.42, 1.0, headroom));

    // Pull only out-of-range chroma toward neutral. This retains extended
    // luminance for the output transform and avoids channel-clipped sunsets.
    float outputY = max(dot(rgb, rec2020Luma), 0.000001);
    float minimum = min(rgb.r, min(rgb.g, rgb.b));
    float maximum = max(rgb.r, max(rgb.g, rgb.b));
    float lowScale = minimum < 0.0 ? outputY / max(outputY - minimum, 0.000001) : 1.0;
    // HDR has no SDR display-white ceiling. Keep the existing SDR gamut
    // compression but don't turn extended colored highlights into gray.
    float availableHighlight = preserveHDR > 0.5
        ? max(maximum - outputY, 0.0) : max(1.08 - outputY, 0.0);
    float colorExcursion = max(maximum - outputY, 0.0);
    float highScale = colorExcursion > availableHighlight
        ? availableHighlight / max(colorExcursion, 0.000001)
        : 1.0;
    rgb = mix(float3(outputY), rgb, clamp(min(lowScale, highScale), 0.0, 1.0));
    return float4(rgb * sourceAlpha, sourceAlpha);
}

namespace {

float filmHash(float2 p, float seed) {
    // Mix bounded fractional values instead of amplifying GPU-dependent sin
    // approximations. Split the seed so large phases do not swallow pixel
    // differences before the mix. Exact patterns may still vary by GPU.
    float2 phase = float2(floorMod(seed, 1024.0), floor(seed / 1024.0));
    float3 h = fract(float3(p.x + phase.x, p.y + phase.y, p.x + phase.y)
        * float3(0.1031, 0.1030, 0.0973));
    h += dot(h, h.yzx + 33.33);
    return fract((h.x + h.y) * h.z);
}

float filmNoise(float2 p, float seed) {
    float2 cell = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = filmHash(cell, seed);
    float b = filmHash(cell + float2(1.0, 0.0), seed);
    float c = filmHash(cell + float2(0.0, 1.0), seed);
    float d = filmHash(cell + float2(1.0, 1.0), seed);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float filmTriangularNoise(float2 pixel, float seed) {
    float a = filmHash(pixel, seed);
    float b = filmHash(pixel + float2(37.0, 17.0), seed + 113.0);
    float c = filmHash(pixel + float2(11.0, 53.0), seed + 271.0);
    // Match the contrast of the former interpolated field while giving the
    // samples a softer, film-density-like distribution.
    return (a + b + c - 1.5) * 0.36;
}

float filmParticleNoise(float2 coordinate, float2 pixel, float particlePixels, float acutance, float seed) {
    // At normal still-image grain sizes a fresh, distribution-shaped sample per
    // output pixel avoids the lattice and cloudy clumps produced by interpolated
    // value noise. As particles become visibly larger, gently blend in two
    // differently rotated fields so the correlation remains organic rather than
    // aligning to a square grid.
    float independent = filmTriangularNoise(pixel, seed);
    float2 rotatedA = float2(
        coordinate.x * 0.819152 - coordinate.y * 0.573576,
        coordinate.x * 0.573576 + coordinate.y * 0.819152
    );
    float2 rotatedB = float2(
        coordinate.x * 0.422618 + coordinate.y * 0.906308,
        -coordinate.x * 0.906308 + coordinate.y * 0.422618
    );
    float fieldA = filmNoise(rotatedA + float2(19.7, 7.3), seed + 41.0) - 0.5;
    float fieldB = filmNoise(rotatedB * 1.173 + float2(5.1, 23.9), seed + 197.0) - 0.5;
    float correlated = (fieldA * 0.58 + fieldB * 0.42) * 1.52;
    // Start resolving particle scale below one output pixel. This is important
    // for the live preview, where physically small grains would otherwise all
    // collapse to the same single-pixel pattern.
    // Acutance changes how distinctly individual grains resolve: lower values
    // favor the softly correlated dye-cloud fields, while higher values retain
    // more independent, high-frequency particles. Center the offset around the
    // recipe default so existing looks keep their morphology.
    float baseCorrelation = smoothstep(0.22, 1.55, particlePixels);
    float acutanceOffset = mix(0.38, -0.28, clamp(acutance, 0.0, 1.0));
    float correlation = clamp(baseCorrelation + acutanceOffset, 0.0, 1.0);
    // Independent samples have variance 0.0324; the two smoothstep fields
    // have approximately 0.05449. Normalize the blend to the latter so
    // resolution changes its structure without also changing Amount.
    float independentWeight = 1.0 - correlation;
    float blendVariance = independentWeight * independentWeight * 0.0324
        + correlation * correlation * 0.05449;
    return mix(independent, correlated, correlation) * sqrt(0.05449 / blendVariance);
}

} // namespace

// Premultiplied in and out.
[[stitchable]] float4 grain(
    coreimage::sample_t source, coreimage::sample_t densityGuide, float4 extent, float amount,
    float particlePixels, float acutance, float variation, float chroma, float shadowResponse,
    float highlightResponse, float seed, coreimage::destination dest
) {
    float2 coordinate = (dest.coord() - extent.xy) / max(particlePixels, 0.5);
    float2 pixel = floor(dest.coord());
    float primary = filmParticleNoise(coordinate, pixel, particlePixels, acutance, seed);
    float variationAmount = clamp(variation, 0.0, 1.0);
    float alternateScale = mix(1.0, 0.52, variationAmount);
    float varied = filmParticleNoise(
        coordinate * alternateScale + float2(13.7, 29.1),
        pixel + float2(47.0, 31.0),
        particlePixels / alternateScale,
        acutance,
        seed + 431.0
    );
    // Size Variation introduces a genuinely broader second population instead
    // of merely nudging the original scale. Normalize both blends so these
    // character controls reshape grain without acting like hidden Amount knobs.
    float variationMix = variationAmount * 0.44;
    float variationNormalization = 1.0 / sqrt(
        max(0.2, (1.0 - variationMix) * (1.0 - variationMix) + variationMix * variationMix)
    );
    float densityNoise = mix(primary, varied, variationMix) * variationNormalization;

    float4 straightSource = coreimage::unpremultiply(source);
    float4 straightGuide = coreimage::unpremultiply(densityGuide);
    // The renderer works in linear Rec. 2020. Shape visibility in perceptual
    // tones so the shadow peak actually lands in visible darker midtones.
    float linearLuminance = clamp(
        dot(max(straightGuide.rgb, float3(0.0)), float3(0.2627, 0.6780, 0.0593)),
        0.0,
        1.0
    );
    float localLuminance = srgbEncode(linearLuminance);
    float shadowWeight = pow(1.0 - localLuminance, 0.72);
    float endpointResponse = mix(highlightResponse, shadowResponse, shadowWeight);

    // A broad darker-midtone peak, with a quiet toe and an earlier shoulder,
    // avoids both noisy blocked blacks and conspicuous grain in bright skies.
    // This is a perceptual film-look model, not a stock-specific simulation.
    float toeTransition = smoothstep(0.04, 0.40, localLuminance);
    float toeCompression = mix(0.18, 1.0, toeTransition);
    float shoulderTransition = smoothstep(0.50, 1.0, localLuminance);
    float shoulderCompression = mix(1.0, 0.18, shoulderTransition);
    float tonalResponse = endpointResponse * toeCompression * shoulderCompression * 1.4;
    float sigma = amount * tonalResponse * 0.34;
    float densityDelta = densityNoise * sigma;
    // Cancel the mean lift from exponentiating zero-mean density noise. The
    // normalized field variance is 0.05449: 0.5 * ln(10) * variance.
    float densityCompensation = 0.06273 * sigma * sigma;
    float luminanceScale = exp2(-(densityDelta + densityCompensation) * 3.321928);

    float3 chromaNoise = float3(
        filmParticleNoise(coordinate * 0.91 + float2(3.1, 7.7), pixel + float2(7.0, 61.0), particlePixels / 0.91, acutance, seed + 151.0),
        filmParticleNoise(coordinate * 1.07 + float2(11.2, 2.4), pixel + float2(59.0, 13.0), particlePixels / 1.07, acutance, seed + 263.0),
        filmParticleNoise(coordinate * 0.83 + float2(5.8, 13.9), pixel + float2(23.0, 79.0), particlePixels / 0.83, acutance, seed + 379.0)
    );
    // Independent dye-layer variation is separated from the shared silver-density
    // component and made luminance-neutral so Chroma changes color texture rather
    // than overall grain contrast.
    chromaNoise -= float3(dot(chromaNoise, float3(0.2126, 0.7152, 0.0722)));
    // The separate dye records are least convincing when they sparkle in blocked
    // shadows or nearly white highlights. Let their small differences live mostly
    // in the printable density range while the shared silver-density texture
    // continues softly into the extremes.
    float dyeToe = smoothstep(0.15, 0.48, localLuminance);
    float dyeShoulder = 1.0 - smoothstep(0.70, 0.97, localLuminance);
    float dyeCloudResponse = mix(0.16, 1.0, dyeToe * dyeShoulder);
    float chromaStrength = amount * clamp(chroma, 0.0, 1.0) * tonalResponse * dyeCloudResponse * 0.50;
    float3 colorScale = max(float3(0.05), float3(1.0) + chromaNoise * chromaStrength);
    float3 rgb = max(float3(0.0), straightSource.rgb * luminanceScale * colorScale);
    return coreimage::premultiply(float4(rgb, straightSource.a));
}

// The raw grain hash per pixel, for checking its statistics.
[[stitchable]] float4 grainHashField(float seed, coreimage::destination dest) {
    float value = filmHash(floor(dest.coord()), seed);
    return float4(value, value, value, 1.0);
}
