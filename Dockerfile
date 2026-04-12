# Usage:
#
#   $ docker build . -t csd
#   $ docker run -v $(pwd):/app -ti csd rake test

FROM jetthoughts/cimg-ruby:4.0-chrome

ENV DEBIAN_FRONTEND=noninteractive \
    BUNDLE_PATH=/bundle

# Install system dependencies with cached apt
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    sudo sed -i 's|http://security.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list && \
    sudo apt-get update -qq && \
    sudo apt-get install -y --no-install-recommends \
      automake \
      build-essential \
      curl \
      gettext \
      gobject-introspection \
      gtk-doc-tools \
      libexif-dev \
      libfftw3-dev \
      libgif-dev \
      libglib2.0-dev \
      libgsf-1-dev \
      libgtk2.0-dev \
      libmagickwand-dev \
      libmatio-dev \
      libopenexr-dev \
      libopenslide-dev \
      liborc-0.4-dev \
      libpango1.0-dev \
      libpoppler-glib-dev \
      librsvg2-dev \
      libtiff5-dev \
      libvips-dev \
      libwebp-dev \
      libxml2-dev \
      swig && \
    sudo rm -rf /var/lib/apt/lists/*

# Setup directories and fix font config if file exists
RUN sudo mkdir -p /bundle /tmp/.X11-unix && \
    sudo chmod 1777 /bundle /tmp/.X11-unix && \
    (sudo test -f /etc/fonts/conf.d/10-yes-antialias.conf && sudo sed -i 's/true/false/g' /etc/fonts/conf.d/10-yes-antialias.conf || echo "Font config file not found, skipping")

WORKDIR /app

# Copy entire project (needed for git dependencies in gems.rb)
COPY --chown=circleci:circleci . .

# Install gems
RUN sudo chown -R circleci:circleci /bundle && \
    bundle config set without 'tools' && \
    bundle install
