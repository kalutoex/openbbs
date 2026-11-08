# OpenBBS 服务端镜像。只跑服务端：API + 服务端渲染页面 + 静态资源。
#
#   docker compose up -d --build
#
# 前端（web/）不进镜像，需要网页版就把它挂到 /app/web，或者用仓库里的 tar 部署。

FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    TZ=Asia/Shanghai

# tzdata 让日志时间是本地时间；curl 给健康检查用。
RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install -r /app/requirements.txt

COPY app /app/app
COPY static /app/static
COPY templates /app/templates
COPY config/site.json.example /app/config/site.json.example
COPY db_snapshot.py backup.sh restore.sh run.sh _cfg.sh check_update.sh VERSION /app/
COPY docker-entrypoint.sh /app/

RUN mkdir -p /app/data /app/logs /app/config \
 && chmod +x /app/docker-entrypoint.sh /app/backup.sh /app/restore.sh /app/run.sh

# 数据全在卷里：这两个目录挂出去，容器删了站还在。
VOLUME ["/app/data", "/app/config"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:$(python -c 'import sys;sys.path.insert(0,"/app");from app import config;print(config.get("server","port",8080))')/api/meta" > /dev/null || exit 1

EXPOSE 8080

ENTRYPOINT ["/app/docker-entrypoint.sh"]
