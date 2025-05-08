# Usage:
#
#   $ docker build . -t csd
#   $ docker run -v $(pwd):/app -ti csd rake test

FROM --platform=linux/amd64 jetthoughts/cimg-ruby:3.4-chrome

# Install dependencies and clean up in one layer to reduce image size
RUN sudo apt-get update -qq && \
    DEBIAN_FRONTEND=noninteractive sudo apt-get install -qq \
      automake \
      build-essential \
      curl \
      fftw3-dev \
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
    sudo apt-get autoremove -y && \
    sudo apt-get autoclean && \
    sudo apt-get clean && \
    sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app
COPY gems.rb gemfiles capybara-screenshot-diff.gemspec /app/
COPY lib/capybara/screenshot/diff/version.rb /app/lib/capybara/screenshot/diff/

# Set the location for Bundler to store gems
ENV BUNDLE_PATH=/bundle

RUN sudo mkdir /bundle && \
    sudo chmod a+w+r /bundle

