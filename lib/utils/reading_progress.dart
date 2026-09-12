/// The reader stores a fraction, not a percentage on a 0..100 scale.
/// A missing/non-finite value has no usable progress; never infer another unit.
double normalizeReadingProgress(num? value) =>
    value == null || !value.isFinite ? 0.0 : value.clamp(0, 1).toDouble();
