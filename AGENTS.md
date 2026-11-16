# 《归航星》项目入口

开始任务时读取 `../homeing-star-doc/AGENTS.md`，按其中路由只加载实际命中的规范。
已在本会话读取且未变化的规则不重复加载；不要全文读取历史归档。

- 本仓库承载测试、诊断、导入和离线生成工具；测试不得写入真实玩家存档。测试入口为 `run-tests.ps1`，默认引用 `../homeing-star-game/`。
- 四个同级仓库：`homeing-star-game`、`homeing-star-doc`、`homeing-star-test`、`homeing-star-temp-assert`。
- 设计与当前交接在文档仓库；原稿/待定素材在素材仓库；测试与工具在测试仓库。
- `docs/standards/` 是文档仓库中的路径，不是本仓库路径。
- 相邻文档仓库暂不可读时，不用旧归档代替现行规范；只处理已有明确依据的部分，并指出缺少的具体文件。
