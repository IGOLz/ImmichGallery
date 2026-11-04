import json, urllib.request, os
base='https://demo.immich.app/api/'
def call(path, method='GET', body=None, token=None):
 req=urllib.request.Request(base+path, data=json.dumps(body).encode() if body is not None else None, method=method, headers={'Content-Type':'application/json','User-Agent':'ImmichGallery-Account-Verification',**({'Authorization':'Bearer '+token} if token else {})})
 with urllib.request.urlopen(req) as r:
  data=r.read()
  return json.loads(data) if data else None
token=call('auth/login','POST',{'email':'demo@immich.app','password':'demo'})['accessToken']
keyid=None
ownid=None
try:
 for path,name in [('server/version','version'),('users/me','user'),('users/me/preferences','preferences'),('api-keys','keys'),('sessions','sessions'),('notifications','notifications')]:
  result=call(path,token=token)
  with open('build/AccountChecks/'+name+'.json','w') as f: json.dump(result,f)
  print(path, 'OK', (len(result) if isinstance(result,list) else 'object'))
  if path=='sessions': ownid=next(d['id'] for d in result if d['current'])
 print('version',call('server/version',token=token))
 created=call('api-keys','POST',{'name':'ImmichGallery temporary account verification','permissions':['asset.read']},token)
 keyid=created.get('id') or created['apiKey']['id']
 # Decode the real secret response without saving the secret.
 created['secret']='redacted-test-secret'
 with open('build/AccountChecks/created-key.json','w') as f: json.dump(created,f)
 renamed=call('api-keys/'+keyid,'PUT',{'name':'ImmichGallery temporary renamed verification'},token)
 assert renamed['name']=='ImmichGallery temporary renamed verification'
 print('API key create and rename OK')
finally:
 if keyid:
  call('api-keys/'+keyid,'DELETE',token=token); print('Temporary API key deleted')
 if ownid:
  call('sessions/'+ownid,'DELETE',token=token); print('Only our verification session deleted')
 else:
  call('auth/logout','POST',token=token)
