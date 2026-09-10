// Gesture distance is measured in CSS pixels. Small tap jitter must not turn a
// page; a deliberate short flick or a longer, slow swipe turns exactly one.
export function touchPageDirection({ dx, dy, duration, size, vertical = false,
  rtl = false, cancelled = false }) {
  if (cancelled || ![dx, dy, duration, size].every(Number.isFinite) || size <= 0)
    return 0;
  const along = vertical ? dy : dx;
  const across = vertical ? dx : dy;
  if (Math.abs(along) < 12 || Math.abs(along) < Math.abs(across) * 1.3) return 0;
  const threshold = Math.max(24, Math.min(56, size * 0.08));
  const flick = duration > 0 && Math.abs(along) / duration >= 0.35;
  if (Math.abs(along) < threshold && !flick) return 0;
  return (along < 0 ? 1 : -1) * (rtl && !vertical ? -1 : 1);
}
