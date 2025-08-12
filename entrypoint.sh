#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Remove a potentially pre-existing server.pid for Rails.
if [ -f /home/appuser/app/tmp/pids/server.pid ]; then
  rm /home/appuser/app/tmp/pids/server.pid
fi

echo "Entrypoint: RAILS_ENV is currently: ${RAILS_ENV}"

echo "Entrypoint: Running database migrations..."
bundle exec rails db:migrate
echo "Entrypoint: Database migrations complete."

echo "Entrypoint: Running database seeds..."
bundle exec rails db:seed # Make sure this line is active
echo "Entrypoint: Database seeds complete."

# Then exec the container's main process (CMD in Dockerfile).
# This will be 'bundle exec puma -C config/puma.rb' from your Dockerfile's CMD.
echo "Entrypoint: Executing main command: $@"
exec "$@"

