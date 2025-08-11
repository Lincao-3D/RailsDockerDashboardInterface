# Dockerfile
# syntax=docker/dockerfile:1.4

# ---- Base Stage ----
FROM ruby:2.7.8-slim AS base

ENV LANG="C.UTF-8" \
    RAILS_ENV="production" \
    RACK_ENV="production" \
    RAILS_LOG_TO_STDOUT="true" \
    RAILS_SERVE_STATIC_FILES="true" \
    BUNDLE_WITHOUT="development:test" \
    BUNDLE_JOBS="$(nproc)"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git libpq-dev nodejs postgresql-client \
      libyaml-dev tzdata && \
    rm -rf /var/lib/apt/lists/*

RUN gem update --system 3.4.22 && \
    gem install bundler:2.4.22

RUN groupadd --gid 1000 appuser && \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/appuser \
      --shell /bin/bash appuser

USER appuser
WORKDIR /home/appuser/app

# ---- Builder Stage ----
FROM base AS builder
# Inherits USER appuser and WORKDIR /home/appuser/app

COPY --chown=appuser:appuser Gemfile Gemfile.lock ./

RUN bundle config set --local deployment 'true' && \
    bundle install --jobs "$(nproc)" --retry 3 && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem && \
    find vendor/bundle/ruby/*/gems/ -name "*.c" -delete && \
    find vendor/bundle/ruby/*/gems/ -name "*.o" -delete

COPY --chown=appuser:appuser . .

RUN mkdir -p tmp/cache/assets tmp/pids tmp/sockets log && \
# Ensure appuser owns these after creation as well
    chown -R appuser:appuser tmp log 

RUN <<'EOF'
set -e
echo "Builder: Running assets:precompile..."
SECRET_KEY_BASE_DUMMY=1 \
ASSETS_PRECOMPILE_CONTEXT=true \
bundle exec rails assets:precompile --trace 2>&1
EOF

# ---- Final Stage ----
FROM base AS final
# Inherits USER appuser and WORKDIR /home/appuser/app from base

# --- MODIFICATION START: Explicit Bundler/Gem Environment for Runtime ---
# Set environment variables to ensure Bundler knows where to find gems and its config.
# Paths are absolute, reflecting the WORKDIR /home/appuser/app.
ENV BUNDLE_PATH="/home/appuser/app/vendor/bundle" \
    BUNDLE_APP_CONFIG="/home/appuser/app/.bundle" \
    GEM_HOME="/home/appuser/app/vendor/bundle" \
    GEM_PATH="/home/appuser/app/vendor/bundle"

# Ensure the PATH includes where gem executables are.
# For Ruby 2.7.x, the directory is typically 'ruby/2.7.0'.
# This helps `bundle exec` or direct calls to gem executables.
ENV PATH="/home/appuser/app/vendor/bundle/bin:/home/appuser/app/vendor/bundle/ruby/2.7.0/bin:${PATH}"
# --- MODIFICATION END ---

# Copy necessary artifacts from the builder stage.
# These paths are relative to the WORKDIR in both stages (/home/appuser/app).
COPY --from=builder --chown=appuser:appuser /home/appuser/app/vendor/bundle /home/appuser/app/vendor/bundle
COPY --from=builder --chown=appuser:appuser /home/appuser/app/public/assets /home/appuser/app/public/assets
COPY --from=builder --chown=appuser:appuser /home/appuser/app /home/appuser/app


# Ensure entrypoint is executable
RUN chmod +x ./entrypoint.sh

EXPOSE 3000

ENTRYPOINT ["./entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

