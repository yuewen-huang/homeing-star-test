# 项目内音效总目录

打开 [试听页面](index.html)，或查看 [CSV 完整清单](catalog.csv) / [JSON 清单](catalog.json)。仅收录项目内文件，外部素材库不参与预览或服务路由。

共 64 个 WAV，另列正式资源中的 MP3；正式 WAV 62 个，外部素材库 WAV 0 个。

“有引用”仅表示在正式脚本、场景或文本资源中发现直接资源路径，不等于每个游戏分支都会播放；“未检出”也不能排除动态加载。已加工的手动动作源轨通过既有 SOURCES.md 映射到九个 Godot .res 资源，试听的是原始 WAV。

试听默认将已测量的正式 WAV 对齐到基础响度（不含游戏中的前景/背景层级）；可切换原始音量，未测量的音频保持原始音量。

原始文件保持原位。用途分类取自现有文件夹，不代表音质或适用性已经试听确认。相同 SHA-256 的文件标记为重复副本，未删除。

本机双击 index.html 可以直接试听。若浏览器限制本地文件，运行 tools/build_audio_catalog.py --serve，再打开 http://127.0.0.1:8774/。服务只读取清单内音频，且仅监听本机。

| 来源分组 | 数量 |
| --- | ---: |
| chapter_1 | 5 |
| chapter_2 | 1 |
| combat | 3 |
| crystal_crab | 6 |
| audio | 3 |
| lan_voice | 3 |
| mist | 1 |
| beast | 4 |
| deer | 6 |
| land | 4 |
| layer | 2 |
| move | 6 |
| ring | 8 |
| steps | 5 |
| swing | 10 |
| warn | 3 |
| wind | 1 |
| sfx | 1 |
| tutorial_battle | 2 |
| ui | 1 |
| homeing-star-temp-assert | 1 |
| homeing-star-test | 1 |
