"""Pre-generate the accepted Audio8 voice for offline, dynamic Beijing-time speech."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import sys, os, json, base64
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ['AUDIO8_RUNTIME']).expanduser().resolve()
sys.path.insert(0,str(BASE))
from arktts_runtime.runtime import ArkTtsRuntime

class CachedVoiceRuntime(ArkTtsRuntime):
    def cache_voice(self,voice):
        codes,meta=self.voices.load(voice)
        a=self.prompt_builder.build('甲',meta['reference_text'],codes)
        b=self.prompt_builder.build('乙',meta['reference_text'],codes)
        end=int(np.flatnonzero(~np.all(a==b,axis=(0,1)))[0])
        state=self._empty_slow_state()
        for pos in range(end):
            logits,hidden=super()._slow_step(a[:,:,pos:pos+1],pos,state)
        self.cached_prefix=a[:,:,:end].copy()
        self.cached_state={key:value.copy() for key,value in state.items()}
        self.cached_output=(logits,hidden)
    def _slow_step(self,column,position,state):
        if hasattr(self,'cached_prefix') and position<self.cached_prefix.shape[2]:
            if not np.array_equal(column,self.cached_prefix[:,:,position:position+1]): raise RuntimeError('Reference prefix changed')
            if position==self.cached_prefix.shape[2]-1:
                for key,value in self.cached_state.items(): np.copyto(state[key],value)
            return self.cached_output
        return super()._slow_step(column,position,state)

VOICE='male_bright_synthetic_v2'
runtime=CachedVoiceRuntime(BASE/'model',ROOT/'Work/audio/voices','int8','fp16',2)
runtime.cache_voice(VOICE)
print('Voice prefix cached',flush=True)
DIGITS='零一二三四五六七八九'
def chinese(n):
    if n<10:return DIGITS[n]
    return ('' if n<20 else DIGITS[n//10])+'十'+(DIGITS[n%10] if n%10 else '')
texts={str(n):chinese(n) for n in range(60)}
texts.update(intro='嗨，我是Tibo，提前告诉你，Codex预计要重置啦',
             beijing='预计北京时间',month='月',day='日',hour='点',minute='分',
             before='之前，这是预估窗口',end='目前还没有确认完成哦',
             unknown='目前无法确定具体北京时间，请查看文字提醒')
CACHE=ROOT/'Work/audio/timebank';CACHE.mkdir(parents=True,exist_ok=True)
def generate(item):
    key,text=item
    path=CACHE/(key+'.pcm')
    if path.exists():return key,path.read_bytes()
    budget=max(200,len(text)*14)
    for attempt in range(3):
        audio,codes=runtime.synthesize(text=text,voice=VOICE,max_new_tokens=budget,temperature=.7,top_p=.9,top_k=50,seed=42+attempt)
        audio=np.asarray(audio,dtype=np.float32).reshape(-1)
        if len(audio) and np.isfinite(audio).all() and np.max(np.abs(audio))>.002 and codes.shape[1]<budget:break
    else:raise RuntimeError('Invalid audio: '+text)
    active=np.flatnonzero(np.abs(audio)>.003)
    audio=audio[max(0,active[0]-900):min(len(audio),active[-1]+1800)]
    rms=float(np.sqrt(np.mean(audio**2)));peak=float(np.max(np.abs(audio)))
    audio*=min(.105/max(rms,.001),.85/peak)
    fade=min(220,len(audio)//2)
    audio[:fade]*=np.linspace(0,1,fade);audio[-fade:]*=np.linspace(1,0,fade)
    pcm=(np.clip(audio,-1,1)*32767).astype('<i2').tobytes()
    path.write_bytes(pcm)
    print('Rendered '+key+': '+text,flush=True)
    return key,pcm
with ThreadPoolExecutor(max_workers=3) as pool:
    clips=dict(pool.map(generate,texts.items()))
bank=dict(sampleRate=44100,clips={key:base64.b64encode(data).decode() for key,data in clips.items()})
(ROOT/'Assets/audio/timebank.json').write_text(json.dumps(bank,separators=(',',':')))
(ROOT/'Assets/audio/timebank-metadata.json').write_text(json.dumps(dict(model='Audio8-TTS-Preview-0.1B-ONNX-INT8',voice=VOICE,texts=texts,seconds={key:len(data)/88200 for key,data in clips.items()},sampleRate=44100,format='mono PCM signed 16-bit little-endian',seed=42,temperature=.7),ensure_ascii=False,indent=2))
print('Generated',len(clips),'clips',flush=True)
