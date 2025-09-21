# AINoval 一键部署（Docker 版）

本指南面向开源用户，提供无需自行构建前端与后端的简易部署方案：一个镜像同时打包后端 JAR 与已编译的 Web 静态文件，配合 docker-compose 可一键启动，并内置可选的 MongoDB 服务。

## 目录结构

```
deploy/
  ├─ dist/
  │   ├─ ainoval-server.jar       # 预编译后端
  │   └─ web/                     # 预编译前端静态文件
  ├─ open/
  │   ├─ README.md                # 本指南
  │   ├─ Dockerfile               # 开源镜像 Dockerfile（相对路径复制 dist）
  │   ├─ docker-compose.yml       # 开源 docker-compose（相对路径引用本目录 env）
  │   ├─ production.env.example   # 环境变量示例
  │   └─ production.env           # 实际运行环境变量（建议忽略到版本库外）
```

## 系统要求
- Docker 24+，Docker Compose v2+
- 至少 1GB 可用内存（建议 2GB+），磁盘 2GB+

## 快速开始
1) 准备环境变量
- 复制 `deploy/open/production.env.example` 到 `deploy/open/production.env`
- 根据你的实际情况修改变量（尤其是 Mongo、JWT、对象存储、代理、API Key 等）
- 将github右边的release下的ainovel.jar包下载，复制到deploy/dist目录下

2) 构建镜像（或使用你私有仓库已推送的镜像）
```bash
# 方式A：在仓库根目录执行
docker compose -f deploy/open/docker-compose.yml build

# 方式B：在 deploy/open 目录执行（无需重复路径）
cd deploy/open
docker compose -f docker-compose.yml build
# 或
docker compose build
```

3) 启动服务
```bash
# 仓库根目录
docker compose -f deploy/open/docker-compose.yml up -d

# 或在 deploy/open 目录
docker compose -f docker-compose.yml up -d
# 或
docker compose up -d
```
启动后访问：http://localhost:18080/

> 提示：开源一键部署使用 `open-dev` 配置，默认连接 compose 中的 `mongo` 服务，并显式在 Mongo 连接字符串上添加 `retryWrites=false&retryReads=false` 以兼容单机 Mongo（非副本集）。如果你改用外部 Mongo，请参考下方示例。

## MongoDB 说明
- 默认 compose 已包含 `mongo` 服务（镜像：mongo:6.0），开源一键部署默认使用 dev 模式、无认证。
- 如你已有外部 MongoDB，可：
  - 注释/删除 `docker-compose.yml` 中的 `mongo` 服务；
  - 在 `deploy/open/production.env` 设置 `SPRING_DATA_MONGODB_URI` 指向外部实例；单机外部 Mongo 建议示例：
    - `SPRING_DATA_MONGODB_URI=mongodb://host:27017/ainovel?retryWrites=false&retryReads=false`
    - 如你的 Mongo 是副本集，可去掉 `retryWrites/Reads=false` 并加上 `replicaSet=xxx`。

## 重要环境变量（节选）
- 端口与 JVM：`SERVER_PORT`、`JVM_XMS`、`JVM_XMX`
- Mongo（dev 无认证）：`SPRING_DATA_MONGODB_URI`（默认 `mongodb://mongo:27017/ainovel`）
 - 向量库（Chroma）：默认关闭，`VECTORSTORE_CHROMA_ENABLED=false`
   - 开启：将其设为 `true` 并确保 `CHROMA_URL` 可达（如 `http://host.docker.internal:18000` 或独立容器地址）。
- JWT：`JWT_SECRET`（务必改成强随机值）
- 存储：`STORAGE_PROVIDER`（local/alioss…），以及对应供应商参数
- 代理：`PROXY_ENABLED`、`PROXY_HOST`、`PROXY_PORT`
- 向量库：`CHROMA_URL`（如需）
- AI Key：`OPENAI_API_KEY`、`GEMINI_API_KEY`、`ANTHROPIC_API_KEY` 等

> 注意：示例 env 仅用于演示，生产环境请务必替换为你自己的安全值。

## 日志与数据
- 应用日志挂载在 `deploy/open/logs`（compose 中映射到容器 `/var/log/ainoval`）。
- MongoDB 数据保存在命名卷 `mongo-data` 中。

## 常见操作
- 查看日志：
```bash
docker compose -f deploy/open/docker-compose.yml logs -f ainoval
```
- 重启服务：
```bash
docker compose -f deploy/open/docker-compose.yml restart ainoval
```
- 停止并删除容器：
```bash
docker compose -f deploy/open/docker-compose.yml down
```

## 常见问题
- 无法访问页面：检查容器是否正常启动、端口是否被占用；或修改 `ports` 映射。
- 连接 Mongo 失败：检查 `MONGO_*` 变量，或确认外部 Mongo 地址/鉴权。
- 前端静态资源 404：镜像内置静态目录 `/app/web/`，通过 JVM 参数 `-Dspring.web.resources.static-locations` 暴露；确保 `deploy/dist/web/` 在构建前已准备完整。

如有改进建议或问题反馈，欢迎提交 Issue！
