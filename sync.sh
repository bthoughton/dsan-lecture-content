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
DL_QUIZ_SOURCE="/home/ben/dsan-6600-2026/quizzes"

# Recordings are staged here rather than pulled from a course repo, and are
# gitignored: they go to the server but never to GitHub. Drop each class into a
# week-N subdirectory; the Zoom filenames only encode a date, not a week.
DL_RECORDING_DIR="$SCRIPT_DIR/lecture-recordings/6600-fall-2026"

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

# The quiz directories hold answer keys and the unsat quizzes next to the
# student handouts, so copy by allowlist only. Never mirror these wholesale.
pull_study_guides() {
  local source_dir="$1" dest_dir="$2"
  rsync -avz --checksum --delete \
    --include='*/' \
    --include='study-guide.html' \
    --include='study-guide.pdf' \
    --include='formula-sheet.html' \
    --include='formula-sheet.pdf' \
    --exclude='*' \
    "$source_dir/" "$dest_dir/"
}

# Reuse the YAML header of a course landing page, swapping in a new title so
# every page in a course shares the same theme and author.
header_with_title() {
  local header_src="$1" new_title="$2" subtitle="${3:-}"
  sed '/^---$/,/^---$/!d' "$header_src" \
    | awk -v t="$new_title" -v s="$subtitle" '
        /^title:/ {
          print "title: \"" t "\""
          if (s != "") print "subtitle: \"" s "\""
          next
        }
        { print }'
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

lecture_topic() {
  local html="$1" fallback="$2" topic=""
  if [ -f "$html" ]; then
    topic=$( { grep -oP '(?<=<title>).*?(?=</title>)' "$html" | head -1 | strip_prefix; } || true)
  fi
  echo "${topic:-$fallback}"
}

lab_topic() {
  local nb="$1" fallback="$2" topic=""
  if [ -f "$nb" ]; then
    # First markdown heading of the notebook, e.g. "# Lab 1: ...".
    topic=$( { grep -oP '(?<=")# [^"]*(?=\\n")' "$nb" | head -1 | sed -E 's/^# //' | strip_prefix; } || true)
  fi
  echo "${topic:-$fallback}"
}

# Local path of a week's recording, or empty. Takes the first mp4 in the week
# directory so Zoom's own filenames can be left alone.
week_recording() {
  local num="$1" mp4
  for mp4 in "$DL_RECORDING_DIR/week-$num"/*.mp4; do
    [ -f "$mp4" ] || continue
    echo "$mp4"
    return 0
  done
}

week_numbers() {
  local lectures_dir="$1" week_dir
  for week_dir in "$lectures_dir"/week-*/; do
    [ -d "$week_dir" ] || continue
    basename "$week_dir" | grep -oP '\d+'
  done | sort -n
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

  local num week_name topic
  while read -r num; do
    week_name="week-$num"
    topic=$(lecture_topic "$content_dir/$week_name/$week_name.html" "$week_name")
    printf '| %02d | %s | [Lecture](%s/%s.html) |\n' \
      "$num" "$topic" "$week_name" "$week_name" >> "$out_qmd"
  done < <(week_numbers "$content_dir")

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

  local lab_dirs lab_dir lab_name lab_num nb topic
  mapfile -t lab_dirs < <(printf '%s\n' "$content_dir"/lab-*/ | sort -V)
  for lab_dir in "${lab_dirs[@]}"; do
    [ -d "$lab_dir" ] || continue
    lab_name=$(basename "$lab_dir")
    lab_num=$(echo "$lab_name" | grep -oP '\d+')

    nb="$lab_dir/${lab_name}.ipynb"
    [ -f "$nb" ] || continue
    topic=$(lab_topic "$nb" "$lab_name")

    printf '| %02d | %s | [Colab](%s/%s/%s/%s.ipynb) | [Notebook](%s/%s.ipynb){download="%s.ipynb"} |\n' \
      "$lab_num" "$topic" \
      "$COLAB_BASE" "$repo_path" "$lab_name" "$lab_name" \
      "$lab_name" "$lab_name" "$lab_name" >> "$out_qmd"
  done

  echo "" >> "$out_qmd"
  echo ": {.table .table-striped .table-hover}" >> "$out_qmd"
}

# The 6600 landing page: one row per week, described by the lecture's own title.
build_course_index() {
  local out_qmd="$1" header_src="$2" title="$3" lectures_dir="$4"

  mkdir -p "$(dirname "$out_qmd")"
  header_with_title "$header_src" "$title" > "$out_qmd"
  {
    echo ""
    echo "## Weekly Materials"
    echo ""
    echo "Each week has one page holding that week's lecture, lab, and quiz study"
    echo "guide."
    echo ""
    echo "| Week | Topic |"
    echo "|:-----|-------|"
  } >> "$out_qmd"

  local num topic
  while read -r num; do
    topic=$(lecture_topic "$lectures_dir/week-$num/week-$num.html" "week-$num")
    printf '| [Week %02d](week-%d/) | %s |\n' "$num" "$num" "$topic" >> "$out_qmd"
  done < <(week_numbers "$lectures_dir")

  {
    echo ""
    echo ": {.table .table-striped .table-hover}"
    echo ""
    echo "## Browse by Type"
    echo ""
    echo "- [All lectures](lectures/)"
    echo "- [All labs](labs/)"
  } >> "$out_qmd"
}

# One page per week, pulling together material that lives in the per-type
# directories. Quiz N covers week N but is taken at the start of week N+1.
build_week_pages() {
  local header_src="$1" course_title="$2" repo_root="$3"
  local lectures_dir="$SCRIPT_DIR/deep-learning/lectures"
  local labs_dir="$SCRIPT_DIR/deep-learning/labs"
  local guides_dir="$SCRIPT_DIR/deep-learning/study-guides"

  local num week_name out_qmd topic links lab_name nb quiz_name guide guide_pdf formula formula_pdf guide_note
  while read -r num; do
    week_name="week-$num"
    topic=$(lecture_topic "$lectures_dir/$week_name/$week_name.html" "$week_name")

    out_qmd="$BUILD_DIR/deep-learning/$week_name/index.qmd"
    mkdir -p "$(dirname "$out_qmd")"
    header_with_title "$header_src" "Week $num: $topic" "$course_title" > "$out_qmd"
    {
      echo ""
      echo "| Material | Links |"
      echo "|----------|-------|"
    } >> "$out_qmd"

    links="[Notes](../lectures/$week_name/$week_name.html)"
    if [ -f "$lectures_dir/$week_name/presentation.html" ]; then
      links="$links · [Slides](../lectures/$week_name/presentation.html)"
    fi
    if [ -n "$(week_recording "$num")" ]; then
      links="$links · [Lecture Recording](../recordings/$week_name/)"
    fi
    echo "| Lecture | $links |" >> "$out_qmd"

    lab_name="lab-$num"
    nb="$labs_dir/$lab_name/$lab_name.ipynb"
    if [ -f "$nb" ]; then
      links="[Open in Colab]($COLAB_BASE/$repo_root/labs/$lab_name/$lab_name.ipynb)"
      links="$links · [Download](../labs/$lab_name/$lab_name.ipynb){download=\"$lab_name.ipynb\"}"
      echo "| Lab $num: $(lab_topic "$nb" "$lab_name") | $links |" >> "$out_qmd"
    fi

    quiz_name=$(printf 'quiz-%02d' "$num")
    guide="$guides_dir/$quiz_name/study-guide.html"
    guide_pdf="$guides_dir/$quiz_name/study-guide.pdf"
    formula="$guides_dir/$quiz_name/formula-sheet.html"
    formula_pdf="$guides_dir/$quiz_name/formula-sheet.pdf"
    guide_note=""
    if [ -f "$guide" ] || [ -f "$guide_pdf" ]; then
      links=""
      [ -f "$guide" ] && links="[Study guide](../study-guides/$quiz_name/study-guide.html)"
      [ -f "$guide_pdf" ] && links="${links:+$links · }[PDF](../study-guides/$quiz_name/study-guide.pdf)"
      echo "| Quiz $num study guide | $links |" >> "$out_qmd"
      guide_note="Quiz $num covers this week's lecture and lab, and is taken at the end of the next class."
    fi
    if [ -f "$formula" ] || [ -f "$formula_pdf" ]; then
      links=""
      [ -f "$formula" ] && links="[Formula sheet](../study-guides/$quiz_name/formula-sheet.html)"
      [ -f "$formula_pdf" ] && links="${links:+$links · }[PDF](../study-guides/$quiz_name/formula-sheet.pdf)"
      echo "| Quiz $num formula sheet | $links |" >> "$out_qmd"
      guide_note="Quiz $num covers this week's lecture and lab, and is taken at the end of the next class."
    fi

    {
      echo ""
      echo ": {.table .table-striped .table-hover}"
      echo ""
      [ -n "$guide_note" ] && echo "$guide_note" && echo ""
      echo "[All weeks](../)"
    } >> "$out_qmd"

    render_page "$out_qmd"

    if [ -n "$(week_recording "$num")" ]; then
      build_recording_player "$num" "$topic"
    fi
  done < <(week_numbers "$lectures_dir")
}

# Browsers ignore playback-rate hints on a raw MP4, so each recording gets a
# small player page that sets video.playbackRate to 1.25 on load.
build_recording_player() {
  local num="$1" topic="$2"
  local week_name="week-$num"
  local out_dir="$BUILD_DIR/deep-learning/recordings/$week_name"
  local out_html="$out_dir/index.html"
  local src="$week_name-recording.mp4"
  local page_title week_href
  page_title=$(printf 'Week %s Lecture Recording' "$num")
  topic=$(printf '%s' "$topic" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g')
  week_href="../../$week_name/"

  mkdir -p "$out_dir"
  cat > "$out_html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>$page_title</title>
    <link rel="icon" type="image/png" href="/icon.png" />
    <style>
      *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
      body {
        font-family: system-ui, -apple-system, sans-serif;
        background: #111318;
        color: #e8e8ee;
        min-height: 100vh;
        display: flex;
        flex-direction: column;
        align-items: center;
        padding: 1.5rem 1.25rem 2rem;
      }
      header { max-width: 1100px; width: 100%; margin-bottom: 1rem; }
      h1 { font-size: 1.25rem; font-weight: 600; margin-bottom: 0.25rem; }
      .subtitle { color: #9aa0ae; font-size: 0.95rem; }
      .player-wrap { max-width: 1100px; width: 100%; }
      video { width: 100%; height: auto; background: #000; border-radius: 8px; }
      .meta { max-width: 1100px; width: 100%; margin-top: 0.85rem; color: #9aa0ae; font-size: 0.9rem; display: flex; gap: 1rem; flex-wrap: wrap; }
      a { color: #8ab4ff; }
    </style>
  </head>
  <body>
    <header>
      <h1>$page_title</h1>
      <p class="subtitle">$topic</p>
    </header>
    <div class="player-wrap">
      <video id="player" controls playsinline preload="metadata">
        <source src="$src" type="video/mp4" />
        Your browser does not support HTML video.
      </video>
    </div>
    <p class="meta">
      <span>Starts at 1.25×. Use the player controls to change speed.</span>
      <a href="$week_href">Back to week $num</a>
    </p>
    <script>
      (function () {
        const DEFAULT_RATE = 1.25;
        const video = document.getElementById("player");
        let userChanged = false;

        function applyDefault() {
          if (!userChanged) {
            video.defaultPlaybackRate = DEFAULT_RATE;
            video.playbackRate = DEFAULT_RATE;
          }
        }

        video.addEventListener("ratechange", function () {
          if (Math.abs(video.playbackRate - DEFAULT_RATE) > 0.01) {
            userChanged = true;
          }
        });
        video.addEventListener("loadedmetadata", applyDefault);
        video.addEventListener("play", applyDefault);
        applyDefault();
      })();
    </script>
  </body>
</html>
EOF
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

# Video is already compressed, so skip -z, and keep partial transfers so a
# dropped connection does not mean re-uploading hundreds of megabytes.
push_video() {
  local local_file="$1" remote_path="$2"
  ensure_remote_dir "$(dirname "$remote_path")"
  rsync -av --partial -e "$SSH_CMD" "$local_file" "$REMOTE:$REMOTE_ROOT/$remote_path"
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

echo "==> Pulling DSAN 6600 study guides from source repo..."
pull_study_guides "$DL_QUIZ_SOURCE" "$SCRIPT_DIR/deep-learning/study-guides"

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
build_course_index \
  "$BUILD_DIR/deep-learning/index.qmd" \
  "$SCRIPT_DIR/deep-learning/index.qmd" \
  "DSAN 6600: Deep Learning" \
  "$SCRIPT_DIR/deep-learning/lectures"
render_page "$BUILD_DIR/deep-learning/index.qmd"

echo "==> Building DSAN 6600 week pages..."
build_week_pages \
  "$SCRIPT_DIR/deep-learning/index.qmd" \
  "DSAN 6600: Deep Learning" \
  "deep-learning"

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
push_content "$SCRIPT_DIR/deep-learning/study-guides" "deep-learning/study-guides"
push_file "$SCRIPT_DIR/deep-learning/.htaccess" "deep-learning/.htaccess"
push_file "$BUILD_DIR/deep-learning/index.html" "deep-learning/index.html"
push_file "$BUILD_DIR/deep-learning/lectures/index.html" "deep-learning/lectures/index.html"
push_file "$BUILD_DIR/deep-learning/labs/index.html" "deep-learning/labs/index.html"

echo "==> Syncing DSAN 6600 lecture recordings..."
while read -r recording_week; do
  recording_file="$(week_recording "$recording_week")"
  [ -n "$recording_file" ] || continue
  push_video "$recording_file" \
    "deep-learning/recordings/week-$recording_week/week-$recording_week-recording.mp4"
  player_html="$BUILD_DIR/deep-learning/recordings/week-$recording_week/index.html"
  if [ -f "$player_html" ]; then
    push_file "$player_html" "deep-learning/recordings/week-$recording_week/index.html"
  fi
done < <(week_numbers "$SCRIPT_DIR/deep-learning/lectures")

echo "==> Syncing DSAN 6600 week pages..."
for week_index in "$BUILD_DIR"/deep-learning/week-*/index.html; do
  [ -f "$week_index" ] || continue
  week_dir_name="$(basename "$(dirname "$week_index")")"
  push_file "$week_index" "deep-learning/$week_dir_name/index.html"
done

echo "==> Cleaning up..."
rm -rf "$BUILD_DIR"

if labs_need_push; then
  echo
  echo "!!! Lab notebooks differ from what is pushed to GitHub."
  echo "    Colab serves labs from GitHub, not from this site, so commit and push"
  echo "    deep-learning/labs or students will open the old notebook."
fi

echo "==> Done! Site is live at https://benjaminhoughton.georgetown.domains/"
