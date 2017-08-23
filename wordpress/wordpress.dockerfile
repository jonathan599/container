FROM wordpress:4.8.1
RUN apt-get update && apt-get install -y \
    netcat cpanminus wget \
    liblog-log4perl-perl libdbi-perl  libwww-search-perl \
    libtemplate-plugin-gd-perl libxml-simple-perl libcgi-pm-perl \
    libemail-valid-perl libpdf-api2-perl librtf-writer-perl \
    liburi-encode-perl libdbd-mysql-perl
RUN rm -rf /var/lib/apt/lists/*
RUN apt-get autoremove
RUN cpanm Bio::Perl --notest
RUN ln -s /usr/local/gkb/modules/ /usr/modules
RUN ln -s /usr/bin/perl /usr/local/bin/perl
RUN mkdir -p /usr/local/gkb/website/html/img-tmp \
    && chmod a+r /usr/local/gkb/website/html/img-tmp \
    && chown www-data:www-data /usr/local/gkb/website/html/img-tmp \
    && ln -s /usr/local/gkb/website/html/img-tmp /usr/src/wordpress/img-tmp
