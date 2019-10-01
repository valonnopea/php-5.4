FROM debian:stretch-slim
MAINTAINER "Mira Manninen <mir@mireiawen.net>"

ENV PHP_VERSION "5.4.45"
ENV FPM_VERSION "0.5.14"
ENV PHP_USER "www-data"
ENV PHP_GROUP "www-data"

# Prevent Debian's PHP packages from being installed
RUN \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# Update the apt
RUN \
	apt-get "update" && \
	apt-get "upgrade" --yes

# Delete the "index.html" that installing Apache drops in here
RUN \
	rm -rvf /var/www/html/*

RUN \
	[ ! -d "/var/www/html" ]; \
	mkdir -p "/var/www/html"; \
	chown "www-data:www-data" "/var/www/html"; \
	chmod 777 "/var/www/html"

# Install software to get sources prepared
RUN \
	apt-get "install" --yes \
		"curl" \
		"patch" \
		"lsb-release"

# Get the PHP sources
RUN \
	curl --silent \
		--output "/tmp/php.tar.bz2" \
		"https://museum.php.net/php5/php-${PHP_VERSION}.tar.bz2" && \
	tar --extract \
		--preserve-permissions \
		--bzip2 \
		--directory "/usr/src" \
		--file "/tmp/php.tar.bz2"

# Self-made patch
COPY \
	"patches/disable_SSLv3_for_openssl_1_0_0.patch" \
	"/tmp/disable_SSLv3_for_openssl_1_0_0.patch"

RUN \
	cd "/usr/src/php-${PHP_VERSION}" && \
	patch --strip="0" \
		< "/tmp/disable_SSLv3_for_openssl_1_0_0.patch"


# Install the pre-requirities for build
RUN \
	apt-get "install" --yes \
		"build-essential" \
		"pkg-config" \
		"libbz2-dev" \
		"libcurl4-gnutls-dev" \
		"libdb-dev" \
		"libfreetype6-dev" \
		"libgdbm-dev" \
		"libgmp-dev" \
		"libjpeg-dev" \
		"libmariadbclient-dev" \
		"libmariadbclient-dev-compat" \
		"libmcrypt-dev" \
		"libmhash-dev" \
		"libncurses-dev" \
		"libpng-dev" \
		"libpspell-dev" \
		"libreadline-dev" \
		"libssh2-1-dev" \
		"libssl1.0-dev" \
		"libtidy-dev" \
		"libxml2-dev" \
		"libxslt-dev" \
		"libz-dev" \
		"unixodbc-dev"

# Fix some include sources
RUN \
	ln --symbolic --force \
		"/usr/include/x86_64-linux-gnu/curl" \
		"/usr/include" && \
	ln --symbolic --force \
		"/usr/include/x86_64-linux-gnu/gmp.h" \
		"/usr/include/gmp.h"

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# Adds GNU HASH segments to generated executables (this is used if present, and is much faster than sysv hash; in this configuration, sysv hash is also generated)
# https://github.com/docker-library/php/issues/272
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -Wl,--hash-style=both -pie"

# Configure the PHP
RUN \
	cd "/usr/src/php-${PHP_VERSION}" && \
	./configure --prefix="/opt/php/${PHP_VERSION}" \
		--with-libdir="lib/x86_64-linux-gnu" \
		--enable-cli --enable-fastcgi --enable-fpm \
		--with-fpm-user="${PHP_USER}" \
		--with-fpm-group="${PHP_GROUP}" \
		--disable-debug \
		--enable-zend-multibyte \
		--enable-bcmath \
		--enable-json \
		--with-bz2 \
		--enable-calendar \
		--with-curl \
		--enable-exif \
		--enable-ftp \
		--with-gettext \
		--with-gmp \
		--with-iconv \
		--enable-mbstring \
		--with-mcrypt \
		--enable-memory-limit \
		--with-mhash \
		--enable-hash \
		--with-ncurses \
		--with-openssl \
		--with-pspell \
		--enable-sockets \
		--with-xmlrpc \
		--with-zlib \
		--with-flatfile \
		--with-gdbm \
		--with-inifile \
		--with-freetype-dir="/usr" \
		--enable-gd-native-ttf \
		--with-jpeg-dir="/usr" \
		--with-png \
		--with-gd \
		--with-unixODBC=shared,/usr \
		--with-readline \
		--with-xsl=shared \
		--enable-sqlite-utf8 \
		--enable-soap=shared \
		--enable-pdo=shared \
		--with-sqlite=shared \
		--with-pdo-sqlite=shared \
		--with-pdo-mysql=shared \
		--with-mysql=shared \
		--with-mysqli=shared \
		--enable-mbstr-enc-trans \
		--enable-mbregex \
		--enable-magic-quotes \
		--enable-discard-path \
		--with-pear \
		--enable-safe-mode \
		--enable-track-vars \
		--with-ttf \
		--enable-zip=shared \
		--enable-hts=shared \
		--with-imagick=shared \
		--enable-oauth=shared \
		--with-libssh2=shared \
		--enable-memcache=shared \
		--with-pdflib=shared,/opt/pdflib \
		--with-tidy=shared \
		--enable-intl=shared \
		--with-geoip=shared \
		--enable-mailparse=shared \
		--enable-apc=shared \
		--enable-xcache=shared \
		--with-fileinfo=shared \
		--enable-mmap \
		--with-config-file-path="/etc/php/${PHP_VERSION}/" \
		--with-config-file-scan-dir="/etc/php/${PHP_VERSION}/ext.d/"

# Do the actual compile and install
RUN \
	cd "/usr/src/php-${PHP_VERSION}" && \
	make && \
	find -type f -name '*.a' -delete && \
	make "install" && \
	find "/usr/local/bin" "/usr/local/sbin" -type "f" -executable -exec strip --strip-all '{}' + || true && \
	make "clean"

# Update the pecl channels
RUN \
	/opt/php/${PHP_VERSION}/bin/pecl "update-channels" && \
	rm -rf "/tmp/pear" "~/.pearrc"

# Set up the path to the PHP binaries for root
RUN \
	echo "PATH=\"\${PATH}:/opt/php/${PHP_VERSION}/bin\"" |tee "/etc/profile.d/php.sh"

RUN \
	echo "source \"/etc/profile.d/php.sh\"" |tee --append "/root/.bashrc"

# Create the user and group
RUN \
	getent 'group' "${PHP_GROUP}" || groupadd \
		--gid "1000" \
		"${PHP_GROUP}" && \
	getent 'passwd' "${PHP_USER}" || useradd \
		--comment "Web Application" \
		--home-dir "/var/www" \
		--gid "${PHP_GROUP}" \
		--no-create-home \
		--shell "/bin/bash" \
		--uid "1000" \
		"${PHP_USER}"

# Install configuration file
COPY \
	"php-fpm.conf" \
	"/opt/php/${PHP_VERSION}/etc/php-fpm.conf"
RUN \
	mkdir --parents "/opt/php/${PHP_VERSION}/etc/fpm.d"

# Set the startup commands
# @note: cannot use version here
ENTRYPOINT [ "/opt/php/5.4.45/sbin/php-fpm" ]
CMD [ "--fpm-config", "/opt/php/5.4.45/etc/php-fpm.conf" ]

# Define the data volumes
VOLUME [ "/var/www/html" ]

# Expose HTTP
EXPOSE 9000
