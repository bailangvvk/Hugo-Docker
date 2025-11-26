# Hugo Static Compilation Docker Build with BusyBox
# 使用 busybox:musl 作为基础镜像，提供基本shell环境

# 构建阶段 - 使用完整的构建环境
FROM golang:1.24-alpine AS builder

# 安装构建依赖（包括C++编译器和strip工具）
RUN apk add --no-cache \
    gcc \
    g++ \
    musl-dev \
    git \
    build-base \
    binutils  # 包含strip命令

WORKDIR /app

# 直接下载并构建 Hugo（无需本地源代码）
RUN git clone --depth 1 https://github.com/gohugoio/hugo.git . && \
    CGO_ENABLED=1 go build \
    -tags extended,netgo,osusergo \
    -ldflags="-s -w -extldflags '-static' -X github.com/gohugoio/hugo/common/hugo.vendorInfo=docker" \
    -o hugo

# 使用strip进一步减小二进制文件大小
RUN strip --strip-all hugo

# 验证二进制文件是否为静态链接
RUN ldd hugo 2>&1 | grep -q "not a dynamic executable" && echo "Static binary confirmed" || echo "Not a static binary"

# 显示优化后的文件大小
RUN ls -lh hugo && echo "Binary size after stripping: $(stat -c%s hugo) bytes"

# 运行时阶段 - 使用busybox:musl（极小的基础镜像，包含基本shell）
FROM busybox:musl

# 复制CA证书（用于HTTPS请求）
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# 复制经过strip优化的Hugo二进制文件
COPY --from=builder /app/hugo /usr/local/bin/hugo

# 创建非root用户（增强安全性）
RUN adduser -D -u 1000 hugo

# 设置工作目录
WORKDIR /site

# 切换到非root用户
USER hugo

# 验证Hugo是否正常工作
RUN hugo version

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD hugo version > /dev/null || exit 1

# 暴露默认端口
EXPOSE 1313

# 设置入口点
ENTRYPOINT ["hugo"]

# 默认命令 - Hugo开发服务器
CMD ["server", "--bind", "0.0.0.0", "--baseURL", "http://localhost:1313"]
