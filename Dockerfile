# Dockerfile

# ---- Base Stage ----
FROM ruby:2.7.8-slim AS base

# Ensure all ENV lines use KEY="value" or KEY="${VAR:-default}"
ENV LANG="C.UTF-8"
ENV RAILS_ENV="${RAILS_ENV:-production}"
ENV RACK_ENV="${RACK_ENV:-production}"
ENV RAILS_LOG_TO_STDOUT="true"
ENV RAILS_SERVE_STATIC_FILES="true"
# Set BUNDLE_WITHOUT globally for the build stages
ENV BUNDLE_WITHOUT="development:test"
# Use available processors for bundling
ENV BUNDLE_JOBS="$(nproc)"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    libpq-dev \
    nodejs \
    postgresql-client \
    libyaml-dev \
    tzdata && \
    rm -rf /var/lib/apt/lists/*

# Upgrade RubyGems to a specific version compatible with Ruby 2.7
# and then install the Bundler version specified in Gemfile.lock
# RubyGems 3.4.x series is compatible with Ruby 2.7.x
# Pick a late version from the 3.4.x series.
RUN gem update --system 3.4.22 && \
    gem install bundler:2.4.22
	# ^ Match your Gemfile.lock's BUNDLED WITH version

# Create app group and user first
RUN groupadd --gid 1000 appuser && \
    useradd --uid 1000 --gid 1000 --create-home --home-dir /home/appuser --shell /bin/bash appuser

# Create app directory and set initial ownership for /home/appuser (for Bundler user config)
# and /home/appuser/app (for app files)
RUN mkdir -p /home/appuser/app && \
    chown -R appuser:appuser /home/appuser

# Switch to the non-root user EARLY
USER appuser
WORKDIR /home/appuser/app

# ---- Builder Stage ----
FROM base AS builder
# Inherits WORKDIR /home/appuser/app and USER appuser from base

# Copy Gemfile and Gemfile.lock
# Ownership should be correct due to USER appuser inherited from base
COPY Gemfile Gemfile.lock ./

# Configure Bundler locally for this application and install gems
# Bundler will attempt to write to /home/appuser/.bundle, which should now be writable by appuser
RUN bundle config set --local deployment 'true' && \
    bundle install --jobs "$(nproc)" --retry 3 && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem && \
    find vendor/bundle/ruby/*/gems/ -name "*.c" -delete && \
    find vendor/bundle/ruby/*/gems/ -name "*.o" -delete

# Copy the rest of the application code
COPY . .

# Precompile assets
# Pass RAILS_ENV and the new ASSETS_PRECOMPILE_CONTEXT
# SECRET_KEY_BASE_DUMMY is needed if credentials are not fully loaded for asset precompilation
RUN SECRET_KEY_BASE_DUMMY=1 \
	RAILS_ENV="${RAILS_ENV}" \
	ASSETS_PRECOMPILE_CONTEXT=true \
	bundle exec rails assets:precompile --trace

# ---- Final Stage ----
FROM base AS final
# Inherits WORKDIR /home/appuser/app and USER appuser from base

# Copy installed gems (vendor/bundle) and precompiled assets from builder stage
COPY --from=builder /home/appuser/app/vendor/bundle /home/appuser/app/vendor/bundle
COPY --from=builder /home/appuser/app/public/assets /home/appuser/app/public/assets

# Copy the application code (already owned by appuser due to previous COPY in builder and USER appuser)
# This COPY ensures the final image has the app code, not just assets/gems.
COPY . .

EXPOSE 3000

# entrypoint.sh should have been copied in the 'COPY . .' above if it's in the repo root
# Ensure it's executable
RUN chmod +x /home/appuser/app/entrypoint.sh

ENTRYPOINT ["/home/appuser/app/entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
