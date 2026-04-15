import bcrypt
import hashlib
from flask import request, jsonify
from tools.logger.custom_logging import custom_log
from core.managers.module_manager import ModuleManager
import jwt
import yaml
import os
from datetime import datetime, timedelta
class LoginModule:
    def __init__(self, app_manager=None):
        """Initialize the LoginModule."""
        self.app_manager = app_manager
        self.connection_module = self.get_connection_module()
        self.SECRET_KEY = "your_secret_key"

        if not self.connection_module:
            raise RuntimeError("LoginModule: Failed to retrieve ConnectionModule from ModuleManager.")

        custom_log("✅ LoginModule initialized.")

    def get_connection_module(self):
        """Retrieve ConnectionModule from ModuleManager."""
        module_manager = self.app_manager.module_manager if self.app_manager else ModuleManager()
        connection_module = module_manager.get_module("connection_module")

        if not connection_module:
            custom_log("❌ ConnectionModule not found in ModuleManager.")
        
        return connection_module


    def register_routes(self):
        """Register authentication routes."""
        if not self.connection_module:
            raise RuntimeError("ConnectionModule is not available yet.")

        self.connection_module.register_route('/register', self.register_user, methods=['POST'])
        self.connection_module.register_route('/login', self.login_user, methods=['POST'])
        self.connection_module.register_route('/delete-user', self.delete_user_request, methods=['POST'])  # ✅ Register route
        self.connection_module.register_route('/sync-progress', self.sync_progress_request, methods=['POST'])

        custom_log("🌐 LoginModule: Authentication routes registered successfully.")

    def delete_user_request(self):
        """API Endpoint to delete a user and their data. Accepts user_id and/or username."""
        try:
            data = request.get_json() or {}
            user_id = data.get("user_id")
            username = data.get("username")
            custom_log(f"🗑️ [delete-user] Incoming | user_id={user_id!r} | username={username!r} | origin={request.headers.get('Origin')}")

            if user_id is None and username:
                row = self.connection_module.fetch_from_db(
                    "SELECT id FROM users WHERE username = %s;",
                    (username,),
                    as_dict=True,
                )
                if not row:
                    custom_log(f"🗑️ [delete-user] No DB row for username={username!r} → 404")
                    return jsonify({"error": "User not found"}), 404
                user_id = row[0]["id"]
                custom_log(f"🗑️ [delete-user] Resolved user_id={user_id} from username")

            if user_id is None:
                custom_log("🗑️ [delete-user] Missing user_id and username → 400")
                return jsonify({"error": "user_id or username is required"}), 400

            response, status_code = self.delete_user_data(user_id)
            custom_log(f"🗑️ [delete-user] delete_user_data finished | status_code={status_code} | response={response}")
            return jsonify(response), status_code

        except Exception as e:
            custom_log(f"❌ Error in delete-user API: {e}")
            return jsonify({"error": "Server error"}), 500

    def sync_progress_request(self):
        """Sync existing local progress to the newly registered account."""
        try:
            data = request.get_json() or {}
            user_id = data.get("user_id")
            username = data.get("username")
            category_progress = data.get("category_progress") or {}
            guessed_names = data.get("guessed_names") or {}
            total_points = data.get("total_points")

            custom_log(
                f"🔄 [sync-progress] Incoming | user_id={user_id!r} | username={username!r} | "
                f"category_progress_keys={list(category_progress.keys()) if isinstance(category_progress, dict) else 'invalid'} | "
                f"guessed_categories={list(guessed_names.keys()) if isinstance(guessed_names, dict) else 'invalid'} | "
                f"total_points={total_points!r}"
            )

            if user_id is None and username:
                row = self.connection_module.fetch_from_db(
                    "SELECT id FROM users WHERE username = %s;",
                    (username,),
                    as_dict=True,
                )
                if not row:
                    return jsonify({"error": "User not found"}), 404
                user_id = row[0]["id"]

            if user_id is None:
                return jsonify({"error": "user_id or username is required"}), 400

            if not isinstance(category_progress, dict):
                category_progress = {}
            if not isinstance(guessed_names, dict):
                guessed_names = {}

            if category_progress:
                self._save_category_progress(user_id, category_progress)
            if guessed_names:
                self._save_guessed_names(user_id, guessed_names)

            # Authoritative total matches rewards/leaderboard: SUM(per-level rows)
            self._recompute_user_total_points_from_progress(user_id)

            if total_points is not None:
                try:
                    client_hint = int(total_points)
                except (TypeError, ValueError):
                    client_hint = None
                if client_hint is not None:
                    custom_log(
                        f"ℹ️ [sync-progress] client total_points hint={client_hint} "
                        f"(stored total is DB sum after sync)"
                    )

            custom_log(f"✅ [sync-progress] completed for user_id={user_id}")
            return jsonify({
                "message": "Progress synced successfully",
                "user_id": user_id,
            }), 200

        except Exception as e:
            custom_log(f"❌ [sync-progress] error: {e}")
            return jsonify({"error": "Server error"}), 500



    def hash_password(self, password):
        """Hash the password using bcrypt."""
        salt = bcrypt.gensalt()
        return bcrypt.hashpw(password.encode(), salt).decode()

    def check_password(self, password, hashed_password):
        """Check if a given password matches the stored hash."""
        return bcrypt.checkpw(password.encode(), hashed_password.encode())

    def _save_guessed_names(self, user_id, guessed_names):
        """Stores guessed names per category & level."""
        try:
            insert_query = """
            INSERT INTO guessed_names (user_id, category, level, guessed_name) 
            VALUES (%s, %s, %s, %s)
            ON DUPLICATE KEY UPDATE guessed_name = guessed_name;
            """

            for category, levels in guessed_names.items():
                for level_str, names in levels.items():
                    level = int(level_str.replace("level_", ""))  # ✅ Convert "level_1" -> 1

                    for name in names:
                        self.connection_module.execute_query(insert_query, (user_id, category, level, name))

            custom_log(f"✅ Guessed names saved for user {user_id}: {guessed_names}")

        except Exception as e:
            custom_log(f"❌ Error saving guessed names: {e}")

    def _recompute_user_total_points_from_progress(self, user_id):
        """Set users.total_points from SUM(user_category_progress.points) (same as rewards flow)."""
        try:
            total_query = """
            SELECT COALESCE(SUM(points), 0) AS total_points
            FROM user_category_progress
            WHERE user_id = %s
            """
            total_data = self.connection_module.fetch_from_db(total_query, (user_id,), as_dict=True) or []
            db_total = int(total_data[0]["total_points"]) if total_data else 0
            self.connection_module.execute_query(
                "UPDATE users SET total_points = %s WHERE id = %s",
                (db_total, user_id),
            )
            custom_log(f"✅ [sync-progress] users.total_points set to {db_total} for user_id={user_id}")
        except Exception as e:
            custom_log(f"❌ [sync-progress] recompute total_points failed: {e}")

    def _get_category_progress(self, user_id):
        """Fetches category-based levels & points."""
        query = """
        SELECT category, level, points FROM user_category_progress WHERE user_id = %s;
        """
        result = self.connection_module.fetch_from_db(query, (user_id,), as_dict=True)

        return {row["category"]: {"level": row["level"], "points": row["points"]} for row in result} if result else {}

    def _save_category_progress(self, user_id, category_progress):
        """Saves per-level points (matches update_rewards / leaderboard SUM)."""
        try:
            insert_query = """
                INSERT INTO user_category_progress (user_id, category, level, points)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE points = VALUES(points);
            """
            for category, progress in category_progress.items():
                if not isinstance(progress, dict):
                    continue
                level_points = progress.get("level_points")
                if isinstance(level_points, dict) and level_points:
                    for level_str, pts in level_points.items():
                        try:
                            lvl = int(str(level_str).replace("level_", ""))
                            p = int(pts)
                        except (TypeError, ValueError):
                            custom_log(f"⚠️ [_save_category_progress] skip bad level/points: {level_str!r} {pts!r}")
                            continue
                        self.connection_module.execute_query(
                            insert_query, (user_id, category, lvl, p)
                        )
                    custom_log(
                        f"✅ [_save_category_progress] user={user_id} category={category} "
                        f"levels_written={list(level_points.keys())}"
                    )
                else:
                    # Legacy payload: one aggregated row (older clients)
                    points = int(progress.get("points", 0) or 0)
                    level = int(progress.get("level", 1) or 1)
                    self.connection_module.execute_query(
                        insert_query, (user_id, category, level, points)
                    )
                    custom_log(
                        f"✅ [_save_category_progress] legacy row user={user_id} category={category} "
                        f"level={level} points={points}"
                    )

            custom_log(f"✅ Category progress saved for user {user_id}: {list(category_progress.keys())}")

        except Exception as e:
            custom_log(f"❌ Error saving category progress: {e}")


    def register_user(self):
        """Registers a user if the username is available."""
        try:
            data = request.get_json()
            username = data.get("username")

            if not username:
                return jsonify({"error": "Username is required"}), 400

            # ✅ Check if username already exists
            query = "SELECT id FROM users WHERE username = %s;"
            existing_user = self.connection_module.fetch_from_db(query, (username,))

            if existing_user:
                return jsonify({"error": "Username is already taken"}), 400

            # ✅ Insert new user with username only
            insert_query = "INSERT INTO users (username) VALUES (%s);"
            self.connection_module.execute_query(insert_query, (username,))

            # ✅ Fetch user ID of newly created user
            user_id_query = "SELECT id FROM users WHERE username = %s;"
            user_result = self.connection_module.fetch_from_db(user_id_query, (username,), as_dict=True)

            if not user_result:
                return jsonify({"error": "User registration failed."}), 500

            user_id = user_result[0]["id"]

            return jsonify({
                "message": "User registered successfully",
                "user_id": user_id,
                "username": username
            }), 200

        except Exception as e:
            custom_log(f"❌ Error registering user: {e}")
            return jsonify({"error": "Server error"}), 500



    def login_user(self):
        """Handles user login and retrieves category-based progress & guessed names."""
        try:
            data = request.get_json()
            email = data.get("email")
            password = data.get("password")

            query = "SELECT id, username, password FROM users WHERE email = %s;"
            user = self.connection_module.fetch_from_db(query, (email,), as_dict=True)

            if not user or not self.check_password(password, user[0]['password']):
                return jsonify({"error": "Invalid credentials"}), 401

            user_id = user[0]['id']
            category_progress = self._get_category_progress(user_id)
            guessed_names = self._get_guessed_names(user_id)

            custom_log(f"❌ category prog {category_progress}")


            token = jwt.encode({"user_id": user_id, "exp": datetime.utcnow() + timedelta(hours=24)}, self.SECRET_KEY, algorithm="HS256")

            return jsonify({"message": "Login successful", "user": {"id": user_id, "username": user[0]["username"], "category_progress": category_progress, "guessed_names": guessed_names}, "token": token}), 200

        except Exception as e:
            custom_log(f"❌ Error during login: {e}")
            return jsonify({"error": "Server error"}), 500

    def _get_guessed_names(self, user_id):
        """Retrieves guessed names grouped by category & level."""
        try:
            query = """
            SELECT category, level, guessed_name 
            FROM guessed_names WHERE user_id = %s;
            """
            results = self.connection_module.fetch_from_db(query, (user_id,), as_dict=True)

            guessed_names = {}

            for row in results:
                category = row["category"]
                level = f"level_{row['level']}"  # ✅ Convert 1 -> "level_1"
                name = row["guessed_name"]

                if category not in guessed_names:
                    guessed_names[category] = {}

                if level not in guessed_names[category]:
                    guessed_names[category][level] = []

                guessed_names[category][level].append(name)

            custom_log(f"📜 Retrieved guessed names for user {user_id}: {guessed_names}")
            return guessed_names

        except Exception as e:
            custom_log(f"❌ Error fetching guessed names: {e}")
            return {}

    def delete_user_data(self, user_id):
        """Delete all data associated with a user before removing them from the database."""
        try:
            if not self.connection_module:
                return {"error": "Database connection is unavailable"}, 500

            # ✅ Delete guessed names
            custom_log(f"🗑️ Deleting guessed names for User ID {user_id}...")
            self.connection_module.execute_query("DELETE FROM guessed_names WHERE user_id = %s", (user_id,))

            # ✅ Delete user progress
            custom_log(f"🗑️ Deleting category progress for User ID {user_id}...")
            self.connection_module.execute_query("DELETE FROM user_category_progress WHERE user_id = %s", (user_id,))

            # ✅ Finally, delete the user
            custom_log(f"🗑️ Deleting User ID {user_id} from users table...")
            self.connection_module.execute_query("DELETE FROM users WHERE id = %s", (user_id,))

            custom_log(f"✅ Successfully deleted all data for User ID {user_id}.")
            return {"message": f"User ID {user_id} and all associated data deleted successfully"}, 200

        except Exception as e:
            custom_log(f"❌ Error deleting user data: {e}")
            return {"error": f"Failed to delete user data: {str(e)}"}, 500
