# 测试交接：战斗难度三档（2026-10-16）

设计：`homeing-star-doc/docs/design/combat_difficulty_v0_1.md`。改动尚未提交（游戏、测试、文档三个仓库都是未提交状态）。

## 改了什么

- 取消接触格反提示：三档都不弹提示（`uses_contact_parry_prompt()` 恒为否，提示代码本身留到第二轮再删）。
- `BattleAssistSettingsService`：删除旧的 `Level` / `set_level()` / `contact_prompt_enabled` / `set_contact_prompt_enabled()` / 红刀减速 `get_red_slowdown()`、`get_normal_slowdown()`；新增 `Difficulty`（NORMAL 默认 / HARD / NIGHTMARE）、`set_difficulty()`、`uses_parry_chain_assist()`、`shows_attack_telegraphs()`，F11 改为循环切换难度。
- 教学师父：删除辅助减速（`assist_slow_remaining`、`_update_assist_slowdown` 等）。
- 兰：普通档连招自动格反（`ParryChainAssist`、`resolve_chain_parry()`）、蓝光（`ParryCueVisual`）、`combat_clock`。
- 鹿风阶段：每套连招一个 `combo_serial`，`get_parry_chain_key()`、`next_parry_contact_in()`。
- `AttackTelegraph`：噩梦档不画标记。

**默认难度是普通**：手动格反成功后，同一来源 1 秒内的下一刀会被自动格反。依赖"格反后下一刀命中 / 半伤"的旧测试需要先 `set_difficulty(BattleAssistSettingsService.Difficulty.HARD)`。

## 本机已跑

| 测试 | 结果 |
|---|---|
| `test_combat_difficulty`（新增，50 项） | 通过 |

本机还在改动版上跑过一次不完整的 `-All`（按字母序跑到 `test_vine_region` 为止，53 个通过）。当时同时在跑原版基线，两边抢 CPU，超时结果不可信。

## 请在高性能电脑上做

1. 先用 `run-tests.ps1 -Prepare -Test test_combat_difficulty` 导入（新增了两个 `class_name`），确认它通过。
2. 在**改动前的提交**（`homeing-star-game` 当前 HEAD `c584040`，暂存改动后检出）上跑一次 `-All` 作为基线，再在改动版上跑一次 `-All`，对比两份结果。

## 预期失败：引用了已删除的接口或接触提示（第二轮重写或删除）

这些测试调用了 `set_level` / `Level.*` / `contact_prompt_enabled` / 红刀减速，或断言提示框会出现。调用已删除方法的文件会直接解析失败。

- 引用旧辅助接口：`test_contact_parry_qte`、`test_core_essence_ultimates`、`test_deer_boss`、`test_deer_four_phase_production`、`test_deer_production_phases`、`test_deer_red_curtain`、`test_deer_vine_camera`、`test_deer_wind_clash_feel`、`test_frogger_boss`、`test_mist_ambushers`、`test_mist_parry_remake`、`test_regional_core_encounters`、`test_tutorial_battle_space`、`test_vine_combat_stele`
- 断言提示框行为：`test_boss_development_room`、`test_deer_god_come`、`test_deer_ground_lash_screen`、`test_deer_mist_hunt_preview`、`test_player_invincibility`、`test_twin_fish_arrival`
- 连带：`test_regional_core_bosses` 继承自 `test_regional_core_encounters`，跟着解析失败。
- 非测试工具同样引用旧接口：`tools/preview_deer_mist.gd`、`tools/record_deer_wind_parry.gd`。

迁移方法：`set_level(Level.NONE)` → `set_difficulty(Difficulty.HARD)`；只验证提示框的断言删除；`set_contact_prompt_enabled(...)` 调用直接删除（提示已不存在）。

## 原版基线里也失败（本机不完整的基线）

`test_town_travel`、`test_ali_story`、`test_attack_telegraph`、`test_chapter_1_boss_rooms`、`test_child_kite_flow`、`test_combat_parry_flow`、`test_contact_parry_qte`、`test_core_essence_ultimates`、`test_rune_lock_integration`（超时）、`test_playtest_fixes`（超时）。基线在 `test_deer_light_stomp` 之后因抢 CPU 大量超时，已停止。

## 改动版失败、原因待查（需要和基线对比）

| 测试 | 本机失败项 | 初步判断 |
|---|---|---|
| `test_parry_effect_placement` | Blocked-hit spark lands on the blade | 多半是默认普通档：前一下手动格反后，半伤格挡被自动格反取代。加 `set_difficulty(HARD)` 应可恢复 |
| `test_deer_clash_phase` | Wind exposes independent pressure, flick and complete combo without item controls | 开发房间菜单相关，未确认是否和本次有关 |
| `test_deer_phase_combos` | Development picker exposes the four phase mappings plus the vine duel | 同上 |
| `test_deer_root_death_cleanup` | 根击致死追踪三项 | 未确认 |
| `test_deer_story` | 根阶段诱饵两项 | 未确认 |
| `test_eating_guests`、`test_forest_signposts`、`test_sideview_layers` | 任务面板 / 路牌数量 / 战斗房角色 | 看起来与战斗无关，可能原本就失败 |
| `test_lan_migration_contract`、`test_lan_ultimate`、`test_mist_portals`、`test_player_palette_actions` | 日志里没有 FAIL 行，可能是退出码或报错 | 需查看 errors.log |
| `test_deer_god_come_production`、`test_navigation_hall_entry`、`test_vine_region` | 超时 | 抢 CPU 时的超时，单独重跑确认 |

字母序 `test_vine_region` 之后的测试本机没有跑到。

## 视觉检查

`tools/capture_parry_cue.gd`（非无头运行，参数为输出目录）截取鹿风阶段前刺时兰刀上的蓝光：出现、收拢、闪亮、全景。本机已检查过，蓝环在兰朝向鹿一侧的刀上，清晰可读。
