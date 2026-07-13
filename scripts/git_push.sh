#!/bin/bash
# Push to GitHub using GITHUB_PAT from .env (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

if [ -z "${GITHUB_PAT:-}" ]; then
    echo "ERROR: GITHUB_PAT is not set in .env"
    echo "Add: GITHUB_PAT=ghp_... or github_pat_..."
    exit 1
fi

BRANCH="${1:-$(git branch --show-current)}"
REMOTE="${GITHUB_REMOTE:-origin}"
REPO="${GITHUB_REPO:-VenomekPL/MediaCenter}"

echo "Pushing ${BRANCH} to ${REMOTE} (${REPO})..."
git push "https://x-access-token:${GITHUB_PAT}@github.com/${REPO}.git" "${BRANCH}"
echo "Done."
