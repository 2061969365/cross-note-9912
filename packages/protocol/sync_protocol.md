# Sync Protocol v1 — CrossNote

## 目标
本地优先：客户端离线可写，联网自动补同步，多端实时一致，基础冲突可收敛。

## 核心规则
- 主键：UUID v4，客户端生成。
- 版本：整数 `version`，每次服务端接受写入时 +1。客户端本地自增初始为1，服务端为权威。
- 时间：ISO8601 `updated_at`，服务端以接收时间为准；客户端本地时间为参考。
- 软删除：`deleted_at != null` 表示已删除，保留墓碑用于同步。
- 冲突策略：LWW (Last-Write-Wins) 按 `updated_at`，同毫秒则 `version` 大者胜，再同则 `device_id` 字典序大者胜。保证确定性收敛。

## 传输层
- 首选 WebSocket `ws://localhost:8787/ws`
- 降级：HTTP `POST /api/sync/push` + `GET /api/sync/pull?since=...`

## WebSocket 消息

### Client -> Server
```json
{"type":"hello","deviceId":"android-xxx","cursor":"2024-..."}
{"type":"push","entityType":"note","operation":"CREATE|UPDATE|DELETE","entity":{...}}
{"type":"pull","since":"2024-...","limit":100}
```

### Server -> Client
```json
{"type":"hello_ack","cursor":"2024-...","serverTime":"..."}
{"type":"push_ack","entityType":"note","id":"uuid","version":2,"updated_at":"...","applied":true,"conflict":"none|lww_rejected"}
{"type":"broadcast","entityType":"note","operation":"CREATE|UPDATE|DELETE","entity":{...}}
{"type":"pull_result","notes":[...],"folders":[...],"cursor":"...","hasMore":false}
{"type":"error","message":"..."}
```

## REST 降级

- `POST /api/sync/push` Body: `{entityType, operation, entity}` -> `{entity, conflict}`
- `GET /api/sync/pull?since=ISO&limit=100&includeDeleted=1` -> `{notes, folders, cursor, hasMore}`
- `GET /api/notes?since=&includeDeleted=0&limit=100` / `GET /api/folders?...`
- CRUD 便捷路由：`POST /api/notes`, `PUT /api/notes/:id`, `DELETE /api/notes/:id` 等均走同一冲突路径。

## 客户端同步流程
```
用户编辑 -> 立即写本地SQLite -> 入 sync_queue(PENDING) -> 尝试WS push
       WS在线：push -> 等push_ack -> 标记DONE/处理冲突
       离线：保留PENDING，WS重连或定时pull补齐
拉取：hello时带cursor -> 服务端返回since之后的所有变更 -> 客户端按(LWW)合并
广播：服务端收到push成功后向除发送者外的所有在线设备 broadcast
```

## 服务端处理
```
收到push -> 按id查现有记录 -> 若不存在：插入 version=1
         -> 若存在：比较 incoming vs existing 按LWW
            胜出：更新并 version+1，广播
            落败：返回现有记录，标记 conflict=lww_rejected，不广播
```

## 迁移预留
- 服务端所有 DB 访问通过 `Store` 接口隔离，未来替换为 Durable Objects 存储。
- WebSocket 广播通过 `Broadcaster` 接口隔离，未来替换为 DO 的 hibernatable WS。
- 协议消息为纯JSON，不依赖Node特定首部。
