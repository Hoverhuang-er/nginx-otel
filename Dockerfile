# Stage 1: Build OpenTelemetry Module
FROM debian:latest AS build-otel-module

WORKDIR /opt

# Install dependencies
RUN apt-get update && \
    apt-get install -y cmake libc-ares-dev libre2-dev mercurial curl perl git 
RUN apt-get install -y perl-modules cpanminus
RUN cpan IO::Socket::SSL 
RUN cpan Crypt::Misc

# Clone nginx repository
RUN hg clone http://hg.nginx.org/nginx/ /opt/nginx

# Configure nginx
WORKDIR /opt/nginx
RUN auto/configure --with-compat

# Create build directory
WORKDIR /opt
RUN mkdir build

# Build module
WORKDIR /opt/build
RUN cmake -DNGX_OTEL_NGINX_BUILD_DIR=/opt/nginx/objs -DNGX_OTEL_DEV=ON .. && \
    make -j 4 && \
    strip ngx_otel_module.so

# Archive module
RUN mkdir -p /opt/artifacts && \
    cp /opt/build/ngx_otel_module.so /opt/artifacts/

# Stage 2: Build Nginx
FROM debian:latest AS build-nginx

WORKDIR /opt

# Copy artifacts from build-otel-module stage
COPY --from=build-otel-module /opt/artifacts /opt/artifacts
COPY --from=build-otel-module /opt/nginx /opt/nginx

# Install dependencies
RUN apt-get update && \
    apt-get install -y cmake libc-ares-dev libre2-dev mercurial curl perl git && \
    cpan IO::Socket::SSL Crypt::Misc

# Clone nginx-tests repository
RUN hg clone http://hg.nginx.org/nginx-tests/ /opt/nginx-tests

# Clone nginx-nacos-upstream repository
RUN git clone https://github.com/nacos-group/nginx-nacos-upstream /opt/nginx-nacos-upstream

# Copy nginx-nacos-upstream to the same level as auto/configure
RUN cp -r /opt/nginx-nacos-upstream /opt/nginx/modules/nacos

# Build nginx with additional modules
WORKDIR /opt/nginx
RUN auto/configure --with-compat --with-debug --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-http_stub_status_module \
                   --add-module=../modules/auxiliary --add-module=../modules/nacos --prefix=.. \
                   --conf-path=conf/my.conf --error-log-path=objs/logs/error.log --pid-path=objs/logs/nginx.pid \
                   --lock-path=objs/logs/nginx.lock --http-log-path=objs/logs/access.log && \
    make -j 4

# Copy all object files
RUN find /opt/nginx/objs -name '*.o' -exec cp {} /opt/artifacts/ \;

# Stage 3: Runtime
FROM debian:latest AS runtime

WORKDIR /opt

# Copy artifacts from build-nginx stage
COPY --from=build-nginx /opt/artifacts /opt/artifacts
COPY --from=build-nginx /opt/nginx /opt/nginx
COPY --from=build-nginx /opt/nginx-tests /opt/nginx-tests
COPY --from=build-nginx /opt/nginx-nacos-upstream /opt/nginx-nacos-upstream

# Optimize kernel parameters and install BBR
RUN sysctl -w net.core.somaxconn=1024 && \
    sysctl -w net.ipv4.tcp_tw_reuse=1 && \
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf && \
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf && \
    sysctl -p

# Set entrypoint to start nginx
ENTRYPOINT ["/opt/nginx/objs/nginx"]