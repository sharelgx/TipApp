#!/bin/zsh
set -eu
cd "${0:A:h}/.."
BRIDGE_DIR="$HOME/Library/Application Support/TiboWatch/Bridge"
HOST_DIR="$HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
mkdir -p "$BRIDGE_DIR" "$HOST_DIR"
xcrun swiftc -O Sources/XBridge.swift -o "$BRIDGE_DIR/TiboXBridge"
codesign --force --sign - "$BRIDGE_DIR/TiboXBridge"
/usr/bin/python3 - "$BRIDGE_DIR/TiboXBridge" "$HOST_DIR/local.tibowatch.x.json" <<'PY'
import json,sys,pathlib
identity=json.loads(pathlib.Path('BrowserExtension/identity.json').read_text())
manifest=dict(name=identity['nativeHost'],description='Tibo Watch local public-post bridge',path=sys.argv[1],type='stdio',allowed_origins=['chrome-extension://'+identity['extensionId']+'/'])
pathlib.Path(sys.argv[2]).write_text(json.dumps(manifest,indent=2)+'\n')
PY
printf '%s\n' '本机桥接已安装。下一步在 Edge 扩展管理中加载 BrowserExtension 文件夹。'
