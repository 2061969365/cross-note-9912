# CrossNote — 跨平台实时同步便签（本地优先）

三端共用一套 Flutter/Dart 代码：Android / Web / Windows。离线可用，本地 SQLite，WebSocket 实时同步，多设备同时在线，断网自动补同步，基础 LWW 冲突收敛。阶段一本地 Hono+SQLite 模拟云端，阶段二平滑迁移到 Cloudflare Worker + Durable Objects（已做 Store/Broadcaster 抽象隔离）。

## 目录
```
cross_note/
  apps/server/   Node.js + Hono + ws + node:sqlite (http://localhost:8787, ws://localhost:8787/ws)
  apps/client/   Flutter + Riverpod + drift + WebSocket + Markdown
  packages/protocol/sync_protocol.md
  docs/
```

## 快速开始
```bash
# 后端
npm --prefix apps/server install --cache F:\worker\.npm-cache
npm --workspace apps/server run dev

# 客户端（需本机已装 Flutter SDK）
cd apps/client && flutter pub get && flutter run -d windows
```

详见 `docs/development.md` / `docs/architecture.md` / `packages/protocol/sync_protocol.md`
