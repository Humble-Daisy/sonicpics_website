# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t modelrails_base .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/credentials/production.key> --name modelrails_base modelrails_base

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .tool-versions.
# When invoked via Kamal, config/deploy.yml passes RUBY_VERSION as a build arg
# so the production image always matches the version Bundler enforces in
# Gemfile.lock (see Gemfile's `ruby file: ".tool-versions"` directive).
ARG RUBY_VERSION=4.0.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. `apt-get upgrade -y` first: Docker Hub rebuilds
# ruby:slim on Debian point releases, not on interim security updates, so
# this is the only reliable patch path between base-image rebuilds.
RUN apt-get update -qq && \
    apt-get upgrade -y -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    MALLOC_CONF="dirty_decay_ms:1000,muzzy_decay_ms:0"

# Throw-away build stage to reduce size of final image
FROM base AS build

# BuildKit auto-populates these from the build platform. We use them below to
# gate bootsnap precompile parallelism: -j 1 is required only under QEMU
# cross-arch emulation (rails/bootsnap#495); native builds use full parallelism.
# Empty values (legacy Docker without BuildKit) compare equal and take the
# native-parallel path, which is the desired fallback.
# https://docs.docker.com/build/building/variables/#multi-platform-build-arguments
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Install packages needed to build gems
# libssl-dev: the webauthn gem pulls in the openssl gem (native extension) which
# needs the OpenSSL headers to compile; the slim runtime base ships only libssl3.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config libssl-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems FIRST so the bundle install layer survives changes
# to vendor/ (including the markdowndocs symlink used for Tailwind scanning).
# .tool-versions is required by Gemfile's `ruby file:` directive — Bundler
# parses it during bundle install, so it must arrive in the same layer.
COPY Gemfile Gemfile.lock .tool-versions ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # Parallel bootsnap precompile on native builds; -j 1 only under QEMU
    # cross-arch emulation (rails/bootsnap#495).
    if [ "$TARGETPLATFORM" = "$BUILDPLATFORM" ]; then \
      bundle exec bootsnap precompile --gemfile; \
    else \
      bundle exec bootsnap precompile -j 1 --gemfile; \
    fi

# Vendor contents come after the bundle install layer so a vendor tweak
# doesn't bust the gem cache.
COPY vendor/ ./vendor/

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times. Same cross-arch gate as
# above: parallel on native, -j 1 only when emulating a different architecture.
RUN if [ "$TARGETPLATFORM" = "$BUILDPLATFORM" ]; then \
      bundle exec bootsnap precompile app/ lib/; \
    else \
      bundle exec bootsnap precompile -j 1 app/ lib/; \
    fi

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security.
# App code and gems stay root-owned (read-only to the rails user); only the
# dirs Rails writes at runtime are chowned — db (entrypoint db:prepare),
# log, storage (Active Storage volume), tmp (bootsnap cache, pids).
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
