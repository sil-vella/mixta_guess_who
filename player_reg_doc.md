# Player registration and persistence

This describes how a **player** (registered username) is created from the app, where data lives, and how duplicate names are prevented.

## Entry point (UI)

- **Screen:** Preferences → **Profile** tab (`mixta_flutter/lib/plugins/main_plugin/screens/preferences_screen/preferences_screen.dart`).
- **When the form shows:** If SharedPreferences has no non-empty `username`, the screen shows `RegisterWidget` with the **Create Player** button (`components/user_register.dart`). If `username` is already set, the profile section is shown instead (no second registration on the same device until prefs are cleared or account removed).

## Client flow

1. User enters a username and taps **Create Player**.
2. **Validation (client only):** Username must be at least **5 characters** after trim (`user_register.dart`).
3. **`LoginModule.registerUser`** (`mixta_flutter/lib/plugins/main_plugin/modules/login_module/login_module.dart`):
   - Sends **`POST /register`** with body `{"username": "<trimmed string>"}` via `ConnectionsModule`.
   - **On success** (JSON has no `error` key): writes local persistence:
     - `username` → string
     - `user_id` → int (parsed from `user_id` in the response)
   - **On error:** returns `{"error": "<server message>"}`; nothing is written to prefs for that attempt.
4. Preferences screen calls `_checkLoginStatus()` after success so the UI switches from the form to the profile block.

## Server flow and DB persistence

- **Route:** `POST /register` — `LoginModule.register_user` in `mixta_flask/plugins/main_plugin/modules/login_module/login_module.py`.
- **Steps:**
  1. Require `username` in JSON; else **400**.
  2. **`SELECT id FROM users WHERE username = %s`**. If a row exists → **400** `Username is already taken`; no insert.
  3. **`INSERT INTO users (username)`**; then select `id` for that username and return **200** with `user_id`, `username`, and message.

The **authoritative** player record is the **`users`** row created in MySQL (see `connection_mysql_module.py`: `users` table with `username VARCHAR(50) UNIQUE NOT NULL`).

## Avoiding duplicates

| Layer | What happens |
|--------|----------------|
| **API** | Explicit existence check before insert; duplicate → **400** + error message. |
| **MySQL** | `username` is **UNIQUE**; concurrent double-submit still cannot create two identical usernames. |
| **App prefs** | After a successful register, `username` is stored; the register UI is hidden until local data is cleared or deleted. |

**Note:** Uniqueness follows the database’s string comparison (collation). There is no separate “check username” endpoint; registration is a single **`/register`** call.

## Related: removing a player

- **Delete my data** (Preferences → **Data** tab) calls `LoginModule.deleteMyData`: may **`POST /delete-user`** then **`SharedPrefManager.clear()`** (or clear-only if guest). Server deletes the user row and related rows; see login module delete handler for details.

## Key files

| Area | Path |
|------|------|
| Prefs screen + register callback | `mixta_flutter/.../preferences_screen/preferences_screen.dart` |
| Create Player form | `mixta_flutter/.../preferences_screen/components/user_register.dart` |
| Register API + prefs write | `mixta_flutter/.../login_module/login_module.dart` |
| `/register` + duplicate check + insert | `mixta_flask/.../login_module/login_module.py` |
| `users` schema | `mixta_flask/.../connection_mysql_module/connection_mysql_module.py` |
