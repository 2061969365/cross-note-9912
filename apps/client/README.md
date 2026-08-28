# Client — Flutter (Android / Web / Windows 共用)

- 状态：Riverpod + go_router + Material 3
- 本地库：drift + drift_flutter (SQLite，零 codegen，WAL)
- 同步：SyncEngine + WebSocket + REST 降级 + sync_queue 离线队列 + LWW 冲突
- 平台隔离：platform/ 抽象接口

启动：`flutter pub get && flutter run -d windows`（或 android / web），设置页可改服务器地址。
