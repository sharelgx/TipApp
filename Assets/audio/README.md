# 中文完成提示音

文案由用户确认：

> 嗨～！我是 Tibo，告诉你一个好消息：Codex 额度重置已经完成啦！快去看看你的账户吧！

录音为通用 AI 合成男声，不是 Tibo 本人的录音或声音模仿。最终音频由本地 Audio8-TTS-Preview-0.1B-ONNX-INT8 生成，与 AI 会计课程使用同一模型；本项目单独创建音色，不修改其他项目的女声设置。

为获得轻快明亮的语气，参考由 Microsoft Edge TTS 的 zh-CN-YunxiNeural 合成，rate +8%、pitch +6Hz，使用通用愉快提示语。Audio8 使用该参考合成用户选定的文案，分句后短停顿拼接。发布音频额外以 1.04 倍速、轻微高频均衡与响度归一化处理，避免大幅升调。

- `reset-confirmed.wav`：Audio8 原始输出，6.433 秒。
- `reset-confirmed.caf`：应用实际播放文件，6.164 秒，44.1 kHz 单声道 PCM 16 位。
- `reset-confirmed.mp3`：与 CAF 内容对应的试听版。
- `metadata.json`：模型、参考、文案与原始波形指标。
- `transcript-check.json`：本地 Whisper 对试听版的自动转写。内容匹配；“啦”被识别为“了”，不是精确逐字听审。

原始波形有限、非静音，峰值约 0.634，无生成 token 截断。CAF/MP3 已完成完整解码检查。主应用使用 afplay 播放本地 CAF，不依赖自定义通知声音，不在日常运行中调用语音模型或云 API。音色轻快程度仍以用户实际试听为准。

脚本见 `scripts/generate-alert.py` 与 `scripts/prepare-audio.sh`。参考文件和注册音色缓存在忽略提交的 `Work/audio/`；模型与虚拟环境不上传仓库。
