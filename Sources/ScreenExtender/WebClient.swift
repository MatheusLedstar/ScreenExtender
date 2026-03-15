/// Embedded web client served to the tablet's browser.
/// Single HTML file with inline CSS and JavaScript — zero dependencies.
enum WebClient {
    static func html(wsPort: UInt16) -> String {
        """
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <meta name="mobile-web-app-capable" content="yes">
        <meta name="apple-mobile-web-app-capable" content="yes">
        <title>Screen Extender</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        html,body{width:100%;height:100%;overflow:hidden;background:#0a0a0a;touch-action:none;-webkit-user-select:none;user-select:none}
        canvas{display:block;width:100vw;height:100vh;object-fit:contain;cursor:none}
        #overlay{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;background:#0a0a0a;color:#e0e0e0;font-family:-apple-system,system-ui,sans-serif;z-index:10;transition:opacity .4s}
        #overlay.hidden{opacity:0;pointer-events:none}
        .ov{text-align:center;max-width:320px}
        .ov h1{font-size:22px;font-weight:600;margin-bottom:12px;color:#fff}
        .ov p{font-size:14px;color:#888;margin-bottom:6px;line-height:1.5}
        .spinner{width:36px;height:36px;border:3px solid #222;border-top-color:#4af;border-radius:50%;animation:spin .8s linear infinite;margin:0 auto 18px}
        @keyframes spin{to{transform:rotate(360deg)}}
        .dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px;vertical-align:middle}
        .dot.on{background:#4c6}
        .dot.off{background:#c44}
        #toolbar{position:fixed;top:8px;right:8px;z-index:20;display:flex;gap:6px;opacity:0;transition:opacity .3s}
        #toolbar.show{opacity:1}
        #toolbar button{background:rgba(0,0,0,.55);color:#ccc;border:1px solid #333;padding:6px 12px;border-radius:6px;font-size:13px;cursor:pointer;backdrop-filter:blur(8px);-webkit-backdrop-filter:blur(8px)}
        #toolbar button:active{background:rgba(255,255,255,.1)}
        #stats{position:fixed;bottom:6px;left:8px;color:#444;font:11px/1 monospace;z-index:20}
        </style>
        </head>
        <body>
        <canvas id="scr"></canvas>
        <div id="overlay">
         <div class="ov">
          <div class="spinner"></div>
          <h1>Screen Extender</h1>
          <p id="status">Conectando ao Mac...</p>
          <p style="font-size:12px;color:#555;margin-top:12px">WiFi: mesma rede que o Mac<br>USB: adb reverse tcp:\(wsPort) tcp:\(wsPort)</p>
         </div>
        </div>
        <div id="toolbar">
         <button onclick="goFS()">&#x26F6; Tela Cheia</button>
        </div>
        <div id="stats"></div>
        <script>
        (function(){
        const C=document.getElementById('scr'),X=C.getContext('2d'),OV=document.getElementById('overlay'),
              ST=document.getElementById('status'),TB=document.getElementById('toolbar'),SS=document.getElementById('stats');
        let ws,ok=false,iW=0,iH=0,fc=0,lt=performance.now(),fps=0;

        function conn(){
         const h=location.hostname,p=\(wsPort);
         ST.textContent='Conectando...';
         ws=new WebSocket('ws://'+h+':'+p);
         ws.binaryType='arraybuffer';
         ws.onopen=()=>{ok=true;OV.classList.add('hidden');TB.classList.add('show')};
         ws.onmessage=async e=>{
          if(!(e.data instanceof ArrayBuffer))return;
          const b=new Blob([e.data],{type:'image/jpeg'});
          const bm=await createImageBitmap(b);
          if(C.width!==bm.width||C.height!==bm.height){C.width=bm.width;C.height=bm.height;iW=bm.width;iH=bm.height}
          X.drawImage(bm,0,0);bm.close();
          fc++;const n=performance.now();if(n-lt>=1000){fps=fc/((n-lt)/1000);fc=0;lt=n;SS.textContent=fps.toFixed(1)+' fps | '+iW+'x'+iH}
         };
         ws.onclose=()=>{ok=false;OV.classList.remove('hidden');TB.classList.remove('show');ST.textContent='Desconectado. Reconectando...';setTimeout(conn,2000)};
         ws.onerror=()=>ws.close();
        }

        // Coordinate mapping (accounts for object-fit:contain)
        function rel(cx,cy){
         const r=C.getBoundingClientRect(),ca=iW/iH,va=r.width/r.height;
         let ox=0,oy=0,rw=r.width,rh=r.height;
         if(ca>va){rh=r.width/ca;oy=(r.height-rh)/2}else{rw=r.height*ca;ox=(r.width-rw)/2}
         return{x:Math.max(0,Math.min(1,(cx-r.left-ox)/rw)),y:Math.max(0,Math.min(1,(cy-r.top-oy)/rh))}
        }
        function snd(t,cx,cy,extra){
         if(!ok||!ws)return;
         const c=rel(cx,cy);const m={t:t,x:c.x,y:c.y};
         if(extra)Object.assign(m,extra);
         ws.send(JSON.stringify(m));
        }

        // Touch
        C.addEventListener('touchstart',e=>{e.preventDefault();const t=e.touches[0];snd('d',t.clientX,t.clientY)},{passive:false});
        C.addEventListener('touchmove',e=>{e.preventDefault();const t=e.touches[0];snd('m',t.clientX,t.clientY)},{passive:false});
        C.addEventListener('touchend',e=>{e.preventDefault();if(e.changedTouches.length)snd('u',e.changedTouches[0].clientX,e.changedTouches[0].clientY)},{passive:false});

        // Mouse (desktop testing)
        let md=false;
        C.addEventListener('mousedown',e=>{md=true;snd('d',e.clientX,e.clientY)});
        C.addEventListener('mousemove',e=>{snd(md?'m':'h',e.clientX,e.clientY)});
        C.addEventListener('mouseup',e=>{md=false;snd('u',e.clientX,e.clientY)});
        C.addEventListener('contextmenu',e=>{e.preventDefault();snd('r',e.clientX,e.clientY)});
        C.addEventListener('wheel',e=>{e.preventDefault();snd('s',e.clientX,e.clientY,{dx:-e.deltaX,dy:-e.deltaY})},{passive:false});

        // Prevent pinch zoom
        document.addEventListener('gesturestart',e=>e.preventDefault());
        document.addEventListener('gesturechange',e=>e.preventDefault());

        window.goFS=()=>{document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen().catch(()=>{})};

        conn();
        })();
        </script>
        </body>
        </html>
        """
    }
}
