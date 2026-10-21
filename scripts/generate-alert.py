"""Create a local Audio8 reset alert from a generic synthetic male reference."""
from pathlib import Path
import sys, json, os, argparse
import numpy as np
import soundfile as sf
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--kind',choices=['confirmed','planned','prediction'],default='confirmed')
args=parser.parse_args()
segments=['嗨','我是Tibo','提前告诉你','Codex预计要重置啦','具体时间请看文字提醒','目前还没有确认完成哦'] if args.kind=='planned' else ['嗨','我是Tibo','告诉你一个好消息','Codex额度重置已经完成啦','快去看看你的账户吧']
spoken_text='嗨～！我是 Tibo，提前告诉你：Codex 预计要重置啦！具体时间请看文字提醒，目前还没有确认完成哦！' if args.kind=='planned' else '嗨～！我是 Tibo，告诉你一个好消息：Codex 额度重置已经完成啦！快去看看你的账户吧！'
if args.kind=='prediction':
    segments=['嗨','发现Tibo的新线索','可能与重置有关','这只是一个猜测，并不确定','目前不知道具体时间','请看文字分析']
    spoken_text='嗨！发现 Tibo 的新线索，可能与重置有关。这只是一个猜测，并不确定，目前不知道具体时间，请看文字分析。'
asset='reset-'+args.kind
BASE=Path(os.environ['AUDIO8_RUNTIME']).expanduser().resolve()
sys.path.insert(0,str(BASE))
from arktts_runtime.registration import VoiceRegistration
from arktts_runtime.runtime import ArkTtsRuntime
WORK=ROOT/'Work/audio'
VOICE=WORK/'voices'
TEXT='嗨！告诉你一个好消息！今天的任务已经顺利完成啦！快去看看吧，希望你每天都有好心情！'
voice_name='male_bright_synthetic_v2'
if not (VOICE/voice_name/'meta.json').exists():
    registration=VoiceRegistration(BASE/'model/registration',VOICE,'audio8-tts-preview-0.1b-int8-v1')
    registration.register((WORK/'bright-reference.wav').read_bytes(),'bright-reference.wav',TEXT,voice_name)
print('Voice registered',flush=True)
runtime=ArkTtsRuntime(BASE/'model',VOICE,'int8','fp16',2)
parts=[]
for text in segments:
    budget=360
    for attempt in range(3):
        audio,codes=runtime.synthesize(text=text,voice=voice_name,max_new_tokens=budget,temperature=.7,top_p=.9,top_k=50,seed=42+attempt)
        audio=np.asarray(audio,dtype=np.float32).reshape(-1)
        if len(audio) and np.isfinite(audio).all() and np.max(np.abs(audio))>.002 and codes.shape[1]<budget:
            break
    else: raise RuntimeError('Invalid or truncated audio: '+text)
    active=np.flatnonzero(np.abs(audio)>.002)
    audio=audio[max(0,active[0]-4410):min(len(audio),active[-1]+4410)]
    fade=min(441,len(audio)//2)
    audio[:fade]*=np.linspace(0,1,fade)
    audio[-fade:]*=np.linspace(1,0,fade)
    parts += [audio,np.zeros(6500,dtype=np.float32)]
    print('Rendered '+text,flush=True)
audio=np.concatenate(parts)
sf.write(ROOT/('Assets/audio/'+asset+'.wav'),audio,44100,subtype='PCM_16')
metadata=dict(model='Audio8-TTS-Preview-0.1B-ONNX-INT8',voice=voice_name,reference='Microsoft zh-CN-YunxiNeural generic synthetic male; rate +8%, pitch +6Hz; generated for this project',text=spoken_text,seconds=len(audio)/44100,peak=float(np.max(np.abs(audio))),rms=float(np.sqrt(np.mean(audio**2))),temperature=.7,top_p=.9,top_k=50,seed=42)
(ROOT/('Assets/audio/'+('metadata.json' if args.kind=='confirmed' else 'metadata-'+args.kind+'.json'))).write_text(json.dumps(metadata,ensure_ascii=False,indent=2))
print(json.dumps(metadata,ensure_ascii=False),flush=True)
