import json,os,struct,subprocess,tempfile,datetime,pathlib
now=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='milliseconds').replace('+00:00','Z')
message=dict(version=1,pageURL='https://x.com/thsottiaux',capturedAt=now,pageLoadedAt=now,status='ok',posts=[dict(url='https://x.com/thsottiaux/status/12345',date=now,text='Protocol test only',quote='',truncated=False)])
with tempfile.TemporaryDirectory(prefix='tibo-bridge-test-') as tmp:
 def send(obj):
  data=json.dumps(obj).encode()
  run=subprocess.run(['dist/TiboXBridge'],input=struct.pack('<I',len(data))+data,capture_output=True,env=dict(os.environ,TIBO_BRIDGE_TEST_ROOT=tmp),check=True)
  size=struct.unpack('<I',run.stdout[:4])[0]
  return json.loads(run.stdout[4:4+size])
 assert send(message)['ok'] is True
 target=pathlib.Path(tmp)/'x-direct-posts.json'
 original=target.read_bytes()
 bad=dict(message,pageURL='https://x.com/messages')
 assert send(bad)['ok'] is False and target.read_bytes()==original
 bad=dict(message,posts=[dict(message['posts'][0],url='https://x.com/other/status/12345')])
 assert send(bad)['ok'] is False and target.read_bytes()==original
 print('Native bridge framing and path/author rejection checks passed; real app data untouched.')
