# 测试交接：整理期间发现的既有失败（2026-10-19）

后续处理记录见 [2026-10-19_preexisting_test_failures_resolution.md](2026-10-19_preexisting_test_failures_resolution.md)。大招角度编排经用户确认暂时跳过，原断言保留。

代码整理 P1–P5 期间，下面这些测试一直失败。每一个都在整理**之前**的提交上用同样的方式失败过（逐条对比过失败信息），所以不是整理造成的，但需要有人修。

运行：`run-tests.ps1 -Test <名称>`（按文件名找，不用管文件夹）。测试按领域放在 `tests/<领域>/`，新写的测试继承 `tests/support/harness.gd`（见 `homeing-star-doc/docs/testing.md`）。

## 失败清单

| 测试 | 位置 | 现象 |
|---|---|---|
| `test_chapter_1_boss_rooms` | `tests/levels/chapter_1/` | 「E starts transition from ReturnGate」失败（共 2 项） |
| `test_tutorial_battle_space` | `tests/levels/tutorial/` | 找不到节点 `TrainingDummy`（相对 `/root/TutorialBattleRoom`）；「attack_1 does not drive body and FX from the same complete timeline」 |
| `test_salt_field_prototype` | `tests/levels/chapter_2_salt/` | 「L input starts the horizontal dodge through viewport input」（76 项中 1 项） |
| `test_navigation_hall_entry` | `tests/levels/town/` | 超时（120 秒） |
| `test_mist_portals` | `tests/levels/chapter_1/` | 「Current double-jump route failed step 1 at (621.0, 555.0)」 |
| `test_town_travel` | `tests/levels/town/` | 「Teleport preserves BGM and playback」（19 项中 1 项） |
| `test_mist_ambushers` | `tests/levels/chapter_1/` | 「Locked K suppressed ordinary damage」 |
| `test_combat_parry_flow` | `tests/combat/` | 「Parry startup + active duration is not 350ms」 |
| `test_deer_boss` | `tests/bosses/deer/` | 58 项中 6 项：Hoof deals 12 once on its landing frames / A single hoof segment cannot deal repeated contact damage / K cannot parry a gold charge / Follow-up uppercut turns toward the target and launches for 22 damage / Real J input and player attack effects can hit the deer hurtbox / Real Q input uses the contextual snare without equipping it |
| `test_deer_story`、`test_deer_intro_comic` | `tests/story/`、`tests/story/comics/` | 实跑超时；`-CheckOnly` 报游戏脚本 `scripts/story/deer_story.gd:66` 循环引用（`deer_intro_scene`） |
| `test_wall_slide_contact` | `tests/player/lan/` | `check_entrance_wall_animation` 第 86 行对 null 调 `get_node` |
| `test_lan_migration_contract` | `tests/player/lan/` | 「Back dodge windows are not owned by timeline events」 |
| `test_vine_remake`、`test_vine_region` | `tests/levels/chapter_1/` | 超时（120 秒） |
| `test_lan_ultimate` | `tests/player/lan/` | 「A visible ultimate slash missed the tutorial boss's real hurtbox」；它在第一个失败点就停止，后面的终极技能检查从来没有跑到 |
| `test_deer_red_curtain` | `tests/bosses/deer/` | 61 项中 2 项：production starts the real curtain sequence / production real transformation completes（测试第 68 行取到空数组，藤幕没有启动） |
| `test_deer_god_come_production` | `tests/bosses/deer/` | 超时；未超时前失败：fourth-phase flight camera remains 0.8 / AI chooses full ultimate once at half health / transformation reaches human hover / real sequence reaches new finale |
| `test_deer_action_segments` | `tests/bosses/deer/` | 「Other BOSS development controls remain independent」 |
| `test_twin_fish_arrival` | `tests/bosses/twin_fish/` | 「switching never accumulates shared player combat callbacks」「third picker option selects real TwinFishBoss」 |
| `test_deer_mist_hunt_preview` | `tests/bosses/deer/` | 「Master preview hides unsupported deer ultimate controls」 |
| `test_sideview_layers` | `tests/levels/town/` | 失败（日志无 FAIL 行，看 errors.log） |
| `test_yupo_story` | `tests/story/` | 「Gossip does not grant stele completion」 |
| `test_player_palette_actions` | `tests/player/lan/` | 「Ground combo did not finish with attack 3x」。很可能是测试过时：用户已确认 attack_3x 不在连段里 |

## 修的原则

- 每一个先判断：是**游戏有 bug**，还是**测试过时**（游戏行为已按用户要求改过，测试没跟上）。拿不准的，问用户，不要猜。
- 测试过时：按 `homeing-star-doc/AGENTS.md` 和设计文档里用户确认过的行为改测试，不要为了变绿而删检查或放宽阈值。
- 游戏有 bug：只修 bug 本身；不改手感、数值、时机，除非用户确认。
- 超时的先查卡在哪（日志在 `artifacts/<时间戳>/`），是测试等待条件写错，还是游戏卡住。
- 只写自己新增代码的测试；修旧测试时可以顺手改成继承 `tests/support/harness.gd`。
- 遵守 `homeing-star-doc/AGENTS.md`；改动场景路径要加进 `scripts/autoload/save_path_migration.gd`；挪动游戏文件只用 `tools/restructure/move_res_paths.py`。
