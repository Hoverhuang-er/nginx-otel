## Stage 1: Build OpenTelemetry Module
#FROM debian:latest AS build-otel-module
#
## Install dependencies
#RUN apt-get update && \
#    apt-get install -y cmake libc-ares-dev g++ libre2-dev mercurial curl perl git libssl-dev zlib1g-dev libpcre3 libpcre3-dev
#RUN apt-get install -y perl-modules cpanminus
#RUN cpan Crypt::Misc
#RUN cpan Net::SSLeay
#RUN cpan IO::Socket::SSL
#
## Clone nginx repository
#RUN hg clone http://hg.nginx.org/nginx/ /nginx
#
## Configure nginx
#WORKDIR /nginx
#RUN ./auto/configure --with-compat
#
## Clone ngx_otel_module repository
#WORKDIR /
#RUN git clone https://github.com/nginxinc/nginx-otel.git /nginx-otel
#
## Create build directory
#RUN mkdir -p /nginx-otel/build
#
## Build module
#WORKDIR /nginx-otel/build
#RUN cmake -DNGX_OTEL_NGINX_BUILD_DIR=/nginx/objs -DNGX_OTEL_DEV=ON .. && \
#    make -j 4 && \
#    strip ngx_otel_module.so
#
## Archive module
#RUN mkdir -p /artifacts && \
#    cp /nginx-otel/build/ngx_otel_module.so /artifacts/
#
## Stage 2: Build Nginx
#FROM debian:latest AS build-nginx
#
## Copy artifacts from build-otel-module stage
#COPY --from=build-otel-module /artifacts /artifacts
#
## Install dependencies
#RUN apt-get update && \
#    apt-get install -y cmake libc-ares-dev g++ libre2-dev mercurial curl perl git libssl-dev zlib1g-dev libpcre3 libpcre3-dev && \
#RUN apt-get install -y perl-modules cpanminus
#RUN cpan Crypt::Misc
#RUN cpan Net::SSLeay
#RUN cpan IO::Socket::SSL
#
## Clone nginx-tests repository
#RUN hg clone http://hg.nginx.org/nginx-tests/ /nginx-tests
#
## Clone nginx-nacos-upstream repository
#RUN git clone https://github.com/nacos-group/nginx-nacos-upstream /nginx-nacos-upstream
#
## Copy nginx-nacos-upstream to the same level as auto/configure
#RUN cp -r /nginx-nacos-upstream /nginx/modules/nacos
## Clone nginx repository
#RUN hg clone http://hg.nginx.org/nginx/ /nginx
## Build nginx with additional modules
#WORKDIR /nginx
#RUN ./auto/configure --with-compat --with-debug --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_stub_status_module \
#                   --add-module=../modules/auxiliary --add-module=../modules/nacos --prefix=.. \
#                   --conf-path=conf/my.conf --error-log-path=objs/logs/error.log --pid-path=objs/logs/nginx.pid \
#                   --lock-path=objs/logs/nginx.lock --http-log-path=objs/logs/access.log && \
#    make -j 4
#
## Copy all object files
#RUN find /nginx/objs -name '*.o' -exec cp {} /artifacts/ \;

# Stage 3: Runtime
FROM debian:latest AS runtime

WORKDIR /nginx
COPY --from=docker.io/cdfng/nginx:ngx_otel /artifacts /artifacts
COPY --from=docker.io/cdfng/nginx:ngx_otel /nginx /nginx
#COPY --from=docker.io/cdfng/nginx:ngx_otel /nginx-tests /nginx-tests
COPY --from=docker.io/cdfng/nginx:ngx_nacos /nginx-nacos-upstream /nginx-nacos-upstream
## Copy artifacts from build-nginx stage
#COPY --from=build-nginx /artifacts /artifacts
#COPY --from=build-nginx /nginx /nginx
##COPY --from=build-nginx /nginx-tests /nginx-tests
#COPY --from=build-nginx /nginx-nacos-upstream /nginx-nacos-upstream

# Optimize kernel parameters and install BBR
RUN sysctl -w net.core.somaxconn=1024 && \
    sysctl -w net.ipv4.tcp_tw_reuse=1 && \
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf && \
    sysctl -p

# Set entrypoint to start nginx
ENTRYPOINT ["/nginx/objs/nginx", "-g", "daemon off;"]