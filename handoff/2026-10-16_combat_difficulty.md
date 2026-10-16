# 测试交接：战斗难度三档（2026-10-16）

设计：`homeing-star-doc/docs/design/combat_difficulty_v0_1.md`。第一轮已提交（游戏 `636cb8b`、测试 `f1e3b46`）；第二轮（删除接触提示代码、迁移旧测试）尚未提交，见下方"第二轮"。

## 改了什么

- 取消接触格反提示：三档都不弹提示。第二轮已把提示代码整体删除。
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
| 第二轮：`-Prepare` 导入 | 通过，无报错 |
| 第二轮：`test_combat_difficulty`（47 项，删掉了 3 项提示检查） | 通过 |
| 第二轮：所有改过的游戏脚本和测试脚本做一次解析检查（单次 Godot 启动，只加载不运行） | 全部能解析 |

第二轮迁移过的测试本机**都没有运行**，只确认了能解析。请在高性能电脑上重点跑上表"需要留意"的几个。

本机还在改动版上跑过一次不完整的 `-All`（按字母序跑到 `test_vine_region` 为止，53 个通过）。当时同时在跑原版基线，两边抢 CPU，超时结果不可信。

## 请在高性能电脑上做

1. 先用 `run-tests.ps1 -Prepare -Test test_combat_difficulty` 导入（新增了两个 `class_name`），确认它通过。
2. 在**改动前的提交**（`homeing-star-game` 当前 HEAD `c584040`，暂存改动后检出）上跑一次 `-All` 作为基线，再在改动版上跑一次 `-All`，对比两份结果。

## 第二轮：删除接触提示代码，迁移旧测试（未提交）

游戏仓库删除了 `ContactParryQTE`（`scripts/core/contact_parry_qte.gd`）和 `ParryQTE` 自动加载，以及所有来源里的提示分支：`BossBase`、`CombatHitbox2D`（连同 `resolve_assisted_parry()`）、鹿群、藤刺、藤敌、雾中伏击者（删掉 `State.QTE`、`qte_panel`、`resolve_qte_success()` 等）、雾中格反敌、区域核心危害、风阶段大招、教学师父（`contact_parry_*`、`assisted_segments`、`parry_assist_prompt`、`get_parry_binding_label()` 等）、开发房间适配器、各 NPC / 剧情触发里的 `ParryQTE.active` 判断；兰的 `contact_qte_paused`、`set_contact_qte_paused()`、`resolve_assisted_parry()`、`suppress_parry_until_released`；`BattleAssistSettingsService.uses_contact_parry_prompt()`。三档下提示早已不出现，游戏行为应不变。

`run-tests.ps1 -Prepare` 必须先跑一次：删掉了 `class_name ContactParryQTE`，全局类缓存要刷新。

### 改过的测试

迁移方法：`set_level(Level.NONE)` → `set_difficulty(Difficulty.HARD)`；只验证提示框的断言删除；`set_contact_prompt_enabled(...)` 删除。

| 测试 | 改动 | 需要留意 |
|---|---|---|
| `test_contact_parry_qte` | 整个删除 | |
| `test_combat_difficulty` | 删掉"三档都不用提示"的循环检查 | 本机已跑，见下 |
| `test_core_essence_ultimates`、`test_deer_production_phases`、`test_deer_red_curtain`、`test_deer_vine_camera`、`test_deer_boss` 开头 | 只做 `Level.NONE` → `HARD` | |
| `test_deer_boss` | 删掉蹄击提示的成功 / 取消 / 错键三段；重试检查不再看提示 | |
| `test_deer_four_phase_production` | 删掉藤刺提示段；金色横扫只检查不能被格断；"重试清空"改用一根刚生成、尚未接触的藤（不再借提示挂起） | 重试那段的夹具是新写的 |
| `test_deer_wind_clash_feel` | 删掉旧的 F11 提示开关检查（`test_combat_difficulty` 已覆盖 F11） | |
| `test_frogger_boss` | 删掉青蛙提示段；`prior_level` → `prior_difficulty` | |
| `test_mist_ambushers` | 删掉提示成功 / 超时 / 翻滚、按键关闭提示、奔跑中冻结、两只重叠抢提示四段；锁定 K 段只保留"锁定时照常受伤、剧情解锁 K"；截图样本去掉 `*_qte`；整房伏击改为兰先开格反窗口、野猪真实撞上后被格反并计数；结尾恢复为普通档 | 整房那段改成真实物理帧碰撞，是新写的 |
| `test_mist_parry_remake` | 原先靠提示框按 K 计数，改为兰先开格反窗口（`start_parry(true)`），等 3 个物理帧让真实碰撞结算；删掉"两只重叠共享一个提示"段 | 计数和击败流程全部依赖新写法，最需要确认 |
| `test_regional_core_encounters`（及继承它的 `test_regional_core_bosses`） | 删掉区域 0 的环提示段；开头设困难档，结尾恢复原难度 | |
| `test_tutorial_battle_space` | 删掉第一轮遗留的辅助减速检查（`get_red_slowdown`、`assist_slow_remaining`）和整段师父接触提示检查（约 100 行） | |
| `test_vine_combat_stele` | 提示成功段改为第二次手动格反破韧（逐帧推进到破韧为止再接 2.1 秒恢复）；提示失败段改为不格反、刺中扣 8 血；难度保存 / 恢复改用 `difficulty` | 破韧后的恢复计时可能和原来差几帧，"poise == 30"那项要看 |
| `test_combat_parry_flow` | 翻滚落地 / 普通落地的辅助格反改用 `resolve_chain_parry()`（同样会打断当前动作）；删掉"提示键漏进普通输入""松开 K 解除抑制"两项 | 这两项原本在基线里就失败 |
| `test_boss_development_room`、`test_deer_god_come`、`test_deer_ground_lash_screen`、`test_deer_mist_hunt_preview`、`test_player_invincibility`、`test_twin_fish_arrival` | 删掉 `ParryQTE.active` / `can_offer` 断言，只改提示文字 | |
| `test_deer_charge`、`test_lan_migration_contract` | 只改断言说明里的 "QTE" 字样 | |
| `tools/preview_deer_mist.gd`、`tools/record_deer_wind_parry.gd` | `Level.NONE` → `HARD`；录像脚本注释改为困难档 | |

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
