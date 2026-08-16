.pragma library

// Theme synthesis helpers. Omarchy themes provide semantic colors, but a
// plugin still has to combine them without assuming that the surface is dark.
// These helpers keep decorative tints on-brand while enforcing readable text
// and non-text contrast for every palette, including the light themes.

function clamp(value, minimum, maximum) {
  var number = Number(value)
  if (!isFinite(number)) return minimum
  return Math.max(minimum, Math.min(maximum, number))
}

function mix(from, to, amount) {
  var ratio = clamp(amount, 0, 1)
  return Qt.rgba(
    from.r + (to.r - from.r) * ratio,
    from.g + (to.g - from.g) * ratio,
    from.b + (to.b - from.b) * ratio,
    from.a + (to.a - from.a) * ratio)
}

function linearChannel(channel) {
  var value = clamp(channel, 0, 1)
  return value <= 0.04045
    ? value / 12.92
    : Math.pow((value + 0.055) / 1.055, 2.4)
}

function luminance(color) {
  return 0.2126 * linearChannel(color.r)
    + 0.7152 * linearChannel(color.g)
    + 0.0722 * linearChannel(color.b)
}

function contrast(first, second) {
  var firstLuminance = luminance(first)
  var secondLuminance = luminance(second)
  var light = Math.max(firstLuminance, secondLuminance)
  var dark = Math.min(firstLuminance, secondLuminance)
  return (light + 0.05) / (dark + 0.05)
}

// Move foreground toward its surface as far as possible while retaining the
// requested WCAG contrast. This produces a quiet tone that works in both
// light and dark themes; a one-way shade transform cannot do that.
function readableMuted(foreground, background, minimumContrast) {
  var target = Math.max(1, Number(minimumContrast) || 1)
  if (contrast(foreground, background) < target) return foreground

  var low = 0
  var high = 1
  var best = foreground
  for (var index = 0; index < 14; index++) {
    var middle = (low + high) / 2
    var candidate = mix(foreground, background, middle)
    if (contrast(candidate, background) >= target) {
      best = candidate
      low = middle
    } else {
      high = middle
    }
  }
  return best
}

function ensureContrast(preferred, fallback, background, minimumContrast) {
  var target = Math.max(1, Number(minimumContrast) || 1)
  if (contrast(preferred, background) >= target) return preferred
  if (contrast(fallback, background) >= target)
    return readableMuted(fallback, background, target)
  return contrast(preferred, background) >= contrast(fallback, background)
    ? preferred
    : fallback
}

function contrastText(fill, first, second) {
  return contrast(first, fill) >= contrast(second, fill) ? first : second
}
