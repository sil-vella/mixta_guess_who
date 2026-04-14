# Points system (short reference)

## When points are awarded

- Only on a **correct** guess (`GamePlayModule` → `RewardsModule.saveReward`).
- **Wrong** answers and **time up** do not add points.

## How many points per correct guess

Configured in `mixta_flutter/lib/plugins/game_plugin/modules/rewards_module/rewardsModule_config/config.dart`:

| Key | Base points |
|-----|-------------|
| `no_hint` | 10 |
| `hint` | 5 |

`RewardsModule.getPoints` multiplies the base by **`levelMultipliers[level]`** (defaults to `1.0` if level missing). Example: level 3, no hint → `10 × 1.5 = 15`.

`levelMaxPoints` in the same config file is **not used** anywhere today (no cap enforced).

## Local storage (SharedPreferences)

- Per category and level: **`points_${category}_level${n}`** — **cumulative** total for that level.
- Guessed names: **`guessed_${category}_level${n}`** (string list).
- **Total across categories:** `FunctionHelperModule.getTotalPoints` sums all `points_*` keys for categories in `available_categories` and each `max_levels_$category`.

## Server sync

- **`POST /update-rewards`** (`mixta_flask/.../rewards_module/rewards_module.py`) with `username`, `category`, `level`, cumulative **`points`**, `guessed_names`, and client-computed **`total_points`**.
- **`user_category_progress`**: row updated **only if** new `points` **>** stored value (monotonic).
- **`users.total_points`**: overwritten from the client’s `total_points` (not recalculated from SQL sum in this handler).
- **Leaderboard** ranks by **`users.total_points`**.

## Level up vs game over

- **Not** driven by point totals. Server compares YAML “all names” for that category/level to **`guessed_names`**; if none missing → **`levelUp`** until max level, else **`endGame`**.

## Key files

| Role | Path |
|------|------|
| Award + hint branch | `mixta_flutter/.../game_play_module/game_play_module.dart` |
| Points math + prefs + API | `mixta_flutter/.../rewards_module/rewards_module.dart` |
| Base × multiplier config | `mixta_flutter/.../rewardsModule_config/config.dart` |
| Total from prefs | `mixta_flutter/.../function_helper_module/function_helper_module.dart` |
| `/update-rewards` | `mixta_flask/.../rewards_module/rewards_module.py` |
| Rankings | `mixta_flask/.../leaderboard_module/leaderboard_module.py` |
