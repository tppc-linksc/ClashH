const SUPPORTED_SCHEMES: string[] = [
  'ss://', 'vmess://', 'vless://', 'trojan://', 'hysteria://', 'hysteria2://',
  'tuic://', 'wireguard://', 'http://', 'https://'
];

export function normalizeProfileInput(rawValue: string): string {
  const value = rawValue.trim();
  if (value.length === 0) return '';
  const normalized = value.toLowerCase();
  for (const scheme of SUPPORTED_SCHEMES) {
    if (normalized.startsWith(scheme)) return value;
  }
  return value;
}

export function isHttpSubscription(value: string): boolean {
  const normalized = value.trim().toLowerCase();
  return normalized.startsWith('https://') || normalized.startsWith('http://');
}
