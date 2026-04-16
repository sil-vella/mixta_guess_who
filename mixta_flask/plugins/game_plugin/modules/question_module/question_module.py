import yaml
import os
import re
import random
import time
from flask import request, jsonify, send_from_directory
from tools.logger.custom_logging import custom_log
from core.managers.module_manager import ModuleManager

class QuestionModule:
    def __init__(self, app_manager=None):
        """Initialize QuestionModule and register routes."""
        self.app_manager = app_manager
        self.connection_module = self.get_connection_module()
        self.BASE_DIR = os.path.dirname(os.path.abspath(__file__))
        self.IMAGE_DIR = os.path.join(self.BASE_DIR, "celeb_data", "images")
        self.NAMES_YAML_PATH = os.path.join(self.BASE_DIR, "celeb_data", "categoriesed_celeb_names_for_db_populate.yml")
        self.DATA_YAML_PATH = os.path.join(self.BASE_DIR, "celeb_data", "celeb_data.yml")
        # Parsed YAML is large (~1.6MB celeb_data.yml); reload only when file mtime changes.
        self._yaml_cache = {}
        self._image_files_cache = None
        self._image_dir_mtime = None

        if not self.connection_module:
            raise RuntimeError("QuestionModule: Failed to retrieve ConnectionModule from ModuleManager.")

        custom_log("✅ QuestionModule initialized.")

        # ✅ Ensure routes are registered upon module initialization
        self.register_routes()

        # One-time load so the first client request does not parse multi‑MB YAML under HTTP timeout.
        custom_log("⏳ QuestionModule: preloading YAML caches (may take ~30s once for celeb_data.yml)...")
        warm0 = time.perf_counter()
        self.load_yaml(self.NAMES_YAML_PATH)
        self.load_yaml(self.DATA_YAML_PATH)
        self._list_image_files()
        custom_log(f"✅ QuestionModule: YAML/image caches warmed in {int((time.perf_counter() - warm0) * 1000)}ms")


    def get_connection_module(self):
        """Retrieve ConnectionModule from ModuleManager."""
        module_manager = self.app_manager.module_manager if self.app_manager else ModuleManager()
        return module_manager.get_module("connection_module")

    def register_routes(self):
        """Register question-related routes."""
        if not self.connection_module:
            raise RuntimeError("ConnectionModule is not available yet.")

        # ✅ Register the get-question route
        self.connection_module.register_route('/get-question', self.get_question, methods=['POST'])
        custom_log("🌐 QuestionModule: `/get-question` route registered.")

        # ✅ Register the static image serving route
        def serve_image(filename):
            """Serves images from the /images/ directory."""
            return send_from_directory(self.IMAGE_DIR, filename)

        self.connection_module.register_route('/images/<path:filename>', serve_image, methods=['GET'])
        custom_log("🖼️ QuestionModule: `/images/<filename>` route registered to serve static images.")

    def load_yaml(self, file_path):
        """Load and return YAML data from a given file path (cached by file mtime)."""
        try:
            mtime = os.path.getmtime(file_path)
        except OSError as e:
            custom_log(f"❌ Cannot stat YAML file {file_path}: {e}")
            return None

        hit = self._yaml_cache.get(file_path)
        if hit is not None and hit[0] == mtime:
            return hit[1]

        try:
            with open(file_path, "r", encoding="utf-8") as file:
                data = yaml.safe_load(file)
            self._yaml_cache[file_path] = (mtime, data)
            return data
        except Exception as e:
            custom_log(f"❌ Error loading YAML from {file_path}: {e}")
            return None

    def normalize_name(self, name):
        """Normalize a celebrity name for consistent searching."""
        name = name.lower().strip()
        name = name.replace(" ", "_")
        return name

    def get_question(self):
        """Fetch a question using the new `celeb_names.yml` structure and look up facts in `celeb_data.yml`."""
        try:
            started_at = time.perf_counter()
            trace_id = int(time.time() * 1000)
            custom_log("🔄 Starting get_question request...")
            custom_log(f"🚦 [srv:{trace_id}] get_question request metadata | method={request.method} | origin={request.headers.get('Origin')} | content_type={request.headers.get('Content-Type')}")

            # ✅ Extract request data
            data = request.get_json()
            custom_log(f"📦 [srv:{trace_id}] raw request json: {data}")
            level = str(data.get("level", 1))  # Convert level to string (since YAML keys are strings)
            category = data.get("category", "mixed").lower()
            guessed_list = [name.lower() for name in data.get("guessed_names", [])]

            custom_log(f"📥 Received request for category '{category}' at level {level}. Guessed list: {guessed_list}")

            # ✅ Load names YAML
            names_started_at = time.perf_counter()
            names_data = self.load_yaml(self.NAMES_YAML_PATH)
            custom_log(f"⏱️ [srv:{trace_id}] Loaded names YAML in {int((time.perf_counter() - names_started_at) * 1000)}ms")
            if not names_data or level not in names_data:
                custom_log(f"❌ No data found for level {level}.")
                return jsonify({"error": f"No data available for level {level}"}), 404

            # ✅ Filter available names for the requested category
            level_data = names_data[level]
            if category != "mixed":
                available_names = level_data.get(category, [])
                custom_log(f"✅ Available names for category '{category}' at level {level}: {available_names}")
            else:
                available_names = [name for cat_list in level_data.values() for name in cat_list]  # Flatten all categories
                custom_log(f"✅ Available names for 'mixed' category at level {level}: {available_names}")

            # ✅ Remove already guessed names first
            available_names = [name for name in available_names if name not in guessed_list]

            # ✅ Shuffle AFTER filtering guessed names
            random.shuffle(available_names)  

            if not available_names:
                custom_log(f"⚠️ No more names left to guess in category '{category}' at level {level}.")
                return jsonify({"error": f"No more names left to guess in category '{category}' at level {level}"}), 200

            # ✅ Randomly select a main celebrity
            selected_name = available_names[0]
            custom_log(f"🎭 Selected name: {selected_name}")


            # ✅ Load full celeb data YAML to get the selected name's facts
            celeb_started_at = time.perf_counter()
            celeb_data = self.load_yaml(self.DATA_YAML_PATH)
            custom_log(f"⏱️ [srv:{trace_id}] Loaded celeb_data YAML in {int((time.perf_counter() - celeb_started_at) * 1000)}ms")
            if not celeb_data or level not in celeb_data or selected_name not in celeb_data[level]:
                custom_log(f"❌ Could not find details for {selected_name} in `celeb_data.yml`.")
                return jsonify({"error": f"Data for {selected_name} not found"}), 500

            # ✅ Retrieve details for selected celebrity
            selected_data = celeb_data[level][selected_name]
            selected_facts = selected_data.get("facts", [])

            # ✅ Select 3 random facts (if available)
            if len(selected_facts) > 3:
                selected_facts = random.sample(selected_facts, 3)

            custom_log(f"📜 Selected 3 Random Facts: {selected_facts}")

            selected_categories = selected_data.get("categories", [])

            if not selected_categories:
                custom_log(f"❌ No category found for {selected_name} in `celeb_data.yml`.")
                return jsonify({"error": f"No category found for {selected_name}"}), 500

            selected_category = selected_categories[0].lower()  # ✅ Use the first category

            # ✅ Select distractor names from the same category
            all_category_names = level_data.get(selected_category, [])
            distractor_names = [name for name in all_category_names if name != selected_name]

            # ✅ Shuffle distractors properly
            random.shuffle(distractor_names)
            distractor_names = distractor_names[:3]  # Pick up to 3 distractors

            # ✅ If not enough distractors, fill from other categories
            if len(distractor_names) < 3:
                additional_names = [name for name in available_names if name not in distractor_names and name != selected_name]
                random.shuffle(additional_names)
                distractor_names.extend(additional_names[:3 - len(distractor_names)])

            custom_log(f"🎭 Final Distractor Names: {distractor_names}")


            # ✅ Get images for selected celebrity and distractors
            image_started_at = time.perf_counter()
            image_url = self.get_image_url(selected_name)
            distractor_images = [self.get_image_url(name) for name in distractor_names]
            custom_log(f"⏱️ [srv:{trace_id}] Resolved image URLs in {int((time.perf_counter() - image_started_at) * 1000)}ms")

            # ✅ Construct response
            response = {
                "actor": selected_name,
                "category": selected_category,
                "facts": selected_facts,
                "level": level,
                "image_url": image_url,
                "distractor_images": distractor_images,
                "distractor_names": distractor_names
            }

            custom_log(f"✅ Sending response: {response}")
            custom_log(f"✅ [srv:{trace_id}] get_question completed in {int((time.perf_counter() - started_at) * 1000)}ms")
            return jsonify(response), 200

        except Exception as e:
            custom_log(f"❌ Unexpected error in get_question: {e}")
            return jsonify({"error": f"Server error: {str(e)}"}), 500

    def _list_image_files(self):
        """List image filenames; cache until the image directory mtime changes."""
        try:
            mtime = os.path.getmtime(self.IMAGE_DIR)
        except OSError:
            return []

        if self._image_files_cache is not None and self._image_dir_mtime == mtime:
            return self._image_files_cache

        self._image_files_cache = os.listdir(self.IMAGE_DIR)
        self._image_dir_mtime = mtime
        return self._image_files_cache

    def _public_base_url(self):
        """
        Base URL for absolute image links returned to clients.

        Behind nginx, ``request.host_url`` is often ``http://`` even for HTTPS clients,
        which breaks Flutter web (mixed content). Prefer ``PUBLIC_BASE_URL``, then
        ``X-Forwarded-Proto`` / ``X-Forwarded-Host``, then ``request.host_url``.
        """
        explicit = (os.environ.get("PUBLIC_BASE_URL") or "").strip().rstrip("/")
        if explicit:
            return explicit
        proto = (request.headers.get("X-Forwarded-Proto") or request.scheme or "http").strip()
        if "," in proto:
            proto = proto.split(",")[0].strip()
        host = (request.headers.get("X-Forwarded-Host") or request.host or "").strip()
        if not host:
            return request.host_url.rstrip("/")
        return f"{proto}://{host}".rstrip("/")

    def get_image_url(self, name):
        """Retrieve the image URL for a given name from the images directory."""
        formatted_name = self.normalize_name(name)
        image_files = self._list_image_files()
        base = self._public_base_url()
        custom_log(f"🖼️ Resolving image for '{formatted_name}' against {len(image_files)} files")
        for filename in image_files:
            if filename.lower().startswith(formatted_name.lower()):  # ✅ Case-insensitive file matching
                return f"{base}/images/{filename}"

        return f"{base}/images/default.jpg"