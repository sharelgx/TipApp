# Tibo Watch

macOS 菜单栏提醒工具，关注 [Tibo / @thsottiaux](https://x.com/thsottiaux) 的 Codex 额度重置及重置卡消息。头像用于应用和菜单栏图标。本项目为非官方个人工具，与 Tibo 或 OpenAI 没有隶属关系；语音为通用 AI 合成男声，不是本人录音。

## 使用

需要 macOS 13+、Xcode Command Line Tools。

```sh
./scripts/build.sh
open 'dist/Tibo Watch.app'
```

首次启动请允许通知。点菜单栏头像打开面板，在“测试提醒”中可分别选择“预计重置（计划）”和“已宣布完成”，测试消息标有“【测试】”，不代表发生真实重置。

- 每 60 秒读取公开 RSS，支持手动检查、暂停、唤醒后补查。
- 首次成功读取建立历史基线，后续新条目才提醒；去重状态与消息缓存保存在本机。
- 齿轮菜单提供中文播报开关、登录时启动、通知设置、消息源和退出。
- 登录时启动默认关闭；若 macOS 要求批准，请到系统设置中的登录项允许。

## 中文通知与声音

| 类型 | 文字通知 | 声音 |
| --- | --- | --- |
| 计划重置 | 明确“预告将重置，尚未确认完成”，显示可解析的预计窗口 | 独立中文预告语音，强调尚未完成 |
| 已宣布完成 | 明确“Tibo 已宣布完成，请查看账户确认是否到账” | 轻快明亮的中文合成男声 |
| 重置卡消息 | 提醒核实发放及使用方式，不暗示额度已自动重置 | 普通系统提示声 |
| 未分类相关消息 | 明确尚未归类为计划或完成，点击原帖核实 | 普通系统提示声 |

每条提醒同时提交系统通知，并显示独立的原生中文文字窗口，保留到手动关闭。窗口在当前鼠标所在屏幕的右上角显示；多条消息按队列逐条查看。点击“查看原帖”打开对应 X 原帖。系统横幅可能被专注、共享屏幕规则等抑制，独立窗口不依赖系统横幅显示，也可能出现在共享画面中。

通知正文为固定中文摘要，并非逐条机器翻译；原始标题与文本仍保留在面板中。判断依赖 RSS 分类；同时出现 planned/completed 时按计划处理，不播放完成语音。

用户选定的完成播报稿：

> 嗨～！我是 Tibo，告诉你一个好消息：Codex 额度重置已经完成啦！快去看看你的账户吧！

录音已预生成并随应用打包。计划与完成通知由应用通过 macOS 自带 `afplay` 播放，避免依赖这台 Mac 上未能实际发声的自定义通知声音通道。语音使用媒体音量，受静音和当前输出设备影响，专注模式下也可能播放。关闭“中文播报”会停止当前录音；关闭系统通知权限或该应用的通知声音也不播报。多条同类型消息同时到达时合并正在播放的相同语音；类型变化会切换到最新消息的语音，避免计划与完成互相混淆。

[试听录音](Assets/audio/reset-confirmed.mp3)

## 来源与边界

使用第三方 [ModelYard 公开 RSS](https://tibo.modelyard.dev/feed.xml)，无需 X API Key，不读取浏览器登录信息。提醒延迟取决于第三方收录时间和下次检查时间，不能保证原帖发出后一分钟内通知。

当前 RSS 只提供最近 20 条事件，离线过久可能漏掉已移出源的消息，新收录的历史补录也可能提醒。超过 24 小时无新条目时提示可能滞后，但也可能只是没有新消息。断网或格式变化会显示错误并保留缓存。休眠或退出期间不监控，唤醒后补查。

“Tibo 已宣布完成”不等于每个账户都已到账。本工具不查询个人额度，不自动领取或消耗重置卡。

日常运行只获取 RSS 和播放本地录音，不调用 Codex、OpenAI API 或语音模型，不消耗 Codex 额度。预生成录音使用本地 Audio8，参考男声生成时调用过 Edge 在线语音服务；开发工具本身的对话使用量另计。

## 重新生成录音（可选）

构建和日常使用不需要下载语音模型。若要重新生成，需要 Python 3.12、FFmpeg，以及另行安装的 Audio8-TTS-Preview-0.1B-ONNX-INT8 运行时。模型不包含在本仓库。

```sh
uv venv --python 3.12 .venv-audio
uv pip install --python .venv-audio/bin/python edge-tts==7.3.1
mkdir -p Work/audio
.venv-audio/bin/edge-tts --voice zh-CN-YunxiNeural --rate '+8%' --pitch '+6Hz' \
  --text '嗨！告诉你一个好消息！今天的任务已经顺利完成啦！快去看看吧，希望你每天都有好心情！' \
  --write-media Work/audio/bright-reference.mp3
ffmpeg -y -i Work/audio/bright-reference.mp3 -ar 44100 -ac 1 Work/audio/bright-reference.wav
```

在已安装 Audio8 所需依赖的 Python 环境中运行：

```sh
export AUDIO8_RUNTIME=/path/to/onnx_runtime_0_1b_int8
python scripts/generate-alert.py
./scripts/prepare-audio.sh
./scripts/build.sh
```

参考音色缓存只在本项目 `Work/` 内创建，不修改其他项目的声音配置。实际参数与时长见 [metadata.json](Assets/audio/metadata.json)。

## 验证与数据

```sh
'dist/Tibo Watch.app/Contents/MacOS/TiboWatch' --check-notification-copy
curl -fL --max-time 25 https://tibo.modelyard.dev/feed.xml -o /tmp/tibo-feed.xml
'dist/Tibo Watch.app/Contents/MacOS/TiboWatch' --check-feed /tmp/tibo-feed.xml
codesign --verify --deep --strict 'dist/Tibo Watch.app'
```

此前旧版语音在应用发送通知后直接播放的路径，已由用户实际确认能听到。新版录音的验证结果见 [音频说明](Assets/audio/README.md)；系统 delivered 或播放进程成功不替代实际听觉验收。

本地数据：`~/Library/Application Support/TiboWatch/posts.json` 保存公开消息缓存，`notification-test.json` 保存最近一次测试结果；UserDefaults 保存偏好、首次基线和去重状态。这些本地状态不提交到仓库。

构建产物为本机 ad-hoc 签名，未经 Apple 公证。跨机器运行可能受到 Gatekeeper 限制；仓库提供源码和预生成音频，不上传模型、虚拟环境或本机缓存。


### 文字提醒实际验收（2026-10-20）

系统报告 delivered 时，用户仍未看到文字横幅；将本应用提醒样式改为持续后仍未看到，因此不能把 delivered 当作可见性证明。当前保留系统通知，同时新增原生 NSPanel 文字提醒，不自动消失，支持关闭、查看原帖和多条队列。

本轮读取实际窗口的可访问性文本并查看截图，确认“【测试】Tibo · 已宣布完成”、模拟消息说明、中文正文与两个按钮均可见；用户实际反馈“看到了”。最新测试诊断也包含 textWindowVisible 字段。全局共享屏幕通知规则未修改。


### 预计重置提醒（2026-10-20）

先前计划消息已有新条目文字通知，但仅用系统提示声，没有独立中文语音、预计窗口展示或单独测试入口。现补齐计划专用录音 `reset-planned.caf`，沿用用户已认可的轻快男声，文案明确“预计要重置”“目前还没有确认完成”。用户已实际确认计划测试“文字和语音都正常”。

只依据原帖预告，不预测下一次重置。对于原帖“within the next N hours”（1–48 整数小时），以帖子发布时间计算预计窗口上界，显示北京时间；窗口不保证一定兑现。原帖只说 EOD / end of day 时保留“发布当天结束前”和原文 PST 标注，不擅自换成精确时刻或推定夏令时；其他表述提示查看原帖。历史条目首次只建立基线，不重复推送，不把旧预告当作新计划。

生成计划录音：`python scripts/generate-alert.py --kind planned`，再执行 `./scripts/prepare-audio.sh planned`。命令行 `--test-planned-notification` 触发“预计两小时内”的模拟消息，窗口明确标注测试，不代表真实预告。时间转换、模糊时区、冲突分类检查均包含于 `--check-notification-copy`。

### 预计北京时间语音（2026-10-20）

计划提醒的语音现在也读出预计北京时间，不再只说“请看文字提醒”。文字与语音共享 `estimatedResetDate`：语音包含月、日、24 小时制的时、分以及“之前，这是预估窗口，目前还没有确认完成”。对于无法精确换算的 EOD 或未知时间，不猜钟点，而播报“目前无法确定具体北京时间，请查看文字提醒”。

时间语音使用已认可的 Audio8 轻快男声预生成 0–59 和时间短语，共 69 段，存于 `Assets/audio/timebank.json`。应用在本地拼装 PCM WAV，经 afplay 播放；播放结束删除临时文件。日常仍不运行模型、不访问语音服务或消耗 Codex 额度。

重新生成时间库：在 Audio8 环境设置 `AUDIO8_RUNTIME` 后执行 `python scripts/generate-timebank.py`。该脚本复用本项目已注册的男声音色，使用缓存参考前缀与 3 个并行推理任务；无需重新生成已验收的完成录音。

验证：全部 69 段 PCM 的采样率、非空、非静音和字节对齐通过。`--check-notification-copy` 覆盖北京时间文本/语音片段一致性及模糊时区不猜时刻。`--check-time-speech /tmp/time-check.wav` 生成确定的“10月20日 07:45”样例，本地 Whisper 转写正确识别“预计北京时间10月20日7点45分之前”，详见 `Assets/audio/transcript-timebank.json`。
