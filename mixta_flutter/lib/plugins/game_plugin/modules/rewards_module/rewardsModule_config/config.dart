class RewardsConfig {
  /// Default points for each type of action
  static const Map<String, int> baseRewards = {
    'no_hint': 10,
    'hint': 5,
  };

  static const Map<String, String> rewardSystem = {
    // 'method': "max_points",
    'method': "guess_all",
  };

  /// Level-based multipliers
  static const Map<int, double> levelMultipliers = {
    1: 1.0,  // Base level, no multiplier
    2: 1.2,  // 20% increase
    3: 1.5,  // 50% increase
    4: 2.0,  // Double points
    5: 2.5,  // 2.5x multiplier
  };

  /// Level max points
  static const Map<int, double> levelMaxPoints = {
    1: 200,
    2: 400,
    3: 650,
    4: 875,
    5: 1100,
  };
}
