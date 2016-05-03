FROM ruby:2.2-slim

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r redmine && useradd -r -g redmine redmine

# grab gosu for easy step-down from root
ENV GOSU_VERSION 1.7
RUN set -x \
    && curl -fSL -o /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && curl -fSL -o /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && rm -r "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true

# grab tini for signal processing and zombie killing
ENV TINI_VERSION v0.9.0
RUN set -x \
    && curl -fSL -o /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini" \
    && curl -fSL -o /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini.asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5 \
    && gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini \
    && rm -r "$GNUPGHOME" /usr/local/bin/tini.asc \
    && chmod +x /usr/local/bin/tini \
    && tini -h

RUN apt-get update && apt-get install -y --no-install-recommends \
    	    imagemagick \
	    		libmysqlclient18 \
					 libpq5 \
					 	libsqlite3-0 \
							     \
								bzr \
								    git \
								    	mercurial \
										  openssh-client \
										  		 subversion \
												 && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV production
WORKDIR /usr/src/redmine

ENV REDMINE_VERSION 3.2.0
ENV REDMINE_DOWNLOAD_MD5 425aa0c56b66bf48c878798a9f7c6546

RUN curl -fSL "http://www.redmine.org/releases/redmine-${REDMINE_VERSION}.tar.gz" -o redmine.tar.gz \
    && echo "$REDMINE_DOWNLOAD_MD5 redmine.tar.gz" | md5sum -c - \
    && tar -xvf redmine.tar.gz --strip-components=1 \
    && rm redmine.tar.gz files/delete.me log/delete.me \
    && mkdir -p tmp/pdf public/plugin_assets \
    && chown -R redmine:redmine ./

RUN buildDeps='\
	gcc \
	    libmagickcore-dev \
	    		      libmagickwand-dev \
			      			libmysqlclient-dev \
								   libpq-dev \
								   	     libsqlite3-dev \
									     		    make \
											    	 patch \
												 ' \
												 && set -ex \
												 && apt-get update && apt-get install -y $buildDeps --no-install-recommends \
												 && rm -rf /var/lib/apt/lists/* \
												 && bundle install --without development test \
												 && for adapter in mysql2 postgresql sqlite3; do \
												    echo "$RAILS_ENV:" > ./config/database.yml; \
												    	 echo "  adapter: $adapter" >> ./config/database.yml; \
													      bundle install --without development test; \
													      done \
													      && rm ./config/database.yml \
													      && apt-get purge -y --auto-remove $buildDeps

# install some plugins
RUN git clone https://github.com/onozaty/redmine-parent-issue-filter.git parent_issue_filter && mv parent_issue_filter /usr/src/redmine/plugins/

# install theme
RUN git clone https://github.com/Nitrino/flatly_light_redmine.git && mv flatly_light_redmine /usr/src/redmine/public/themes/oop
COPY redmine/themes/oop/stylesheets/ /usr/src/redmine/public/themes/oop/stylesheets/

VOLUME /usr/src/redmine/files

COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 3000
# update plugins
CMD ["bundle", "exec", "rake", "redmine:plugins", "NAME=redmine_people,redmine_contacts", "RAILS_ENV=production"]
CMD ["rails", "server", "-b", "0.0.0.0"]