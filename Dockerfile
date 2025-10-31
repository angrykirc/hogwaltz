ARG NGINX_VERSION=1.29.1
ARG BUILD_DEPS="apk-tools wget git tar linux-headers gcc g++ make cmake zlib-dev pcre-dev openssl-dev gd-dev c-ares-dev luajit-dev luajit"
ARG RUNTIME_DEPS="pcre luajit"

FROM alpine:latest AS build-stage

ARG NGINX_VERSION
ARG BUILD_DEPS

RUN apk update \
    && apk add ${BUILD_DEPS} \
    && apk upgrade

RUN wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
RUN tar -zxvf nginx-${NGINX_VERSION}.tar.gz

# Lua (openresty) module
RUN git clone --depth 1 --branch v0.10.28 https://github.com/openresty/lua-nginx-module.git
# lua-resty-core
RUN git clone --depth 1 --branch v0.1.31 https://github.com/openresty/lua-resty-core.git
# lua-resty-lrucache
RUN git clone --depth 1 --branch v0.15 https://github.com/openresty/lua-resty-lrucache.git
# lua-resty-random
RUN git clone --depth 1 --branch master https://github.com/bungle/lua-resty-random.git
# lua-resty-memcached
RUN git clone --depth 1 --branch master https://github.com/openresty/lua-resty-memcached.git
# lua-resty-ipmatcher
RUN git clone --depth 1 --branch master https://github.com/api7/lua-resty-ipmatcher.git

# fix for Lua module
ENV LUAJIT_LIB=/usr/lib
ENV LUAJIT_INC=/usr/include/luajit-2.1

# build modules
RUN cd nginx-${NGINX_VERSION} \
    && ./configure --with-compat --with-ld-opt='-lpcre' --with-cc-opt="-DJA3_SORT_EXT -Os -fstack-clash-protection -Wformat -Werror=format-security -fno-plt -g" \
       --add-dynamic-module=/lua-nginx-module \
    && make modules

# build lua-resty-core
RUN mkdir -p /etc/nginx/lualib \
    && cd /lua-resty-core \
    && make install LUA_LIB_DIR=/etc/nginx/lualib \
    && cd /lua-resty-lrucache \
    && make install LUA_LIB_DIR=/etc/nginx/lualib \
    && cd /lua-resty-memcached \
    && make install LUA_LIB_DIR=/etc/nginx/lualib \
    && cd /lua-resty-random \
    && make install LUA_LIB_DIR=/etc/nginx/lualib \
    && cd /lua-resty-ipmatcher \
    && make install INST_LUADIR=/etc/nginx/lualib

FROM nginx:${NGINX_VERSION}-alpine

ARG NGINX_VERSION
ARG RUNTIME_DEPS

RUN apk update \
    && apk add ${RUNTIME_DEPS} \
    && apk upgrade

# copy built modules
COPY --from=build-stage /nginx-${NGINX_VERSION}/objs/*.so /etc/nginx/modules/
# copy lua modules
COPY --from=build-stage /etc/nginx/lualib /etc/nginx/lualib

# copy stuff
COPY default.conf /etc/nginx/conf.d/
COPY nginx.conf /etc/nginx/
COPY hogwaltz/*.lua /etc/nginx/hogwaltz/

# fix permissions
RUN chown -R nginx:nginx /etc/nginx
