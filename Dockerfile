FROM ubuntu:20.04 AS compile

ENV DEBIAN_FRONTEND=noninteractive
ARG VERSION=18.8.0
ENV VERSION ${VERSION}

RUN apt update && \
    apt install -y wget \
    aptitude \
    debconf \
    default-libmysqlclient-dev

RUN mkdir -p /opt/source /opt/build/etc/init.d /opt/build/etc/default /opt/build/usr/share/asterisk

WORKDIR /opt/source
RUN wget -O asterisk.tar.gz https://github.com/asterisk/asterisk/archive/refs/tags/${VERSION}.tar.gz
RUN tar -zxf asterisk.tar.gz --strip 1

RUN ./contrib/scripts/install_prereq install
RUN ./contrib/scripts/get_mp3_source.sh
RUN ./configure --with-pjproject-bundled --with-jansson-bundled --disable-optimizations

COPY menuselect/menuselect.makeopts menuselect.makeopts
COPY menuselect/menuselect.makedeps menuselect.makedeps

RUN make
RUN make DESTDIR=/opt/build install
RUN make DESTDIR=/opt/build config
RUN make DESTDIR=/opt/build samples
RUN make DESTDIR=/opt/build install-logrotate

WORKDIR /opt
RUN rm -fr /opt/source /opt/asterisk.tar.gz

FROM ubuntu:20.04 as build

ENV DEBIAN_FRONTEND=noninteractive
ARG VERSION=18.8.0
ENV VERSION ${VERSION}

COPY --from=compile /opt/build /opt/build

RUN apt update && \
    apt install -y fakeroot \
    gettext

WORKDIR /opt
RUN mkdir -p /opt/build/DEBIAN
COPY DEBIAN/postinstall /opt/build/DEBIAN/postinst
RUN chmod +x /opt/build/DEBIAN/postinst

COPY DEBIAN/control control
RUN envsubst < /opt/control > /opt/build/DEBIAN/control

RUN fakeroot dpkg-deb -b /opt/build /opt/asterisk.deb

RUN rm -rf /opt/build

FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

COPY --from=build /opt/asterisk.deb /tmp/
RUN apt update && \
    apt install -y /tmp/asterisk.deb \
    lua5.2 \
    liblua5.2-dev \
    lua-sql-mysql \
    unixodbc

EXPOSE 5060/udp
ENTRYPOINT ["/usr/sbin/asterisk"]
CMD ["-c", "-vvvv", "-g"]
