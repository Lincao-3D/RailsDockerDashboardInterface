# #!/bin/bash
# set -e

# # Remove a potentially pre-existing server.pid for Rails.
# rm -f /app/tmp/pids/server.pid

# # Check if Gemfile exists and install dependencies if needed.
# if [ -f Gemfile ]; then
  # echo "Gemfile found. Installing gems..."
  # bundle install
# else
  # echo "Gemfile not found. Skipping gem installation."
# fi
# export RAILS_ENV=${RAILS_ENV:-development} # <--- ADD OR ENSURE THIS
# echo "RAILS_ENV is set to: $RAILS_ENV"
# # Wait for the database service to be ready before proceeding.
# # This prevents errors during startup if the DB container isn't fully initialized.
# until pg_isready -h db -U postgres; do
  # echo "Waiting for the database service..."
  # sleep 2
# done
# echo "Database service is ready."

# # Prepare the database (creates if it doesn't exist, and runs migrations).
# echo "Preparing database for $RAILS_ENV environment..."
# bundle exec rails db:prepare # This will now use RAILS_ENV


# echo "Database prepared."

# echo "Executing main command: $@"

# # Then exec the container's main process (what's set as CMD in the Dockerfile).
# exec "$@" 
#--------------------production:
#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /home/appuser/app/tmp/pids/server.pid # <-- Use full path or ensure WORKDIR is set before

# RAILS_ENV will be set by Render, so this line is mostly for local consistency if you use this script.
echo "RAILS_ENV is currently: ${RAILS_ENV}"
echo "Executing main command: $@"

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"