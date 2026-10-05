"""One opt-in intervention through a RUNNING localhost backend, synthetic fixture only."""
import argparse
import json
import time
import urllib.request
import uuid
from .tests.fixtures import request, start, event, SCENARIO


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--url',default='http://127.0.0.1:8787')
    parser.add_argument('--expect-provider',choices=['mock','qwen'],default='mock')
    parser.add_argument('--allow-billable-call',action='store_true')
    args=parser.parse_args()
    if args.expect_provider=='qwen' and not args.allow_billable_call:
        parser.error('Qwen smoke test requires explicit --allow-billable-call authorization')
    if args.url not in ('http://127.0.0.1:8787','http://localhost:8787'):
        parser.error('This synthetic smoke test targets the documented localhost backend only')
    token=''
    def call(path,body=None):
        headers={'Content-Type':'application/json'}
        if token: headers['Authorization']='Bearer '+token
        request=urllib.request.Request(args.url+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
        with urllib.request.urlopen(request,timeout=15) as response: return json.load(response)
    body=start('smoke-'+uuid.uuid4().hex)
    body['client_secret']=uuid.uuid4().hex+uuid.uuid4().hex
    session=call('/v1/sessions',body); token=session['credential']
    if session.get('provider')!=args.expect_provider:
        raise SystemExit('Backend provider does not match the requested smoke mode; no intervention requested.')
    prefix='/v1/sessions/'+session['session_id']
    call(prefix+'/events',{'events':[event()]})
    path=prefix+'/interventions/'+SCENARIO+'/1'
    result=call(path,request())
    deadline=time.monotonic()+150
    while result['status']=='pending' and time.monotonic()<deadline:
        time.sleep(1); result=call(path)
    call(prefix+'/completion',{'status':'completed' if result['status']=='completed' else 'interrupted','last_seq':1})
    if result['status']!='completed': raise SystemExit('Smoke failed: '+str(result.get('error','timeout')))
    message=result['message']
    if message['provider']!=args.expect_provider: raise SystemExit('Provider mismatch; this is not a live Qwen verification.')
    print('Synthetic smoke succeeded; provider='+message['provider'])
    print(message['text'])
    print('Session saved. UI timing is tested separately; no participant data was used.')

if __name__=='__main__': main()
