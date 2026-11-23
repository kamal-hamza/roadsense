//! The use case's three success metrics, computed from aggregated counts.

/// How often drivers braked hard at hotspots, split by whether they were warned (metric 1).
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct PassCounts {
    pub warned: u32,
    pub warned_with_hard_brake: u32,
    /// Missed or suppressed (muted) passes: the comparison group.
    pub unwarned: u32,
    pub unwarned_with_hard_brake: u32,
}

impl PassCounts {
    /// Share of warned passes with a hard brake, or `None` with no warned passes yet.
    pub fn warned_hard_brake_rate(&self) -> Option<f64> {
        rate(self.warned_with_hard_brake, self.warned)
    }

    pub fn unwarned_hard_brake_rate(&self) -> Option<f64> {
        rate(self.unwarned_with_hard_brake, self.unwarned)
    }
}

/// The three success metrics from the use case.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SuccessMetrics {
    /// Metric 1: do warned drivers brake hard less often at hotspots?
    pub passes: PassCounts,
    /// Metric 2: share of active drivers who muted or turned off warnings.
    pub mute_rate: Option<f64>,
    /// Metric 3: share of new devices still active 7+ days after their first trip.
    pub week_one_retention: Option<f64>,
}

/// `part / whole`, or `None` when there's nothing to divide.
pub fn rate(part: u32, whole: u32) -> Option<f64> {
    (whole > 0).then(|| f64::from(part) / f64::from(whole))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rates_need_a_denominator() {
        let counts = PassCounts {
            warned: 10,
            warned_with_hard_brake: 1,
            unwarned: 0,
            unwarned_with_hard_brake: 0,
        };
        assert_eq!(counts.warned_hard_brake_rate(), Some(0.1));
        assert_eq!(counts.unwarned_hard_brake_rate(), None);
    }
}
