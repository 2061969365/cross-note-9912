# Architecture — CrossNote

## 目标
本地优先、离线可用、实时多端同步，阶段一用本地 Hono+WS+SQLite 模拟云端，阶段二平滑迁移到 Cloudflare Worker + Durable Objects。

## 分层
```
Flutter App (Android/Web/Windows 共用)
  app/            Material 3 + go_router + theme
  core/           config / network / storage
  models/         Note / Folder / SyncQueue (纯Dart)
  database/       drift + drift_flutter (SQLite, 无codegen手写迁移)
  repositories/   离线优先：先写本地SQLite -> 入sync_queue -> 后台同步
  sync/           SyncEngine + WsClient + ConflictResolver + sync_state
  features/       notes / folders / search / settings (Riverpod)
  platform/       平台隔离（device prefix 等）

Local Backend (Node.js + Hono)
  src/api/routes.ts        REST + /api/sync/pull|push
  src/websocket/handler.ts WS: hello/pull/push/broadcast
  src/sync/store.ts        Store 接口（隔离DB，便于未来替换为DO存储）
  src/sync/conflict.ts     LWW 确定性冲突解决
  src/database/db.ts       node:sqlite + WAL
packages/protocol/sync_protocol.md  协议权威定义

```

## 迁移预留
- `Store` 接口：当前为 node:sqlite 实现，未来替换为 DO storage / D1。
- `Broadcaster` 接口：当前为 ws 内存广播，未来替换为 DO hibernatable WebSocket + 跨实例发布。
- 协议为纯JSON，不依赖Node特定头部或中间件，便于 Worker 复用。
- 客户端通过 `server_url` 配置服务器地址，切换环境无需改代码。

## 数据流
```
用户编辑 -> Repository 立即写本地SQLite -> enqueue(PENDING) -> SyncEngine._drainQueue
  -> 优先 WS push -> 等 push_ack (applied / lww_rejected) -> 更新本地 / 推进cursor
  -> 失败则回退 REST push -> 仍失败则保留 PENDING，下次重连/轮询继续
拉取：hello带cursor -> pull since cursor -> 本地按 LWW 合并 -> 推进cursor
广播：server 接受写入后向除发送者外的所有在线WS广播 -> 客户端按LWW合并
```

## 冲突
LWW：updated_at 大者胜；同毫秒则 version 大者胜；再同则 device_id 字典序大者胜。服务端为权威，客户端收到 lww_rejected 时以服务端记录覆盖本地。
