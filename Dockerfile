# Dockerfile
# syntax=docker/dockerfile:1.4 
# ↑ Good to keep for BuildKit features

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

# Create non-root user
RUN groupadd --gid 1000 appuser && \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/appuser \
      --shell /bin/bash appuser
# USER and WORKDIR will be set here, applicable to this stage and inherited
USER appuser
WORKDIR /home/appuser/app

# ---- Builder Stage ----
FROM base AS builder
# Inherits USER appuser and WORKDIR /home/appuser/app

# --- MODIFICATION: Use --chown on Gemfile and Gemfile.lock copy ---
COPY --chown=appuser:appuser Gemfile Gemfile.lock ./

RUN bundle config set --local deployment 'true' && \
    bundle install --jobs "$(nproc)" --retry 3 && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem && \
    find vendor/bundle/ruby/*/gems/ -name "*.c" -delete && \
    find vendor/bundle/ruby/*/gems/ -name "*.o" -delete

# --- MODIFICATION: Use --chown on main code copy ---
COPY --chown=appuser:appuser . .

# Ensure tmp and log directories exist and are writable by appuser
# Since all files were copied as appuser, appuser should be able to do this.
RUN mkdir -p tmp/cache/assets tmp/pids tmp/sockets log && \
    chmod -R u+rwX tmp log # Ensure correct permissions, u+rwX is good

# Assets precompilation
RUN <<'EOF'
set -e
echo "Running assets:precompile..."
SECRET_KEY_BASE_DUMMY=1 \
ASSETS_PRECOMPILE_CONTEXT=true \
bundle exec rails assets:precompile --trace 2>&1
EOF

# ---- Final Stage ----
FROM base AS final
# Inherits USER appuser and WORKDIR /home/appuser/app

# Copy only necessary artifacts from builder.
# Source paths are from the builder's WORKDIR (/home/appuser/app)
# Destination paths are to the final stage's WORKDIR (/home/appuser/app)
COPY --from=builder --chown=appuser:appuser /home/appuser/app/vendor/bundle ./vendor/bundle
COPY --from=builder --chown=appuser:appuser /home/appuser/app/public/assets ./public/assets
# Copy the rest of the application code that was already chowned in builder
COPY --from=builder --chown=appuser:appuser /home/appuser/app .

EXPOSE 3000

# entrypoint.sh should have been copied with correct ownership by the COPY . . above
# ↓ Path relative to WORKDIR
RUN chmod +x ./entrypoint.sh
# ↓ Path relative to WORKDIR
ENTRYPOINT ["./entrypoint.sh"] 
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

