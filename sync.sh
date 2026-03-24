#!/usr/bin/env bash
set -euo pipefail

REMOTE="benjamin@benjaminhoughton.georgetown.domains"
KEY="$HOME/.ssh/id_rsa_desktop"
REMOTE_ROOT="~/public_html"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LANDING_DIR="$SCRIPT_DIR/.landing-build"

SSH_CMD="ssh -i $KEY"
LECTURE_SOURCE="/home/ben/dsan-6500-2026/lectures"

echo "==> Pulling latest lecture files from source repo..."
rsync -avz --update "$LECTURE_SOURCE/" "$SCRIPT_DIR/computer-vision/"

generate_landing_page() {
  mkdir -p "$LANDING_DIR"

  local qmd_file="$LANDING_DIR/index.qmd"
  local header
  header=$(sed '/^---$/,/^---$/!d' "$SCRIPT_DIR/computer-vision/index.qmd")

  cat > "$qmd_file" <<HEADER
$header
HEADER

  echo "" >> "$qmd_file"
  echo "## Lecture Schedule" >> "$qmd_file"
  echo "" >> "$qmd_file"
  echo "| Week | Topic | Link |" >> "$qmd_file"
  echo "|:----:|-------|:----:|" >> "$qmd_file"

  for week_dir in "$SCRIPT_DIR"/computer-vision/week-*/; do
    [ -d "$week_dir" ] || continue
    week_name=$(basename "$week_dir")
    week_num=$(echo "$week_name" | grep -oP '\d+')
    week_num_padded=$(printf "%02d" "$week_num")

    html_file="$week_dir/${week_name}.html"
    if [ -f "$html_file" ]; then
      title=$(grep -oP '(?<=<title>).*?(?=</title>)' "$html_file" | head -1)
      topic=$(echo "$title" | sed -E 's/^.*Week [0-9]+ ?[-—] ?//')
    else
      topic="$week_name"
    fi

    echo "| $week_num_padded | $topic | [Lecture](${week_name}/${week_name}.html) |" >> "$qmd_file"
  done

  echo "" >> "$qmd_file"
  echo ": {.table .table-striped .table-hover}" >> "$qmd_file"

  echo "==> Rendering lectures landing page..."
  cd "$LANDING_DIR"
  quarto render index.qmd --output index.html
  cd "$SCRIPT_DIR"

  if [ -f "$SCRIPT_DIR/icon.png" ]; then
    sed -i 's#</head>#  <link rel="icon" type="image/png" href="/icon.png" />\
</head>#' "$LANDING_DIR/index.html"
  fi
}

generate_landing_page

echo "==> Syncing site root index..."
rsync -avz -e "$SSH_CMD" \
  "$SCRIPT_DIR/index.html" \
  "$REMOTE:$REMOTE_ROOT/index.html"

if [ -f "$SCRIPT_DIR/icon.png" ]; then
  echo "==> Syncing favicon..."
  rsync -avz -e "$SSH_CMD" \
    "$SCRIPT_DIR/icon.png" \
    "$REMOTE:$REMOTE_ROOT/icon.png"
fi

echo "==> Syncing lectures landing page..."
rsync -avz -e "$SSH_CMD" \
  "$LANDING_DIR/index.html" \
  "$REMOTE:$REMOTE_ROOT/computer-vision/index.html"

echo "==> Syncing lecture content..."
rsync -avz --delete -e "$SSH_CMD" \
  --exclude='/index.html' \
  --exclude='index.qmd' \
  "$SCRIPT_DIR/computer-vision/" \
  "$REMOTE:$REMOTE_ROOT/computer-vision/"

echo "==> Cleaning up..."
rm -rf "$LANDING_DIR"

echo "==> Done! Site is live at https://benjaminhoughton.georgetown.domains/"
