import sys, time, json, urllib.request, urllib.error
import jwt
KID='973AZ487M3'; ISS='a3955ee4-936a-4c78-b9d1-9d1c559885af'
KEY=open('/Users/touri/.appstoreconnect/private_keys/AuthKey_973AZ487M3.p8').read()
def token():
    now=int(time.time())
    return jwt.encode({'iss':ISS,'iat':now,'exp':now+1100,'aud':'appstoreconnect-v1'},KEY,algorithm='ES256',headers={'kid':KID})
def call(method, path, body=None):
    url=path if path.startswith('http') else 'https://api.appstoreconnect.apple.com'+path
    req=urllib.request.Request(url, method=method, data=(json.dumps(body).encode() if body is not None else None))
    req.add_header('Authorization','Bearer '+token()); req.add_header('Content-Type','application/json')
    try:
        with urllib.request.urlopen(req) as r:
            t=r.read(); return r.status, (json.loads(t) if t else None)
    except urllib.error.HTTPError as e:
        t=e.read(); 
        try: return e.code, json.loads(t)
        except Exception: return e.code, t.decode(errors='replace')
if __name__=='__main__':
    m=sys.argv[1]; p=sys.argv[2]; b=json.loads(sys.argv[3]) if len(sys.argv)>3 else None
    s,d=call(m,p,b); print(s); print(json.dumps(d,ensure_ascii=False,indent=1) if d is not None else '')
