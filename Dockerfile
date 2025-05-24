# Usage:
#
#   $ docker build . -t csd
#   $ docker run -v $(pwd):/app -ti csd rake test

FROM jetthoughts/cimg-ruby:3.4-chrome

ENV DEBIAN_FRONTEND=noninteractive \
 BUNDLE_PATH=/bundle

RUN --mount=type=cache,target=/var/cache/apt \
    sudo sed -i 's|http://security.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list && \
    sudo apt-get update -qq && \
    sudo apt-get install -qq --fix-missing \
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
    sudo apt-get autoclean

RUN sudo sed -i 's/true/false/g' /etc/fonts/conf.d/10-antialias.conf


RUN sudo mkdir -p /bundle /tmp/.X11-unix && \
    sudo chmod 1777 /bundle /tmp/.X11-unix

WORKDIR /app
