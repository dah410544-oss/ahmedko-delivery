(()=>{ 
  if(window.__ahmedkoLiveAppInstalled)return;
  window.__ahmedkoLiveAppInstalled=true;
  const style=document.createElement("style");
  style.textContent="#ahmedkoNetworkState{position:fixed;right:12px;bottom:12px;z-index:99998;background:#102849;color:#fff;border:1px solid #F5C32B;border-radius:999px;padding:7px 12px;font:700 12px Arial,sans-serif;box-shadow:0 5px 16px #0004;opacity:0;transform:translateY(12px);transition:opacity .2s,transform .2s;pointer-events:none}#ahmedkoNetworkState.show{opacity:1;transform:translateY(0)}#ahmedkoNetworkState.offline{border-color:#ef6b73;background:#401c29}#ahmedkoLiveRefresh{position:fixed;top:10px;left:50%;transform:translate(-50%,-150%);z-index:99999;background:#071A35;color:#fff;border:1px solid #f5c32b;border-radius:999px;padding:9px 16px;font:700 13px Arial,sans-serif;box-shadow:0 8px 22px #0005;opacity:0;transition:transform .18s,opacity .18s}#ahmedkoLiveRefresh.show{transform:translate(-50%,0);opacity:1}#ahmedkoLiveRefresh .spin{display:inline-block;color:#f5c32b;margin-inline-end:7px}#ahmedkoLiveRefresh.busy .spin{animation:ahmedkoLiveSpin .8s linear infinite}@keyframes ahmedkoLiveSpin{to{transform:rotate(360deg)}}";
  style.textContent += "\n/* AHMEDKO PREMIUM VISUAL IDENTITY */\n:root{--ak-gold:#F5C32B;--ak-night:#06152d;--ak-blue:#102849;--ak-glass:rgba(18,43,76,.78)}\nhtml{background:#06152d}\nbody{background:radial-gradient(ellipse at 88% 4%,rgba(34,91,145,.24),transparent 34%),radial-gradient(ellipse at 8% 48%,rgba(245,195,43,.055),transparent 28%),linear-gradient(180deg,#06152d 0%,#081b36 48%,#06152d 100%)}\nbody:before{content:\"\";position:fixed;inset:0;z-index:-1;pointer-events:none;opacity:.22;background-image:radial-gradient(rgba(245,195,43,.32) .7px,transparent .7px);background-size:28px 28px;mask-image:linear-gradient(to bottom,black,transparent 76%)}\n.top{background:rgba(5,19,40,.88);border-bottom:1px solid rgba(245,195,43,.22);box-shadow:0 12px 36px rgba(0,0,0,.28)}\n.brand{letter-spacing:.8px;text-shadow:0 2px 18px rgba(245,195,43,.12)}\n.hero{isolation:isolate;background:radial-gradient(ellipse at 82% 18%,rgba(245,195,43,.20),transparent 24%),radial-gradient(ellipse at 18% 85%,rgba(36,101,158,.38),transparent 42%),linear-gradient(125deg,#06152d 0%,#102b4e 55%,#173e68 100%);border:1px solid rgba(245,195,43,.22);border-radius:0 0 34px 34px;box-shadow:0 22px 55px rgba(0,0,0,.22)}\n.hero:before{content:\"\";position:absolute;width:340px;height:340px;border-radius:50%;right:-120px;top:-190px;border:1px solid rgba(245,195,43,.22);box-shadow:0 0 0 28px rgba(245,195,43,.025),0 0 0 58px rgba(245,195,43,.02);z-index:0;pointer-events:none}\n.hero:after{opacity:.16;filter:drop-shadow(0 20px 35px rgba(0,0,0,.5))}\n.hero h1{letter-spacing:-.6px;text-shadow:0 5px 24px rgba(0,0,0,.2)}\n.eyebrow{background:linear-gradient(120deg,rgba(245,195,43,.18),rgba(245,195,43,.06));box-shadow:0 5px 20px rgba(245,195,43,.08)}\n.btn.yellow,.small.yellow{box-shadow:0 8px 22px rgba(245,195,43,.18)}\nsection{background:transparent}\n.heading h2{letter-spacing:-.25px}\n.card,.store{background:linear-gradient(145deg,rgba(21,52,88,.94),rgba(8,27,52,.94));border:1px solid rgba(151,184,220,.17);box-shadow:0 16px 36px rgba(0,0,0,.20),inset 0 1px 0 rgba(255,255,255,.035);backdrop-filter:blur(12px)}\n.card:hover,.store:hover{border-color:rgba(245,195,43,.55);box-shadow:0 20px 42px rgba(0,0,0,.27),0 0 24px rgba(245,195,43,.07)}\n.ico{filter:drop-shadow(0 5px 10px rgba(0,0,0,.28))}\n.search{background:rgba(13,36,66,.94);border-color:rgba(151,184,220,.24);box-shadow:inset 0 1px 0 rgba(255,255,255,.035)}\n.restaurant-search-toolbar{background:rgba(5,20,42,.91);border-color:rgba(245,195,43,.20);backdrop-filter:blur(18px)}\n.contact{background:radial-gradient(ellipse at 90% 0%,rgba(245,195,43,.12),transparent 38%),linear-gradient(135deg,#112e50,#07182f);border-color:rgba(245,195,43,.24);box-shadow:0 22px 48px rgba(0,0,0,.25)}\nfooter{background:#040f20;border-top-color:rgba(245,195,43,.18)}\n.cart-fab{box-shadow:0 12px 30px rgba(245,195,43,.24),0 5px 18px rgba(0,0,0,.35)}\n@media(prefers-reduced-motion:no-preference){.card,.store,.btn,.small{transition:transform .22s ease,box-shadow .22s ease,border-color .22s ease}.hero .btn{animation:akRise .65s both}@keyframes akRise{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}}\n";
  document.head.appendChild(style);
  const indicator=document.createElement("div");
  indicator.id="ahmedkoLiveRefresh";
  indicator.innerHTML='<span class="spin">↓</span><span>اسحب للأسفل للتحديث</span>';
  document.body.appendChild(indicator);
  const networkState=document.createElement("div");
  networkState.id="ahmedkoNetworkState";
  networkState.setAttribute("role","status");
  networkState.setAttribute("aria-live","polite");
  document.body.appendChild(networkState);
  let networkTimer;
  const showNetworkState=online=>{
    networkState.textContent=online?"عاد الاتصال بالإنترنت":"لا يوجد اتصال بالإنترنت";
    networkState.classList.toggle("offline",!online);
    networkState.classList.add("show");
    clearTimeout(networkTimer);
    if(online&&"serviceWorker" in navigator){
      navigator.serviceWorker.getRegistration().then(reg=>reg&&reg.update().catch(()=>{})).catch(()=>{});
    }
    networkTimer=setTimeout(()=>networkState.classList.remove("show"),online?3500:10000);
  };
  window.addEventListener("offline",()=>showNetworkState(false));
  window.addEventListener("online",()=>showNetworkState(true));
  let startY=0,pulling=false,refreshing=false;
  const threshold=75;
  const hide=()=>{indicator.classList.remove("show");indicator.style.transform="translate(-50%,-150%)";};
  async function refresh(){
    if(refreshing)return;
    refreshing=true;indicator.classList.add("show","busy");
    indicator.querySelector("span:last-child").textContent="جارٍ تحميل أحدث نسخة…";
    indicator.querySelector(".spin").textContent="↻";
    try{
      if("serviceWorker" in navigator){
        const reg=await navigator.serviceWorker.getRegistration();
        if(reg){
          await reg.update().catch(()=>{});
          if(reg.waiting)reg.waiting.postMessage({type:"SKIP_WAITING"});
        }
      }
    }catch(e){console.warn("AHMEDKO update check:",e);}
    setTimeout(()=>location.reload(),450);
  }
  window.addEventListener("touchstart",e=>{
    if(refreshing||e.touches.length!==1||window.scrollY>0)return;
    const t=e.target;
    if(t&&t.closest&&t.closest("input,textarea,select,[contenteditable=true]"))return;
    startY=e.touches[0].clientY;pulling=startY<180;
  },{passive:true});
  window.addEventListener("touchmove",e=>{
    if(!pulling||refreshing||e.touches.length!==1||window.scrollY>0)return;
    const d=e.touches[0].clientY-startY;
    if(d<=0)return;
    e.preventDefault();
    indicator.classList.add("show");
    indicator.style.transform="translate(-50%,"+Math.min(d,threshold+20)+"px)";
    indicator.querySelector(".spin").textContent=d>=threshold?"↻":"↓";
    indicator.querySelector("span:last-child").textContent=d>=threshold?"اترك الشاشة للتحديث":"اسحب للأسفل للتحديث";
  },{passive:false});
  const finish=()=>{if(!pulling)return;const armed=indicator.querySelector("span:last-child").textContent==="اترك الشاشة للتحديث";pulling=false;if(armed)refresh();else hide();};
  window.addEventListener("touchend",finish,{passive:true});
  window.addEventListener("touchcancel",finish,{passive:true});
  if("serviceWorker" in navigator&&location.protocol==="https:"){
    let reloading=false;
    navigator.serviceWorker.addEventListener("controllerchange",()=>{if(!reloading){reloading=true;location.reload();}});
    window.addEventListener("load",async()=>{
      try{
        const reg=await navigator.serviceWorker.register(new URL("./service-worker.js",document.baseURI),{updateViaCache:"none"});
        const check=()=>reg.update().catch(()=>{});
        check();setInterval(check,15000);
        document.addEventListener("visibilitychange",()=>{if(!document.hidden)check();});
      }catch(e){console.warn("AHMEDKO service worker:",e);}
    });
  }
})();