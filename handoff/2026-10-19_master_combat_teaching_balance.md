# 师傅教学与战斗数值精调

设计和完整数值表：`homeing-star-doc/docs/design/master_combat_teaching_balance_20261019.md`。

## 已验证

使用 `D:\Godot\Godot_v4.7.2-stable_win64_console.exe`，通过 `run-tests.ps1` 执行，脚本自动备份和恢复玩家存档。

| 测试 | 结果 | 日志目录（artifacts/ 下） |
|---|---|---|
| test_master_combat_teaching | 37 项通过；含真实 O 24 段命中师傅合计 96 伤害、存档字节不变 | 20261019-210244-352 |
| test_tutorial_battle_space | 通过 | 20261019-205937-221 |
| test_master_clash_rhythm | 通过 | 20261019-205937-221 |
| test_lan_special_attack_feel | 44 项通过；更新蓄力削韧期望 | 20261019-210105-749 |
| test_combat_difficulty | 通过 | 20261019-210105-749 |
| test_master_development_phases | 通过，日志报告 0 failures | 20261019-210105-749 |
| test_master_sendoff | 通过（独立重跑） | 20261019-210308-876 |

`20261019-210244-352/teaching_{opening,red,gold,break}.png` 已逐张查看：底部教学文字与师傅头顶气泡均可读，无 HUD 遮挡。金刀与红刀截图展示对应教学文案，并非动作生效帧；动作判定由既有六套拼刀测试覆盖。

## 尚存的独立失败

`test_lan_ultimate` 的轨迹多样性检查要求至少四种 15 度角度类别，实际三种。当前伤害 4 的日志：`20261019-205937-221`；临时复制相同测试并将 `ultimate_hit_context.damage` 还原为 1 后仍完全相同地失败：`20261019-210216-345`。临时测试文件已移除。此轮只调整 O 伤害，未更改轨迹或角度门槛，也没有将该测试算作通过。

引擎日志中的 user:// 日志权限、证书存储报错仍存在；新增脚本没有解析/运行脚本错误。战后测试一次启动受到环境中断，已单独重跑通过。未修改用户原有的 `project.godot` 与 `save/progress.cfg` 改动。
