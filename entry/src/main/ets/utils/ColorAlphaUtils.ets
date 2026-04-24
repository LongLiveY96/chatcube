export function withColorAlpha(color: string, alphaHex: string): string {
  const normalizedAlpha = normalizeAlphaHex(alphaHex)
  if (!isHexColor(color) || normalizedAlpha === '') {
    return color
  }
  if (color.length === 4) {
    return '#' + color.charAt(1) + color.charAt(1) + color.charAt(2) + color.charAt(2) + color.charAt(3) +
      color.charAt(3) + normalizedAlpha
  }
  if (color.length === 7) {
    return color + normalizedAlpha
  }
  if (color.length === 9) {
    return color.substring(0, 7) + normalizedAlpha
  }
  return color
}

function normalizeAlphaHex(alphaHex: string): string {
  let value = alphaHex
  if (value.startsWith('#')) {
    value = value.substring(1)
  }
  if (value.length !== 2) {
    return ''
  }
  if (!isHexPair(value)) {
    return ''
  }
  return value.toUpperCase()
}

function isHexColor(color: string): boolean {
  if (!color.startsWith('#')) {
    return false
  }
  if (color.length !== 4 && color.length !== 7 && color.length !== 9) {
    return false
  }
  for (let i = 1; i < color.length; i++) {
    if (!isHexChar(color.charAt(i))) {
      return false
    }
  }
  return true
}

function isHexPair(value: string): boolean {
  return isHexChar(value.charAt(0)) && isHexChar(value.charAt(1))
}

function isHexChar(value: string): boolean {
  return (value >= '0' && value <= '9') || (value >= 'a' && value <= 'f') || (value >= 'A' && value <= 'F')
}
