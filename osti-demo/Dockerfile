FROM ubuntu:latest
LABEL gov.lanl.dl.demo=0.0.1

# initial install complains about missing apt-utils, but runs
RUN apt-get update && \
    apt-get install --yes apt-utils && \
    apt-get --yes dist-upgrade

# upgrade package with cpan, install cpanm
RUN apt-get --yes install gcc
RUN apt-get --yes install make 
RUN apt-get --yes install perl
RUN apt-get --yes install openssl
RUN apt-get --yes install libssl-dev
RUN apt-get --yes install libz-dev
RUN cpan install App::cpanminus
RUN cpan -T Net::SSLeay
RUN cpanm LWP::Protocol::https || cat /root/.cpanm/work/*/build.log
RUN cpanm JSON::XS
RUN cpanm Apache::Solr::JSON

RUN apt-get --yes install vim
# TODO make a user and workdir and copy there instead
# don't run as root
COPY load_solr.pl /var/tmp

#RUN /var/tmp/load_solr.pl

# Maybe start it from here
CMD [ "sleep", "600" ]
