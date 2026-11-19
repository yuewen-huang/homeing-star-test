# Homing Star 测试

游戏、测试、素材和文档分别维护；四个仓库克隆为同一级目录。

- 游戏：`../homeing-star-game`，https://github.com/yuewen-huang/homeing-star-game
- 测试：https://github.com/yuewen-huang/homeing-star-test
- 原稿与临时素材：`../homeing-star-temp-assert`，https://github.com/yuewen-huang/homeing-star-temp-assert
- 设计与规约：`../homeing-star-doc`，https://github.com/yuewen-huang/homeing-star-doc

本仓库没有 project.godot。运行器的 `--path` 指向游戏，`--script` 指向本仓库；测试内 `res://` 始终引用游戏资源。

日常按改动用 `-Test` 运行相关回归。无参数时运行共享动作时钟、命中查询和存档路径迁移三项。需要导入项目时加 `-Prepare`，需要全量时显式加 `-All`。

```powershell
.\run-tests.ps1 -List
.\run-tests.ps1 -Test test_combat_parry_flow,test_no_default_poise
```

日志、截图和测量产物位于被忽略的 `artifacts/`。运行器限制单个进程时间，仅在 `save/progress.cfg` 发生变化时恢复原文件。需要落盘的测试使用 `-Project` 指向隔离游戏副本。

Python 美术工具默认从 `../homeing-star-temp-assert/PendingArt` 和 `Art` 读取原稿、从 `../homeing-star-game/assets` 读取正式资源；支持原有命令行路径覆盖。旧 `tools/game_legacy` 保留作历史工具参考，其中的旧设备绝对路径需使用时调整。

此次迁移只复制当前文件，旧 Gitee 历史保留在原本地目录。版本配对见 `game-baseline.json`。
