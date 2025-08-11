# !/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /home/appuser/app/tmp/pids/server.pid # <-- Use full path or ensure WORKDIR is set before

# RAILS_ENV will be set by Render, so this line is mostly for local consistency if you use this script.
echo "RAILS_ENV is currently: ${RAILS_ENV}"
echo "Executing main command: $@"

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"