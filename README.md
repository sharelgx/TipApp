# Tibo Watch

macOS 菜单栏提醒工具，关注 [Tibo / @thsottiaux](https://x.com/thsottiaux) 的 Codex 额度重置及重置卡消息。头像用于应用和菜单栏图标。本项目为非官方个人工具，与 Tibo 或 OpenAI 没有隶属关系；语音为通用 AI 合成男声，不是本人录音。

## 使用

需要 macOS 13+、Xcode Command Line Tools。

```sh
./scripts/build.sh
open 'dist/Tibo Watch.app'
```

首次启动请允许通知。点菜单栏头像打开面板，点击“测试通知”会发送标有“【测试】”的模拟完成消息并播放中文语音，不代表发生真实重置。

- 每 60 秒读取公开 RSS，支持手动检查、暂停、唤醒后补查。
- 首次成功读取建立历史基线，后续新条目才提醒；去重状态与消息缓存保存在本机。
- 齿轮菜单提供中文播报开关、登录时启动、通知设置、消息源和退出。
- 登录时启动默认关闭；若 macOS 要求批准，请到系统设置中的登录项允许。

## 中文通知与声音

| 类型 | 文字通知 | 声音 |
| --- | --- | --- |
| 计划重置 | 明确“预告将重置，尚未确认完成”，点击核对时间安排 | 普通系统提示声 |
| 已宣布完成 | 明确“Tibo 已宣布完成，请查看账户确认是否到账” | 轻快明亮的中文合成男声 |
| 重置卡消息 | 提醒核实发放及使用方式，不暗示额度已自动重置 | 普通系统提示声 |
| 未分类相关消息 | 明确尚未归类为计划或完成，点击原帖核实 | 普通系统提示声 |

点击通知打开对应 X 原帖。系统通知正文为固定中文摘要，并非逐条机器翻译；原始标题与文本仍保留在面板中。判断依赖 RSS 分类；同时出现 planned/completed 时按计划处理，不播放完成语音。

用户选定的完成播报稿：

> 嗨～！我是 Tibo，告诉你一个好消息：Codex 额度重置已经完成啦！快去看看你的账户吧！

录音已预生成并随应用打包。完成通知由应用通过 macOS 自带 `afplay` 播放，避免依赖这台 Mac 上未能实际发声的自定义通知声音通道。语音使用媒体音量，受静音和当前输出设备影响，专注模式下也可能播放。关闭“中文播报”会停止当前录音；关闭系统通知权限或该应用的通知声音也不播报。多条完成消息同时到达时合并正在播放的相同语音，避免重叠。

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
