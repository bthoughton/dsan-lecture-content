#!/usr/bin/env bash
set -euo pipefail

REMOTE="benjamin@benjaminhoughton.georgetown.domains"
KEY="$HOME/.ssh/id_rsa_desktop"
REMOTE_ROOT="~/public_html"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.landing-build"

SSH_CMD="ssh -i $KEY"

# --build-only renders the landing pages locally and skips the upload.
DEPLOY=true
if [ "${1:-}" = "--build-only" ]; then
  DEPLOY=false
fi

CV_LECTURE_SOURCE="/home/ben/dsan-6500-2026/lectures"
DL_LECTURE_SOURCE="/home/ben/dsan-6600-2026/lectures"
DL_LAB_SOURCE="/home/ben/dsan-6600-2026/labs"

# Colab can only open notebooks from GitHub, so lab notebooks must be pushed to
# this (public) repo for the "Open in Colab" links to resolve.
COLAB_BASE="https://colab.research.google.com/github/bthoughton/dsan-lecture-content/blob/main"

# Solution notebooks must never reach this repo or the public site.
PRIVATE=(--exclude='*-complete.ipynb' --exclude='*-solution.ipynb' --exclude='*-solutions.ipynb')

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

pull_source() {
  local source_dir="$1" dest_dir="$2"
  rsync -avz --checksum --delete \
    --exclude='index.qmd' \
    "${PRIVATE[@]}" \
    "$source_dir/" "$dest_dir/"
}

# Reuse the YAML header of a course landing page, swapping in a new title so
# every page in a course shares the same theme and author.
header_with_title() {
  local header_src="$1" new_title="$2"
  sed '/^---$/,/^---$/!d' "$header_src" \
    | awk -v t="$new_title" '/^title:/ { print "title: \"" t "\""; next } { print }'
}

render_page() {
  local qmd="$1"
  local dir base
  dir="$(dirname "$qmd")"
  base="$(basename "$qmd")"

  (cd "$dir" && quarto render "$base" --output index.html)

  if [ -f "$SCRIPT_DIR/icon.png" ]; then
    sed -i 's#</head>#  <link rel="icon" type="image/png" href="/icon.png" />\
</head>#' "$dir/index.html"
  fi
}

# Strip the "DSAN 6600 Week 01:" style prefix off a page title to leave the topic.
strip_prefix() {
  sed -E 's/^.*(Week|Lab) [0-9]+ ?[-—:] ?//'
}

build_lectures_index() {
  local content_dir="$1" out_qmd="$2" header_src="$3" title="$4"

  mkdir -p "$(dirname "$out_qmd")"
  header_with_title "$header_src" "$title" > "$out_qmd"
  {
    echo ""
    echo "## Lecture Schedule"
    echo ""
    echo "| Week | Topic | Link |"
    echo "|:----:|-------|:----:|"
  } >> "$out_qmd"

  local week_dirs week_dir week_name week_num html_file page_title topic
  mapfile -t week_dirs < <(printf '%s\n' "$content_dir"/week-*/ | sort -V)
  for week_dir in "${week_dirs[@]}"; do
    [ -d "$week_dir" ] || continue
    week_name=$(basename "$week_dir")
    week_num=$(echo "$week_name" | grep -oP '\d+')

    html_file="$week_dir/${week_name}.html"
    if [ -f "$html_file" ]; then
      page_title=$(grep -oP '(?<=<title>).*?(?=</title>)' "$html_file" | head -1)
      topic=$(echo "$page_title" | strip_prefix)
    else
      topic="$week_name"
    fi

    printf '| %02d | %s | [Lecture](%s/%s.html) |\n' \
      "$week_num" "$topic" "$week_name" "$week_name" >> "$out_qmd"
  done

  echo "" >> "$out_qmd"
  echo ": {.table .table-striped .table-hover}" >> "$out_qmd"
}

build_labs_index() {
  local content_dir="$1" out_qmd="$2" header_src="$3" title="$4" repo_path="$5"

  mkdir -p "$(dirname "$out_qmd")"
  header_with_title "$header_src" "$title" > "$out_qmd"
  {
    echo ""
    echo "## Labs"
    echo ""
    echo "Open a lab in Colab to work in the browser, or download the notebook to"
    echo "run it locally."
    echo ""
    echo "| Lab | Topic | Open in Colab | Download |"
    echo "|:---:|-------|:-------------:|:--------:|"
  } >> "$out_qmd"

  local lab_dirs lab_dir lab_name lab_num nb page_title topic
  mapfile -t lab_dirs < <(printf '%s\n' "$content_dir"/lab-*/ | sort -V)
  for lab_dir in "${lab_dirs[@]}"; do
    [ -d "$lab_dir" ] || continue
    lab_name=$(basename "$lab_dir")
    lab_num=$(echo "$lab_name" | grep -oP '\d+')

    nb="$lab_dir/${lab_name}.ipynb"
    [ -f "$nb" ] || continue

    # First markdown heading of the notebook, e.g. "# Lab 1: ...".
    page_title=$(grep -oP '(?<=")# [^"]*(?=\\n")' "$nb" | head -1 | sed -E 's/^# //')
    topic="$lab_name"
    [ -n "$page_title" ] && topic=$(echo "$page_title" | strip_prefix)

    printf '| %02d | %s | [Colab](%s/%s/%s/%s.ipynb) | [Notebook](%s/%s.ipynb){download="%s.ipynb"} |\n' \
      "$lab_num" "$topic" \
      "$COLAB_BASE" "$repo_path" "$lab_name" "$lab_name" \
      "$lab_name" "$lab_name" "$lab_name" >> "$out_qmd"
  done

  echo "" >> "$out_qmd"
  echo ": {.table .table-striped .table-hover}" >> "$out_qmd"
}

# rsync on the host is too old for --mkpath, so nested targets need creating first.
ensure_remote_dir() {
  local remote_path="$1"
  [ -n "$remote_path" ] && [ "$remote_path" != "." ] || return 0
  ssh -i "$KEY" "$REMOTE" "mkdir -p $REMOTE_ROOT/$remote_path"
}

# Push a content directory, keeping the generated landing page in place.
push_content() {
  local local_dir="$1" remote_path="$2"
  ensure_remote_dir "$remote_path"
  rsync -avz --delete -e "$SSH_CMD" \
    --exclude='/index.html' \
    --exclude='index.qmd' \
    "${PRIVATE[@]}" \
    "$local_dir/" "$REMOTE:$REMOTE_ROOT/$remote_path/"
}

# Colab reads labs from GitHub, so an unpushed lab edit is invisible to students
# even after a successful deploy.
labs_need_push() {
  local labs="deep-learning/labs"
  git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1

  if ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- "$labs"; then
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" ls-files --others --exclude-standard -- "$labs")" ]; then
    return 0
  fi
  if [ -n "$(git -C "$SCRIPT_DIR" log --oneline '@{u}..HEAD' -- "$labs" 2>/dev/null)" ]; then
    return 0
  fi
  return 1
}

push_file() {
  local local_file="$1" remote_path="$2"
  ensure_remote_dir "$(dirname "$remote_path")"
  rsync -avz -e "$SSH_CMD" "$local_file" "$REMOTE:$REMOTE_ROOT/$remote_path"
}

# ---------------------------------------------------------------------------
# Pull content from the course repos
# ---------------------------------------------------------------------------

echo "==> Pulling DSAN 6500 lectures from source repo..."
pull_source "$CV_LECTURE_SOURCE" "$SCRIPT_DIR/computer-vision"

echo "==> Pulling DSAN 6600 lectures from source repo..."
pull_source "$DL_LECTURE_SOURCE" "$SCRIPT_DIR/deep-learning/lectures"

echo "==> Pulling DSAN 6600 labs from source repo..."
pull_source "$DL_LAB_SOURCE" "$SCRIPT_DIR/deep-learning/labs"

# ---------------------------------------------------------------------------
# Build landing pages
# ---------------------------------------------------------------------------

rm -rf "$BUILD_DIR"

echo "==> Building DSAN 6500 lectures landing page..."
build_lectures_index \
  "$SCRIPT_DIR/computer-vision" \
  "$BUILD_DIR/computer-vision/index.qmd" \
  "$SCRIPT_DIR/computer-vision/index.qmd" \
  "DSAN 6500: Computer Vision Analytics & Generative Image Modeling"
render_page "$BUILD_DIR/computer-vision/index.qmd"

echo "==> Building DSAN 6600 course landing page..."
mkdir -p "$BUILD_DIR/deep-learning"
cp "$SCRIPT_DIR/deep-learning/index.qmd" "$BUILD_DIR/deep-learning/index.qmd"
render_page "$BUILD_DIR/deep-learning/index.qmd"

echo "==> Building DSAN 6600 lectures landing page..."
build_lectures_index \
  "$SCRIPT_DIR/deep-learning/lectures" \
  "$BUILD_DIR/deep-learning/lectures/index.qmd" \
  "$SCRIPT_DIR/deep-learning/index.qmd" \
  "DSAN 6600: Deep Learning — Lectures"
render_page "$BUILD_DIR/deep-learning/lectures/index.qmd"

echo "==> Building DSAN 6600 labs landing page..."
build_labs_index \
  "$SCRIPT_DIR/deep-learning/labs" \
  "$BUILD_DIR/deep-learning/labs/index.qmd" \
  "$SCRIPT_DIR/deep-learning/index.qmd" \
  "DSAN 6600: Deep Learning — Labs" \
  "deep-learning/labs"
render_page "$BUILD_DIR/deep-learning/labs/index.qmd"

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------

if [ "$DEPLOY" = false ]; then
  echo "==> Build only; landing pages left in $BUILD_DIR"
  exit 0
fi

echo "==> Syncing site root index..."
push_file "$SCRIPT_DIR/index.html" "index.html"

if [ -f "$SCRIPT_DIR/icon.png" ]; then
  echo "==> Syncing favicon..."
  push_file "$SCRIPT_DIR/icon.png" "icon.png"
fi

echo "==> Syncing DSAN 6500 content..."
push_content "$SCRIPT_DIR/computer-vision" "computer-vision"
push_file "$BUILD_DIR/computer-vision/index.html" "computer-vision/index.html"

echo "==> Syncing DSAN 6600 content..."
push_content "$SCRIPT_DIR/deep-learning/lectures" "deep-learning/lectures"
push_content "$SCRIPT_DIR/deep-learning/labs" "deep-learning/labs"
push_file "$SCRIPT_DIR/deep-learning/.htaccess" "deep-learning/.htaccess"
push_file "$BUILD_DIR/deep-learning/index.html" "deep-learning/index.html"
push_file "$BUILD_DIR/deep-learning/lectures/index.html" "deep-learning/lectures/index.html"
push_file "$BUILD_DIR/deep-learning/labs/index.html" "deep-learning/labs/index.html"

echo "==> Cleaning up..."
rm -rf "$BUILD_DIR"

if labs_need_push; then
  echo
  echo "!!! Lab notebooks differ from what is pushed to GitHub."
  echo "    Colab serves labs from GitHub, not from this site, so commit and push"
  echo "    deep-learning/labs or students will open the old notebook."
fi

echo "==> Done! Site is live at https://benjaminhoughton.georgetown.domains/"
