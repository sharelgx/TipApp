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

2026-10-20 验收：更新后的应用发送中文模拟完成通知，系统返回 submitted=true、delivered=true、playbackStarted=true，用户实际反馈“听到了，这版合适”。本次轻快明亮版本已通过用户试听。


## 计划预告专用录音

`reset-planned.wav/.caf/.mp3` 使用同一 Audio8 模型和 male_bright_synthetic_v2 音色生成，不改已认可的完成录音。文案：“嗨～！我是 Tibo，提前告诉你：Codex 预计要重置啦！具体时间请看文字提醒，目前还没有确认完成哦！”生成参数见 metadata-planned.json，转写见 transcript-planned.json。原始时长 8.288 秒、有限非静音波形且未达 token 截断上限；发布版完成完整解码检查。本地 Whisper 转写明确包含“预计要重置”和“目前还没有确认完成”。

2026-10-20 实际验收：预计两小时内的模拟通知窗口展示北京时间窗口上界、计划状态与测试标记；用户确认“文字和语音都正常”。真实消息只依据新收录的原帖预告，不自行预测。
