# Development

## 启动本地后端
```bash
cd F:\worker\cross_note
npm --prefix apps/server install --cache F:\worker\.npm-cache
npm --workspace apps/server run dev
# http://localhost:8787  ws://localhost:8787/ws  db=apps/server/data/cross_note.db
```
健康检查：`GET http://localhost:8787/api/health`

## Flutter 客户端
```bash
cd F:\worker\cross_note\apps\client
flutter pub get
flutter run -d windows    # 或 android / web / edge
# 首次运行会自动生成 device_id (android-xxx / windows-xxx / web-xxx) 并持久化
```
设置页可修改服务器地址（默认 http://localhost:8787），需与后端一致。

## 调试同步
- 客户端设置页可见：device_id / 最后同步游标 / 待同步队列数
- 断网后编辑 -> 联网自动补同步（WS重连 + 15s轮询兜底）
- 多设备：同一局域网用 `http://<局域网IP>:8787` 作为 server_url

## 迁移到 Cloudflare（阶段二）
1. 将 `apps/server/src/sync/store.ts` 替换为 DO storage 适配
2. 将 `src/websocket/handler.ts` 替换为 DO hibernatable WS
3. 协议与客户端零改动，仅改部署目标
