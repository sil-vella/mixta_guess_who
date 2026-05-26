import yaml
import os
import re
import random
import time
import base64
from flask import request, jsonify, send_from_directory, Response
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
        names_data = self.load_yaml(self.NAMES_YAML_PATH)
        celeb_data = self.load_yaml(self.DATA_YAML_PATH)
        self._list_image_files()
        if not names_data:
            custom_log(f"❌ QuestionModule: names YAML is empty — restore {self.NAMES_YAML_PATH}")
        if not celeb_data:
            custom_log(f"❌ QuestionModule: celeb_data YAML is empty — restore {self.DATA_YAML_PATH}")
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

        # Admin YAML editor (token-protected)
        self.connection_module.register_route(
            '/admin/celeb-editor',
            self.celeb_editor_page,
            methods=['GET'],
            endpoint='question_module_celeb_editor_page',
        )
        self.connection_module.register_route(
            '/admin/celeb-data',
            self.celeb_editor_data,
            methods=['GET', 'POST'],
            endpoint='question_module_celeb_editor_data',
        )
        self.connection_module.register_route(
            '/admin/celeb-images-upload',
            self.celeb_images_upload,
            methods=['POST'],
            endpoint='question_module_celeb_images_upload',
        )
        custom_log("🛠️ QuestionModule: `/admin/celeb-editor` and `/admin/celeb-data` routes registered.")

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
            if data is None:
                custom_log(f"⚠️ YAML file is empty or null: {file_path}")
                data = {}
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

    def _is_editor_authorized(self):
        def _clean_env_value(raw):
            value = (raw or "").strip()
            if len(value) >= 2 and (
                (value[0] == "'" and value[-1] == "'")
                or (value[0] == '"' and value[-1] == '"')
            ):
                value = value[1:-1].strip()
            return value

        def _read_key_from_env_file(file_path, key):
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    for line in f:
                        raw = line.strip()
                        if not raw or raw.startswith("#") or "=" not in raw:
                            continue
                        k, v = raw.split("=", 1)
                        if k.strip() == key:
                            return _clean_env_value(v)
            except Exception:
                return ""
            return ""

        expected_user = _clean_env_value(os.environ.get("CELEB_EDITOR_USER"))
        expected_password = _clean_env_value(os.environ.get("CELEB_EDITOR_PASSWORD"))

        if not expected_user or not expected_password:
            repo_root = os.path.abspath(os.path.join(self.BASE_DIR, "..", "..", "..", "..", ".."))
            local_env = os.path.join(repo_root, ".env.local")
            prod_env = os.path.join(repo_root, ".env.prod")
            expected_user = expected_user or _read_key_from_env_file(local_env, "CELEB_EDITOR_USER")
            expected_password = expected_password or _read_key_from_env_file(local_env, "CELEB_EDITOR_PASSWORD")
            expected_user = expected_user or _read_key_from_env_file(prod_env, "CELEB_EDITOR_USER")
            expected_password = expected_password or _read_key_from_env_file(prod_env, "CELEB_EDITOR_PASSWORD")

        if not expected_user or not expected_password:
            return False
        header = (request.headers.get("Authorization") or "").strip()
        if not header.lower().startswith("basic "):
            return False
        b64 = header[6:].strip()
        try:
            decoded = base64.b64decode(b64).decode("utf-8")
        except Exception:
            return False
        if ":" not in decoded:
            return False
        username, password = decoded.split(":", 1)
        return username == expected_user and password == expected_password

    def _ensure_level_data(self, data, level):
        key = str(level)
        if key not in data or not isinstance(data.get(key), dict):
            data[key] = {}
        return data[key]

    def _normalize_categories(self, categories):
        if categories is None:
            return []
        if not isinstance(categories, list):
            return []
        seen = set()
        out = []
        for item in categories:
            value = str(item).strip()
            if value and value not in seen:
                seen.add(value)
                out.append(value)
        return out

    def _normalize_facts(self, facts):
        if facts is None:
            return []
        if not isinstance(facts, list):
            return []
        out = []
        for item in facts:
            value = str(item).strip()
            if value:
                out.append(value)
        return out

    def _collect_categories_from_names_level(self, level_names):
        collected = {}
        if not isinstance(level_names, dict):
            return collected
        for category, celeb_list in level_names.items():
            if not isinstance(celeb_list, list):
                continue
            for celeb in celeb_list:
                celeb_name = str(celeb).strip()
                if not celeb_name:
                    continue
                if celeb_name not in collected:
                    collected[celeb_name] = []
                if category not in collected[celeb_name]:
                    collected[celeb_name].append(str(category))
        return collected

    def _build_merged_editor_data(self, celeb_data, names_data):
        merged = {}
        all_levels = set(str(k) for k in celeb_data.keys()) | set(str(k) for k in names_data.keys())
        for level in sorted(all_levels, key=lambda x: int(x) if str(x).isdigit() else str(x)):
            level_celeb = celeb_data.get(level, {})
            level_names = names_data.get(level, {})
            if not isinstance(level_celeb, dict):
                level_celeb = {}
            names_categories = self._collect_categories_from_names_level(level_names)
            celeb_names = set(level_celeb.keys()) | set(names_categories.keys())
            merged[level] = {}
            for celeb_name in sorted(celeb_names):
                celeb_row = level_celeb.get(celeb_name, {})
                categories = self._normalize_categories(
                    celeb_row.get("categories") if isinstance(celeb_row, dict) else []
                )
                facts = self._normalize_facts(celeb_row.get("facts") if isinstance(celeb_row, dict) else [])
                if not categories:
                    categories = names_categories.get(celeb_name, [])
                merged[level][celeb_name] = {
                    "categories": categories,
                    "facts": facts,
                }
        return merged

    def _rebuild_names_level(self, level_celeb):
        names_level = {}
        for celeb_name, celeb_row in level_celeb.items():
            if not isinstance(celeb_row, dict):
                continue
            categories = self._normalize_categories(celeb_row.get("categories"))
            for category in categories:
                if category not in names_level:
                    names_level[category] = []
                if celeb_name not in names_level[category]:
                    names_level[category].append(celeb_name)
        for category in names_level:
            names_level[category] = sorted(names_level[category])
        return dict(sorted(names_level.items(), key=lambda i: i[0]))

    def _write_yaml_with_backup(self, path, data):
        if os.path.exists(path):
            ts = time.strftime("%Y%m%d_%H%M%S")
            backup_path = f"{path}.bak_{ts}"
            try:
                with open(path, "r", encoding="utf-8") as old_file:
                    old_content = old_file.read()
                with open(backup_path, "w", encoding="utf-8") as backup_file:
                    backup_file.write(old_content)
            except Exception as e:
                custom_log(f"⚠️ Failed to create backup for {path}: {e}")
        with open(path, "w", encoding="utf-8") as file:
            yaml.safe_dump(
                data,
                file,
                sort_keys=True,
                allow_unicode=True,
                default_flow_style=False,
                width=120,
            )

    def celeb_editor_page(self):
        if not self._is_editor_authorized():
            return Response(
                "Unauthorized",
                401,
                {"WWW-Authenticate": 'Basic realm="Celeb Editor"'},
            )

        html = """<!doctype html>
<html>
  <head>
    <meta charset="utf-8"/>
    <meta name="viewport" content="width=device-width, initial-scale=1"/>
    <title>Celeb YAML Editor</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 16px; background: #111; color: #eee; }
      h1 { margin: 0 0 12px 0; }
      .row { display: flex; gap: 8px; margin: 8px 0; flex-wrap: wrap; }
      button { padding: 8px 12px; cursor: pointer; }
      select, input, textarea {
        background: #1e1e1e; color: #dcdcdc; border: 1px solid #444; padding: 8px;
      }
      select, input { min-width: 220px; }
      textarea { width: 100%; min-height: 220px; font-family: monospace; font-size: 13px; }
      .facts { min-height: 300px; }
      .hint { color: #a9a9a9; font-size: 13px; margin-top: 8px; }
      .status { margin-top: 8px; font-size: 13px; }
      .ok { color: #9fef9f; }
      .err { color: #ff9f9f; }
      .panel { border: 1px solid #333; padding: 10px; margin-top: 10px; border-radius: 6px; background: #171717; }
      .label { font-size: 12px; color: #9a9a9a; margin-top: 6px; margin-bottom: 4px; }
      .spinner {
        width: 14px;
        height: 14px;
        border: 2px solid #666;
        border-top-color: #fff;
        border-radius: 50%;
        display: inline-block;
        vertical-align: middle;
        animation: spin 0.8s linear infinite;
        margin-right: 6px;
      }
      .hidden { display: none !important; }
      @keyframes spin { to { transform: rotate(360deg); } }
    </style>
  </head>
  <body>
    <h1>Celeb YAML Editor</h1>
    <div class="row">
      <button id="reloadBtn">Reload</button>
      <button id="editBtn">Edit</button>
      <button id="cancelEditBtn">Cancel</button>
      <button id="saveBtn"><span id="saveSpinner" class="spinner hidden"></span><span id="saveLabel">Save</span></button>
      <button id="addLevelBtn">Add Level</button>
      <button id="removeLevelBtn">Remove Level</button>
      <button id="uploadImagesBtn">Upload Images</button>
      <input id="uploadImagesInput" type="file" multiple class="hidden" />
    </div>
    <div class="row">
      <select id="levelSelect"></select>
      <select id="celebSelect"></select>
      <button id="addCelebBtn">Add Celeb</button>
      <button id="removeCelebBtn">Remove Celeb</button>
    </div>
    <div class="panel">
      <div class="label">Level</div>
      <input id="levelField" type="text" />
      <div class="label">Celeb key (e.g. leonardo_dicaprio)</div>
      <input id="celebName" type="text" />
      <div class="label">Categories (comma separated)</div>
      <input id="categories" type="text" />
      <div class="label">Facts (one fact per line)</div>
      <textarea id="facts" class="facts" spellcheck="false"></textarea>
    </div>
    <div class="hint">
      Choose level and celeb to view. Click Edit to unlock fields, then Save.
      Saving updates both celeb_data.yml and categoriesed_celeb_names_for_db_populate.yml.
    </div>
    <div id="status" class="status"></div>
    <script>
      const statusEl = document.getElementById("status");
      const levelSelect = document.getElementById("levelSelect");
      const celebSelect = document.getElementById("celebSelect");
      const levelFieldEl = document.getElementById("levelField");
      const celebNameEl = document.getElementById("celebName");
      const categoriesEl = document.getElementById("categories");
      const factsEl = document.getElementById("facts");
      const editBtn = document.getElementById("editBtn");
      const cancelEditBtn = document.getElementById("cancelEditBtn");
      const saveBtn = document.getElementById("saveBtn");
      const addLevelBtn = document.getElementById("addLevelBtn");
      const removeLevelBtn = document.getElementById("removeLevelBtn");
      const addCelebBtn = document.getElementById("addCelebBtn");
      const removeCelebBtn = document.getElementById("removeCelebBtn");
      const uploadImagesBtn = document.getElementById("uploadImagesBtn");
      const uploadImagesInput = document.getElementById("uploadImagesInput");
      const saveSpinner = document.getElementById("saveSpinner");
      const saveLabel = document.getElementById("saveLabel");
      let data = {};
      let currentLevel = "";
      let currentCeleb = "";
      let isEditMode = false;
      let snapshotData = null;
      let isBusy = false;

      function setStatus(msg, isError) {
        statusEl.textContent = msg;
        statusEl.className = "status " + (isError ? "err" : "ok");
      }

      function sortedLevels() {
        return Object.keys(data).sort((a, b) => {
          const na = Number(a), nb = Number(b);
          if (!Number.isNaN(na) && !Number.isNaN(nb)) return na - nb;
          return a.localeCompare(b);
        });
      }

      function sortedCelebs(level) {
        if (!data[level]) return [];
        return Object.keys(data[level]).sort((a, b) => a.localeCompare(b));
      }

      function ensureLevel(level) {
        if (!data[level]) data[level] = {};
      }

      function setEditMode(enabled) {
        isEditMode = !!enabled;
        if (isBusy) return;
        levelFieldEl.disabled = !isEditMode;
        celebNameEl.disabled = !isEditMode;
        categoriesEl.disabled = !isEditMode;
        factsEl.disabled = !isEditMode;
        saveBtn.disabled = !isEditMode;
        cancelEditBtn.disabled = !isEditMode;
        addLevelBtn.disabled = !isEditMode;
        removeLevelBtn.disabled = !isEditMode;
        addCelebBtn.disabled = !isEditMode;
        removeCelebBtn.disabled = !isEditMode;
        editBtn.disabled = isEditMode;
      }

      function setBusy(enabled, labelText) {
        isBusy = !!enabled;
        const reloadBtn = document.getElementById("reloadBtn");
        if (reloadBtn) reloadBtn.disabled = isBusy;
        editBtn.disabled = isBusy || isEditMode;
        cancelEditBtn.disabled = isBusy || !isEditMode;
        saveBtn.disabled = isBusy || !isEditMode;
        addLevelBtn.disabled = isBusy || !isEditMode;
        removeLevelBtn.disabled = isBusy || !isEditMode;
        addCelebBtn.disabled = isBusy || !isEditMode;
        removeCelebBtn.disabled = isBusy || !isEditMode;
        uploadImagesBtn.disabled = isBusy;
        levelSelect.disabled = isBusy;
        celebSelect.disabled = isBusy;
        levelFieldEl.disabled = true;
        celebNameEl.disabled = true;
        categoriesEl.disabled = true;
        factsEl.disabled = true;
        saveSpinner.classList.toggle("hidden", !isBusy);
        saveLabel.textContent = isBusy ? (labelText || "Saving...") : "Save";
        if (!isBusy) setEditMode(isEditMode);
      }

      function renderLevels() {
        const levels = sortedLevels();
        levelSelect.innerHTML = "";
        for (const lv of levels) {
          const opt = document.createElement("option");
          opt.value = lv;
          opt.textContent = "Level " + lv;
          levelSelect.appendChild(opt);
        }
        if (!levels.length) {
          currentLevel = "";
          currentCeleb = "";
          renderCelebs();
          return;
        }
        if (!currentLevel || !data[currentLevel]) currentLevel = levels[0];
        levelSelect.value = currentLevel;
        renderCelebs();
      }

      function renderCelebs() {
        celebSelect.innerHTML = "";
        if (!currentLevel || !data[currentLevel]) {
          celebNameEl.value = "";
          categoriesEl.value = "";
          factsEl.value = "";
          return;
        }
        const celebs = sortedCelebs(currentLevel);
        for (const c of celebs) {
          const opt = document.createElement("option");
          opt.value = c;
          opt.textContent = c;
          celebSelect.appendChild(opt);
        }
        if (!celebs.length) {
          currentCeleb = "";
          celebNameEl.value = "";
          categoriesEl.value = "";
          factsEl.value = "";
          return;
        }
        if (!currentCeleb || !data[currentLevel][currentCeleb]) currentCeleb = celebs[0];
        celebSelect.value = currentCeleb;
        loadCelebToForm();
      }

      function loadCelebToForm() {
        if (!currentLevel || !currentCeleb || !data[currentLevel] || !data[currentLevel][currentCeleb]) return;
        const row = data[currentLevel][currentCeleb];
        levelFieldEl.value = currentLevel;
        celebNameEl.value = currentCeleb;
        categoriesEl.value = (row.categories || []).join(", ");
        factsEl.value = (row.facts || []).join("\\n");
      }

      function commitFormToData() {
        if (!isEditMode) return;
        if (!currentLevel || !currentCeleb || !data[currentLevel] || !data[currentLevel][currentCeleb]) return;
        const targetLevel = (levelFieldEl.value || "").trim();
        const newName = (celebNameEl.value || "").trim();
        if (!targetLevel) throw new Error("Level cannot be empty.");
        if (!newName) throw new Error("Celeb key cannot be empty.");
        const cats = (categoriesEl.value || "")
          .split(",")
          .map(x => x.trim())
          .filter(Boolean);
        const facts = (factsEl.value || "")
          .split("\\n")
          .map(x => x.trim())
          .filter(Boolean);
        const old = data[currentLevel][currentCeleb];
        old.categories = cats;
        old.facts = facts;
        const levelChanged = targetLevel !== currentLevel;
        const nameChanged = newName !== currentCeleb;
        if (levelChanged) ensureLevel(targetLevel);
        const targetBucket = data[targetLevel];
        if ((levelChanged || nameChanged) && targetBucket[newName]) {
          throw new Error("Celeb key already exists in target level.");
        }
        if (levelChanged || nameChanged) {
          targetBucket[newName] = old;
          delete data[currentLevel][currentCeleb];
          if (data[currentLevel] && Object.keys(data[currentLevel]).length === 0) {
            delete data[currentLevel];
          }
          currentLevel = targetLevel;
          currentCeleb = newName;
        }
      }

      async function loadData() {
        try {
          setBusy(true, "Loading...");
          setStatus("Loading...", false);
          const resp = await fetch("/admin/celeb-data");
          const body = await resp.json();
          if (!resp.ok) {
            throw new Error(body.error || ("HTTP " + resp.status));
          }
          data = body.data || {};
          currentLevel = sortedLevels()[0] || "";
          currentCeleb = currentLevel ? sortedCelebs(currentLevel)[0] || "" : "";
          snapshotData = JSON.parse(JSON.stringify(data));
          renderLevels();
          setEditMode(false);
          setStatus("Loaded.", false);
        } finally {
          setBusy(false);
        }
      }

      async function saveData() {
        try {
          setBusy(true, "Saving...");
          setStatus("Saving...", false);
          commitFormToData();
          const resp = await fetch("/admin/celeb-data", {
            method: "POST",
            headers: {
              "Content-Type": "application/json"
            },
            body: JSON.stringify({ data })
          });
          const body = await resp.json();
          if (!resp.ok) {
            throw new Error(body.error || ("HTTP " + resp.status));
          }
          snapshotData = JSON.parse(JSON.stringify(data));
          setEditMode(false);
          setStatus("Saved.", false);
        } finally {
          setBusy(false);
        }
      }

      async function uploadImages(files) {
        if (!files || !files.length) return;
        const form = new FormData();
        for (const f of files) form.append("images", f);
        try {
          setBusy(true, "Uploading...");
          setStatus("Uploading images...", false);
          const resp = await fetch("/admin/celeb-images-upload", {
            method: "POST",
            body: form
          });
          const body = await resp.json();
          if (!resp.ok) throw new Error(body.error || ("HTTP " + resp.status));
          const uploaded = Array.isArray(body.uploaded) ? body.uploaded : [];
          const failed = Array.isArray(body.failed) ? body.failed : [];
          if (failed.length) {
            setStatus("Upload completed with warnings.", true);
            alert(
              "Uploaded: " + uploaded.length + "\\n" +
              "Failed: " + failed.length + "\\n\\n" +
              failed.map(x => (x.filename || "unknown") + " - " + (x.reason || "failed")).join("\\n")
            );
          } else {
            setStatus("Uploaded " + uploaded.length + " image(s).", false);
          }
        } finally {
          setBusy(false);
          uploadImagesInput.value = "";
        }
      }

      levelSelect.addEventListener("change", () => {
        try { commitFormToData(); } catch (e) { setStatus(e.message, true); return; }
        currentLevel = levelSelect.value;
        currentCeleb = sortedCelebs(currentLevel)[0] || "";
        renderCelebs();
      });

      celebSelect.addEventListener("change", () => {
        try { commitFormToData(); } catch (e) { setStatus(e.message, true); return; }
        currentCeleb = celebSelect.value;
        loadCelebToForm();
      });

      document.getElementById("addLevelBtn").addEventListener("click", () => {
        if (!isEditMode) return;
        const value = prompt("New level key (e.g. 3):", "");
        if (!value) return;
        const lv = value.trim();
        ensureLevel(lv);
        currentLevel = lv;
        currentCeleb = "";
        renderLevels();
      });

      document.getElementById("removeLevelBtn").addEventListener("click", () => {
        if (!isEditMode) return;
        if (!currentLevel) return;
        if (!confirm("Remove level " + currentLevel + " and all celebs?")) return;
        delete data[currentLevel];
        currentLevel = sortedLevels()[0] || "";
        currentCeleb = currentLevel ? sortedCelebs(currentLevel)[0] || "" : "";
        renderLevels();
      });

      document.getElementById("addCelebBtn").addEventListener("click", () => {
        if (!isEditMode) return;
        if (!currentLevel) { setStatus("Select/add a level first.", true); return; }
        const name = prompt("New celeb key (e.g. tom_cruise):", "");
        if (!name) return;
        const celeb = name.trim();
        if (!celeb) return;
        ensureLevel(currentLevel);
        if (!data[currentLevel][celeb]) {
          data[currentLevel][celeb] = { categories: [], facts: [] };
        }
        currentCeleb = celeb;
        renderCelebs();
      });

      document.getElementById("removeCelebBtn").addEventListener("click", () => {
        if (!isEditMode) return;
        if (!currentLevel || !currentCeleb) return;
        if (!confirm("Remove celeb " + currentCeleb + " from level " + currentLevel + "?")) return;
        delete data[currentLevel][currentCeleb];
        currentCeleb = sortedCelebs(currentLevel)[0] || "";
        renderCelebs();
      });

      document.getElementById("reloadBtn").addEventListener("click", () => loadData().catch(e => setStatus(e.message, true)));
      editBtn.addEventListener("click", () => {
        snapshotData = JSON.parse(JSON.stringify(data));
        setEditMode(true);
        setStatus("Edit mode enabled.", false);
      });
      cancelEditBtn.addEventListener("click", () => {
        if (!snapshotData) return;
        data = JSON.parse(JSON.stringify(snapshotData));
        currentLevel = sortedLevels()[0] || "";
        currentCeleb = currentLevel ? sortedCelebs(currentLevel)[0] || "" : "";
        renderLevels();
        setEditMode(false);
        setStatus("Edit cancelled.", false);
      });
      saveBtn.addEventListener("click", () => saveData().catch(e => setStatus(e.message, true)));
      uploadImagesBtn.addEventListener("click", () => uploadImagesInput.click());
      uploadImagesInput.addEventListener("change", () => {
        uploadImages(uploadImagesInput.files).catch(e => setStatus(e.message, true));
      });

      loadData().catch(e => setStatus(e.message, true));
    </script>
  </body>
</html>
"""
        return Response(html, mimetype="text/html")

    def celeb_editor_data(self):
        if not self._is_editor_authorized():
            return Response(
                "Unauthorized",
                401,
                {"WWW-Authenticate": 'Basic realm="Celeb Editor"'},
            )

        try:
            celeb_data = self.load_yaml(self.DATA_YAML_PATH) or {}
            names_data = self.load_yaml(self.NAMES_YAML_PATH) or {}
            if not isinstance(celeb_data, dict):
                celeb_data = {}
            if not isinstance(names_data, dict):
                names_data = {}

            if request.method == "GET":
                merged = self._build_merged_editor_data(celeb_data, names_data)
                return jsonify({"data": merged})

            body = request.get_json(silent=True) or {}
            edited = body.get("data")
            if edited is None:
                raw_yaml = body.get("yaml")
                if not isinstance(raw_yaml, str):
                    return jsonify({"error": "Expected JSON body with `data` object (or legacy `yaml` string)"}), 400
                edited = yaml.safe_load(raw_yaml)
            if edited is None:
                edited = {}
            if not isinstance(edited, dict):
                return jsonify({"error": "Top-level payload must be a mapping of levels"}), 400

            next_celeb_data = {}
            next_names_data = {}
            for level, level_data in edited.items():
                level_key = str(level)
                if level_data is None:
                    level_data = {}
                if not isinstance(level_data, dict):
                    return jsonify({"error": f"Level '{level_key}' must map celeb -> data"}), 400

                self._ensure_level_data(next_celeb_data, level_key)

                for celeb_name, celeb_row in sorted(level_data.items(), key=lambda i: str(i[0])):
                    celeb_key = str(celeb_name).strip()
                    if not celeb_key:
                        continue
                    if celeb_row is None:
                        celeb_row = {}
                    if not isinstance(celeb_row, dict):
                        return jsonify({"error": f"Celeb '{celeb_key}' in level '{level_key}' must be a mapping"}), 400

                    next_celeb_data[level_key][celeb_key] = {
                        "categories": self._normalize_categories(celeb_row.get("categories")),
                        "facts": self._normalize_facts(celeb_row.get("facts")),
                    }

                next_names_data[level_key] = self._rebuild_names_level(next_celeb_data[level_key])

            self._write_yaml_with_backup(self.DATA_YAML_PATH, next_celeb_data)
            self._write_yaml_with_backup(self.NAMES_YAML_PATH, next_names_data)

            try:
                self._yaml_cache.pop(self.DATA_YAML_PATH, None)
                self._yaml_cache.pop(self.NAMES_YAML_PATH, None)
            except Exception:
                pass

            return jsonify({"success": True})
        except yaml.YAMLError as e:
            return jsonify({"error": f"Invalid YAML: {e}"}), 400
        except Exception as e:
            custom_log(f"❌ celeb_editor_data failed: {e}")
            return jsonify({"error": f"Server error: {e}"}), 500

    def celeb_images_upload(self):
        if not self._is_editor_authorized():
            return Response(
                "Unauthorized",
                401,
                {"WWW-Authenticate": 'Basic realm="Celeb Editor"'},
            )

        try:
            files = request.files.getlist("images")
            if not files:
                return jsonify({"error": "No files uploaded. Use form-data field `images`."}), 400

            os.makedirs(self.IMAGE_DIR, exist_ok=True)
            max_size = 300 * 1024 * 1024  # 300MB per file
            allowed_exts = {".jpg", ".jpeg", ".png"}
            uploaded = []
            failed = []

            for file_obj in files:
                try:
                    original_name = os.path.basename((file_obj.filename or "").strip())
                    if not original_name:
                        failed.append({"filename": "", "reason": "Missing filename"})
                        continue

                    safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", original_name)
                    if safe_name in {".", ".."}:
                        failed.append({"filename": original_name, "reason": "Invalid filename"})
                        continue
                    ext = os.path.splitext(safe_name)[1].lower()
                    if ext not in allowed_exts:
                        failed.append({
                            "filename": original_name,
                            "reason": "Unsupported file type. Allowed: .jpg, .jpeg, .png",
                        })
                        continue

                    try:
                        file_obj.stream.seek(0, os.SEEK_END)
                        size = file_obj.stream.tell()
                        file_obj.stream.seek(0)
                    except Exception:
                        size = 0
                    if size > max_size:
                        failed.append({
                            "filename": original_name,
                            "reason": "File exceeds 300MB limit",
                        })
                        continue

                    target_path = os.path.join(self.IMAGE_DIR, safe_name)
                    file_obj.save(target_path)
                    uploaded.append({"filename": safe_name, "size_bytes": size})
                except Exception as inner_error:
                    failed.append({
                        "filename": os.path.basename((file_obj.filename or "").strip()),
                        "reason": str(inner_error),
                    })

            try:
                self._image_files_cache = None
                self._image_dir_mtime = None
            except Exception:
                pass

            return jsonify({"uploaded": uploaded, "failed": failed}), 200
        except Exception as e:
            custom_log(f"❌ celeb_images_upload failed: {e}")
            return jsonify({"error": f"Server error: {e}"}), 500

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