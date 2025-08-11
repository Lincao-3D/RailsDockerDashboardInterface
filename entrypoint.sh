#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
# Assuming WORKDIR is /home/appuser/app as set in Dockerfile final stage
rm -f tmp/pids/server.pid

# RAILS_ENV will be set by Render (or other production ENV VARS)
echo "Entrypoint: RAILS_ENV is currently: ${RAILS_ENV}"
echo "Entrypoint: Executing main command: $@"

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"