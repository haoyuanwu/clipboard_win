import json, hashlib
from pathlib import Path
from datetime import datetime, timedelta
root=Path('build/preview-data'); root.mkdir(parents=True, exist_ok=True)
now=datetime.now(); entries=[]
for i,(text,source,tint,count) in enumerate([
 ('让每一次复制，都有迹可循。','记事本',0xff0078d4,3),
 ('SuperClipboard\n文字、图片、文件、视频，随时找回。','Microsoft Edge',0xff159b87,8),
 ('const clipboard = "随时找回灵感";\n保留原始内容，继续手头的工作。','Visual Studio Code',0xff7255b5,2),
]):
 entries.append(dict(id=f'100000000000000{i}-0',fingerprint=hashlib.sha256(('text:'+text).encode()).hexdigest(),kind='text',text=text,title='',paths=[],originalPaths=[],imagePath='',previewPath='',html='',rtf='',source=source,sourceIcon='',tint=tint,count=count,pinned=i==0,createdAt=(now-timedelta(minutes=i*5)).isoformat(),lastCopiedAt=(now-timedelta(minutes=i*5)).isoformat(),library='history'))
state=dict(history=entries,notebook=[],transfer=[],settings=dict(appearance='light',sort='time',limit=500,startup=False,transferMinutes=10,transferHistory=False),notebookPath=str(root.resolve()/'Notebook'),busy=False,error='',deadline=None)
(root/'state.json').write_text(json.dumps(state,ensure_ascii=False),encoding='utf8')
print('Prepared isolated preview records')
