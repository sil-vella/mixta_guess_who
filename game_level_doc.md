# Game content: quick add guide

All paths are under `mixta_flask/plugins/game_plugin/` unless noted.

1. **Categories & level count** — `modules/function_helper_module/data/categories.yml`  
   Add a category key and set `levels` (string number). This drives max levels in the app and in `/update-rewards` level-up logic.

2. **Who appears at each level** — `modules/question_module/celeb_data/categoriesed_celeb_names_for_db_populate.yml`  
   Under each level key (`'1'`, `'2'`, …), list **snake_case** ids per category (e.g. `actors: [meryl_streep, …]`). Every id here must exist in `celeb_data.yml` for that level.

3. **Facts & category tags** — `modules/question_module/celeb_data/celeb_data.yml`  
   For each level, each person id has `categories` (list) and `facts` (list of strings). The server picks up to three random facts per round.

4. **Images** — `modules/question_module/celeb_data/images/`  
   Add image files whose names **start with** the same normalized id (lowercase, spaces → `_`). The server builds URLs like `/images/<filename>` and falls back to `default.jpg` if nothing matches.

5. **Restart Flask** after YAML/image changes. The Flutter app loads categories via `GET /get-categories`; no app store change is required for content-only updates.

---

# Mixta “Guess Who” game — reference

## Purpose

Players see four face images and short clues; they pick the correct celebrity for the current **category** and **level**. Progress (guessed names, points, level) can sync to MySQL when a username is registered.

## Main components

| Piece | Location / role |
|--------|------------------|
| Categories & max levels | `function_helper_module/data/categories.yml` → exposed as `GET /get-categories` |
| Name pools per level | `question_module/celeb_data/categoriesed_celeb_names_for_db_populate.yml` |
| Facts & metadata | `question_module/celeb_data/celeb_data.yml` (keys match name ids) |
| Image files | `question_module/celeb_data/images/` |
| Question API | `POST /get-question` (body: `level`, `category`, `guessed_names`) — picks a name not yet guessed, loads facts, returns `image_url` + distractor image URLs |
| Static images | `GET /images/<filename>` served from the images folder |
| Rewards / level-up | `POST /update-rewards` — compares guessed list to the full YAML pool; sets `levelUp` / `endGame` |

## Client (Flutter)

- **SharedPreferences** holds `category`, `level_<category>`, `points_<category>_level<N>`, `guessed_<category>_level<N>`, `available_categories`, `max_levels_<category>`, auth fields, etc.
- **Game flow:** `GamePlayModule` requests a question with the current guessed list; on correct answer, `RewardsModule` updates prefs and calls `/update-rewards`.
- **Progression:** Server declares level complete when **all** names in the YAML pool for that category/level are guessed; then `levelUp` until `max_level` from `categories.yml`, else `endGame`.
- **Profile → Data tab:** “Delete my data” clears local prefs and, if registered, deletes the user row and related rows in MySQL via `POST /delete-user`.

## Server (Flask + MySQL)

- Tables (created by `ConnectionMySqlModule`): `users`, `user_category_progress`, `guessed_names`.
- Docker volume `mixta_mysql_data` stores MySQL data locally when using `docker-compose.debug.yml`.

## Performance note

`celeb_data.yml` is large; each `get-question` load can be slow until you add caching or split data. Consider keeping YAML lean or loading once at startup.

## Related scripts

- Local web run with filtered logs: `playbooks/frontend/launch_chrome.sh` (optional `SERVER_LOG_FILE`).
