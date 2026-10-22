#!/usr/bin/env python3
"""Tiny Chrome DevTools driver over `adb forward tcp:9222 localabstract:chrome_devtools_remote`.
Never prints secrets: every output passes through scrub()."""
import json, os, sys, time, urllib.request, base64
import websocket

HOST = os.environ["PREVIEW_HOST"]
SECRETS = [os.environ.get(k, "") for k in ("BYPASS", "QA_EMAIL", "QA_PASSWORD")]

def scrub(s):
    s = str(s)
    for v in SECRETS:
        if v:
            s = s.replace(v, "***")
    return s

def targets():
    with urllib.request.urlopen("http://127.0.0.1:9222/json/list", timeout=10) as r:
        return [t for t in json.load(r) if t.get("type") == "page"]

def pick(any_page=False):
    for _ in range(15):
        ts = targets()
        hits = [t for t in ts if HOST in t.get("url", "")]
        if hits:
            return hits[0]
        time.sleep(2)
    if ts:
        return ts[0]
    raise SystemExit("no matching page target: " + scrub([t.get("url") for t in ts]))

_id = [0]
def call(ws, method, params=None):
    _id[0] += 1
    ws.send(json.dumps({"id": _id[0], "method": method, "params": params or {}}))
    while True:
        m = json.loads(ws.recv())
        if m.get("id") == _id[0]:
            return m

def ev(ws, expr, await_promise=True):
    r = call(ws, "Runtime.evaluate", {"expression": expr, "awaitPromise": await_promise, "returnByValue": True})
    return r.get("result", {}).get("result", {}).get("value", r.get("result"))

def connect(t):
    return websocket.create_connection(t["webSocketDebuggerUrl"], timeout=60, suppress_origin=True)

def main():
    cmd = sys.argv[1]
    if cmd == "tabs":
        for t in targets():
            print(scrub(t.get("url")), "|", scrub(t.get("title")))
        return
    if cmd == "nav":
        ws = connect(pick(any_page=True))
        call(ws, "Page.navigate", {"url": sys.argv[2]})
        print("navigated")
        return
    if cmd == "text":
        for t in targets():
            if HOST not in t.get("url", ""):
                continue
            ws = connect(t)
            print("=== URL:", scrub(ev(ws, "location.href")))
            print(scrub(ev(ws, "document.body ? document.body.innerText.slice(0,3000) : ''")))
            print("=== dialogs:", scrub(ev(ws, "Array.from(document.querySelectorAll('[role=dialog]')).map(d=>d.innerText.slice(0,1500)).join('\\n---\\n')")))
            print("=== sw:", scrub(ev(ws, "navigator.serviceWorker && navigator.serviceWorker.getRegistrations().then(r=>r.map(x=>x.active&&x.active.scriptURL).join(','))")))
            print("=== displayMode standalone:", ev(ws, "matchMedia('(display-mode: standalone)').matches"))
            print("=== share-db:", scrub(ev(ws, "new Promise(res=>{const q=indexedDB.open('ten10-share-target',1);q.onupgradeneeded=()=>q.result.createObjectStore('files',{keyPath:'id'});q.onsuccess=()=>{try{const g=q.result.transaction('files').objectStore('files').getAll();g.onsuccess=()=>res(JSON.stringify(g.result.map(x=>({name:x.name,type:x.type,text:x.text,size:x.buffer?x.buffer.byteLength:0}))));}catch(e){res('err '+e)}};q.onerror=()=>res('open err')})")))
        return
    if cmd == "login":
        ws = connect(pick())
        email = json.dumps(os.environ["QA_EMAIL"]); pw = json.dumps(os.environ["QA_PASSWORD"])
        js = """(async()=>{
          const sleep=ms=>new Promise(r=>setTimeout(r,ms));
          for(let i=0;i<30&&!document.querySelector('#login-username');i++) await sleep(500);
          const e=document.querySelector('#login-username'), p=document.querySelector('#password');
          if(!e||!p) return 'no login form at '+location.pathname;
          const set=(el,v)=>{Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value').set.call(el,v);el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));};
          set(e,%s); set(p,%s);
          const b=e.form.querySelector('button[type=submit]'); b.click();
          for(let i=0;i<40&&location.pathname.startsWith('/login');i++) await sleep(500);
          return 'after submit: '+location.pathname;
        })()""" % (email, pw)
        print(scrub(ev(ws, js)))
        return
    if cmd in ("sharetext", "sharefile"):
        # Fallback that exercises the real SW /share-target handler from the page (no OS share sheet).
        ws = connect(pick())
        if cmd == "sharetext":
            body = "fd.append('text', %s);" % json.dumps(sys.argv[2])
        else:
            b64 = base64.b64encode(open(sys.argv[2], "rb").read()).decode()
            body = "const bin=atob('%s');const u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);fd.append('file', new File([u],'receipt.png',{type:'image/png'}));" % b64
        js = "(async()=>{const fd=new FormData();%s const r=await fetch('/share-target',{method:'POST',body:fd,redirect:'manual'});const s=r.type+' '+r.status;location.href='/?ai-share=1';return s;})()" % body
        print(scrub(ev(ws, js)))
        return
    raise SystemExit("unknown cmd")

if __name__ == "__main__":
    main()
