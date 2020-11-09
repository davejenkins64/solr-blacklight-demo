FROM ubuntu:latest
LABEL org.blacklight.demo=0.0.1

# initial install complains about missing apt-utils, but runs
RUN apt-get update && \
    apt-get install --yes apt-utils && \
    apt-get --yes dist-upgrade
RUN apt-get install --yes ruby-full
RUN apt-get install --yes curl
RUN apt-get install --yes git
RUN apt-get install --yes gcc
RUN apt-get install --yes make

# These are neeeded by rbenv to compile ruby
RUN apt-get install --yes autoconf 
RUN apt-get install --yes bison 
RUN apt-get install --yes build-essential 
RUN apt-get install --yes libssl-dev 
RUN apt-get install --yes libyaml-dev 
RUN apt-get install --yes libreadline6-dev 
RUN apt-get install --yes zlib1g-dev 
RUN apt-get install --yes libncurses5-dev 
RUN apt-get install --yes libffi-dev 
#RUN apt-get install --yes libgdbm6 
RUN apt-get install --yes libgdbm-dev 
RUN apt-get install --yes libdb-dev
RUN apt-get install --yes libsqlite3-dev

# rails needs this for tzinfo-data and a working javascript engine
RUN DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends tzdata
RUN apt-get install --yes node-base
RUN apt-get install --yes npm

# Yarn needs to come from a special repository (and uses curl)
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
RUN echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list
RUN apt-get update
RUN apt-get install --yes yarn

# For debugging
RUN apt-get install --yes vim

# Stuff we do as the user blacklight
RUN useradd -s /bin/bash -d /opt/blacklight -m blacklight
USER blacklight
WORKDIR /opt/blacklight

# Install rbenv and add to our path
ENV PATH=/opt/blacklight/.rbenv/bin:/opt/blacklight/.rbenv/shims:$PATH
RUN curl -fsSL https://github.com/rbenv/rbenv-installer/raw/master/bin/rbenv-installer | bash
# Note, when the ruby version changes, change in 2 lines below
RUN rbenv init || echo "Inititalized"
RUN rbenv install 2.7.2

# Remember our rebenv choices in our home directory
RUN rbenv local 2.7.2
RUN rbenv rehash

# rails below needs a few more gems
RUN gem install bundler
RUN gem install rails
RUN gem install solr_wrapper
RUN gem install tzinfo-data

# Finally, set up our search application
RUN rails new search_app -m https://raw.github.com/projectblacklight/blacklight/master/template.demo.rb
WORKDIR search_app
RUN grep -v 'name: blacklight-core' .solr_wrapper.yml > /tmp/.solr-wrapper.yml
RUN echo "name: osti" >> /tmp/.solr-wrapper.yml
RUN mv /tmp/.solr-wrapper.yml .
ENV SOLR_URL=http://192.168.21.222:8983/solr/osti

# start the rails server listening on all IPs
CMD [ "rails", "server", "--binding=0.0.0.0" ]
