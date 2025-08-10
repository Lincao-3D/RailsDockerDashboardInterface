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

# Create app directory and a non-root user
RUN mkdir -p /home/appuser/app && \
    useradd --create-home --home-dir /home/appuser --shell /bin/bash appuser && \
    chown -R appuser:appuser /home/appuser/app

WORKDIR /home/appuser/app
USER appuser

# ---- Builder Stage ----
FROM base AS builder
# Inherits USER appuser and WORKDIR /home/appuser/app

# Copy Gemfile and Gemfile.lock
COPY --chown=appuser:appuser Gemfile Gemfile.lock ./

# Configure Bundler locally for this application and install gems
RUN bundle config set --local deployment 'true' && \
    bundle install --jobs "$(nproc)" --retry 3 && \
    rm -rf vendor/bundle/ruby/*/cache/*.gem && \
    find vendor/bundle/ruby/*/gems/ -name "*.c" -delete && \
    find vendor/bundle/ruby/*/gems/ -name "*.o" -delete

# Copy the rest of the application code
COPY --chown=appuser:appuser . .

# Precompile assets
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

# ---- Final Stage ----
FROM base AS final
# Inherits USER appuser and WORKDIR /home/appuser/app

# Copy installed gems (vendor/bundle) and precompiled assets from builder stage
COPY --from=builder --chown=appuser:appuser /home/appuser/app/vendor/bundle /home/appuser/app/vendor/bundle
COPY --from=builder --chown=appuser:appuser /home/appuser/app/public/assets /home/appuser/app/public/assets

# Copy the application code
COPY --chown=appuser:appuser . .

EXPOSE 3000

COPY --chown=appuser:appuser entrypoint.sh /home/appuser/app/entrypoint.sh
RUN chmod +x /home/appuser/app/entrypoint.sh

ENTRYPOINT ["/home/appuser/app/entrypoint.sh"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

