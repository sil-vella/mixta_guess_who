from flask import request, jsonify
from tools.logger.custom_logging import custom_log
from core.managers.module_manager import ModuleManager

class RewardsModule:
    def __init__(self, app_manager=None):
        """Initialize RewardsModule and retrieve necessary modules."""
        self.app_manager = app_manager
        self.module_manager = self.app_manager.module_manager if self.app_manager else ModuleManager()  # ✅ Store once

        self.connection_module = self.get_connection_module()
        self.question_module = self.get_question_module()


        if not self.connection_module:
            raise RuntimeError("RewardsModule: Failed to retrieve ConnectionModule from ModuleManager.")
        if not self.question_module:
            raise RuntimeError("RewardsModule: Failed to retrieve QuestionModule from ModuleManager.")

        self.register_routes()
        custom_log("✅ RewardsModule initialized.")

    def get_connection_module(self):
        """Retrieve ConnectionModule from ModuleManager."""
        return self.module_manager.get_module("connection_module")

    def get_question_module(self):
        """Retrieve QuestionModule from ModuleManager."""
        return self.module_manager.get_module("question_module")

    def _get_names_from_yaml(self, category, level):
        """Retrieve all names for a category and level from YAML using QuestionModule."""
        
        custom_log(f"🔍 [_get_names_from_yaml] Start: category={category}, level={level}")

        if not self.question_module:
            custom_log("❌ [_get_names_from_yaml] QuestionModule instance is not available.")
            return []

        # ✅ Fetch NAMES_YAML_PATH dynamically
        names_yaml_path = getattr(self.question_module, "NAMES_YAML_PATH", None)
        custom_log(f"🗂️ [_get_names_from_yaml] Retrieved NAMES_YAML_PATH: {names_yaml_path}")

        if not names_yaml_path:
            custom_log("❌ [_get_names_from_yaml] QuestionModule does not have a valid NAMES_YAML_PATH.")
            return []

        # ✅ Load YAML data
        try:
            questions = self.question_module.load_yaml(names_yaml_path)
            custom_log(f"📄 [_get_names_from_yaml] YAML loaded successfully. Keys found: {list(questions.keys())}")
        except Exception as e:
            custom_log(f"❌ [_get_names_from_yaml] Failed to load YAML. Error: {str(e)}")
            return []

        if not questions or str(level) not in questions:
            custom_log(f"⚠️ [_get_names_from_yaml] No data found for level {level}. Available levels: {list(questions.keys())}")
            return []

        # ✅ Log structure of level
        level_data = questions[str(level)]
        custom_log(f"🧐 [_get_names_from_yaml] Data for level {level}: {level_data}")

        # ✅ Fix for category-based lists
        try:
            if isinstance(level_data, dict):  # Check if structure is correct
                if category in level_data and isinstance(level_data[category], list):
                    all_names = [name.lower() for name in level_data[category]]
                    custom_log(f"✅ [_get_names_from_yaml] Retrieved {len(all_names)} names for category '{category}' at level {level}. Names: {all_names}")
                    return all_names
                else:
                    custom_log(f"⚠️ [_get_names_from_yaml] Category '{category}' not found at level {level}. Available categories: {list(level_data.keys())}")
            else:
                custom_log(f"⚠️ [_get_names_from_yaml] Unexpected data format for level {level}. Expected dict but got {type(level_data)}.")

        except Exception as e:
            custom_log(f"❌ [_get_names_from_yaml] Error processing names: {str(e)}")
            return []

        return []

    def register_routes(self):
        """Register rewards route."""
        if not self.connection_module:
            raise RuntimeError("ConnectionModule is not available yet.")

        self.connection_module.register_route('/update-rewards', self.update_rewards, methods=['POST'])
        custom_log("🌐 RewardsModule: `/update-rewards` route registered.")

    def update_rewards(self):
        """Handles updating user points, levels, and guessed names per category & level."""
        custom_log(f"📢 [update_rewards] Request received: {request.get_json()}")

        data = request.get_json()
        category = data.get("category")
        level = data.get("level")
        new_points = data.get("points")
        guessed_names = data.get("guessed_names", [])  # ✅ Updated guessed list
        username_raw = data.get("username")
        username = (username_raw or "").strip() or None
        client_total_points = data.get("total_points")  # Optional client hint; server recalculates authoritative value

        try:
            level = int(level)
            new_points = int(new_points)
        except (TypeError, ValueError):
            custom_log(f"❌ [update_rewards] Invalid level/points payload | level={level!r} | points={new_points!r}")
            return jsonify({"error": "Invalid level or points"}), 400

        if not category:
            custom_log("❌ [update_rewards] Missing or empty 'category'.")
            return jsonify({"error": "Category is required"}), 400

        custom_log(
            f"📜 [update_rewards] category={category} level={level} points={new_points} "
            f"mode={'registered' if username else 'guest'} username={username!r}"
        )
        custom_log(f"📜 Updated guessed names received: {guessed_names}")

        # ✅ Fetch all available names for this level from YAML (shared by guest + registered)
        all_names_at_level = self._get_names_from_yaml(category, level)
        custom_log(f"📜 Total names to guess for '{category}' Level {level}: {all_names_at_level}")

        # ✅ Find missing names (YAML names are lowercased; normalize client list for comparison)
        guessed_set = {str(n).lower() for n in (guessed_names or []) if n is not None and str(n).strip()}
        missing_names = set(all_names_at_level) - guessed_set
        custom_log(f"🔍 Missing names to guess: {missing_names}")

        # ✅ Get FunctionHelperModule
        custom_log("🔍 Fetching FunctionHelperModule...")
        module_manager = self.app_manager.module_manager if self.app_manager else ModuleManager()
        function_helper_module = module_manager.get_module("function_helper_module")

        if not function_helper_module:
            custom_log("❌ [update_rewards] FunctionHelperModule not available.")
            return jsonify({"error": "FunctionHelperModule not available"}), 500

        # ✅ Load category data to get max level
        category_data = function_helper_module._load_categories_data()
        max_level = int(category_data.get(category, {}).get("levels", 1))
        custom_log(f"📊 Loaded category data for '{category}' | Max Level: {max_level}")

        # ✅ Determine level_up / end_game (same rules for guest and registered)
        level_up = False
        end_game = False
        if all_names_at_level and not missing_names:
            if level < max_level:
                level_up = True
                custom_log(f"🎯 All names guessed — level up to {level + 1}")
            else:
                end_game = True
                custom_log(f"🏆 Max level reached in {category}. End game.")

        # ✅ Guest / anonymous: no DB writes; return flags so the client can progress locally
        if not username:
            guest_total = 0
            try:
                guest_total = int(client_total_points) if client_total_points is not None else 0
            except (TypeError, ValueError):
                guest_total = 0
            response = {
                "message": "Rewards acknowledged (guest)",
                "levelUp": level_up,
                "endGame": end_game,
                "total_points": guest_total,
            }
            custom_log(f"✅ [update_rewards] Guest response (no DB): {response}")
            return jsonify(response), 200

        # ✅ Fetch user_id using username
        user_query = "SELECT id FROM users WHERE username = %s;"
        user_data = self.connection_module.fetch_from_db(user_query, (username,), as_dict=True)

        if not user_data:
            custom_log(f"❌ No user found for username: {username}")
            return jsonify({"error": "User not found"}), 404

        user_id = user_data[0]["id"]

        # ✅ Fetch current progress
        progress_query = """
        SELECT points FROM user_category_progress WHERE user_id = %s AND category = %s AND level = %s
        """
        progress_data = self.connection_module.fetch_from_db(progress_query, (user_id, category, level), as_dict=True)
        current_points = progress_data[0]["points"] if progress_data else 0

        # ✅ Only update if new points are greater
        if new_points > current_points:
            if progress_data:
                update_query = """
                UPDATE user_category_progress SET points = %s WHERE user_id = %s AND category = %s AND level = %s
                """
                self.connection_module.execute_query(update_query, (new_points, user_id, category, level))
                custom_log(f"🔄 Updated points for user {user_id} in {category} Level {level}: {new_points}")
            else:
                insert_query = """
                INSERT INTO user_category_progress (user_id, category, level, points) VALUES (%s, %s, %s, %s)
                """
                self.connection_module.execute_query(insert_query, (user_id, category, level, new_points))
                custom_log(f"✅ Inserted new progress for user {user_id} in {category} Level {level}: {new_points}")

        # ✅ Insert new guessed names directly
        if guessed_names:
            custom_log(f"📜 Saving guessed names for user {user_id} in {category} Level {level}: {guessed_names}")

            for guessed_name in guessed_names:
                insert_query = """
                INSERT IGNORE INTO guessed_names (user_id, category, level, guessed_name) VALUES (%s, %s, %s, %s)
                """  # ✅ Prevent duplicate inserts
                self.connection_module.execute_query(insert_query, (user_id, category, level, guessed_name))
                custom_log(f"✅ Added guessed name '{guessed_name}' for user {user_id} in {category} Level {level}.")

        # ✅ Update user's total points in `users` using authoritative DB sum (not frontend value)
        if client_total_points is not None:
            custom_log(
                f"ℹ️ [update_rewards] Client total_points hint received: {client_total_points} (server will recompute)"
            )

        total_query = """
        SELECT COALESCE(SUM(points), 0) AS total_points
        FROM user_category_progress
        WHERE user_id = %s
        """
        total_data = self.connection_module.fetch_from_db(total_query, (user_id,), as_dict=True) or []
        db_total_points = int(total_data[0]["total_points"]) if total_data else 0

        update_total_points_query = """
        UPDATE users SET total_points = %s WHERE id = %s
        """
        self.connection_module.execute_query(update_total_points_query, (db_total_points, user_id))
        custom_log(f"✅ Total points updated for user {user_id}: {db_total_points} (db sum)")

        response = {
            "message": "Rewards updated successfully",
            "levelUp": level_up,
            "endGame": end_game,
            "total_points": db_total_points,
        }

        custom_log(f"✅ [update_rewards] Response Sent: {response}")
        return jsonify(response), 200
