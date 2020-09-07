ARG RUBY_VERSION=2.7

FROM cimg/ruby:${RUBY_VERSION}

RUN \

  # Install dependencies
  sudo apt-get update && \
  DEBIAN_FRONTEND=noninteractive sudo apt-get install -y \
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
    libwebp-dev \
    libxml2-dev \
    swig


WORKDIR /app
ADD . /app/

RUN \
  bundle install && \
  sudo /app/bin/install-vips

RUN \
  # Clean up
  sudo apt-get remove -y curl automake build-essential && \
  sudo apt-get autoremove -y && \
  sudo apt-get autoclean && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

