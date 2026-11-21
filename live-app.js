(()=>{ 
  if(window.__ahmedkoLiveAppInstalled)return;
  window.__ahmedkoLiveAppInstalled=true;
  const style=document.createElement("style");
  style.textContent="#ahmedkoLiveRefresh{position:fixed;top:10px;left:50%;transform:translate(-50%,-150%);z-index:99999;background:#071A35;color:#fff;border:1px solid #f5c32b;border-radius:999px;padding:9px 16px;font:700 13px Arial,sans-serif;box-shadow:0 8px 22px #0005;opacity:0;transition:transform .18s,opacity .18s}#ahmedkoLiveRefresh.show{transform:translate(-50%,0);opacity:1}#ahmedkoLiveRefresh .spin{display:inline-block;color:#f5c32b;margin-inline-end:7px}#ahmedkoLiveRefresh.busy .spin{animation:ahmedkoLiveSpin .8s linear infinite}@keyframes ahmedkoLiveSpin{to{transform:rotate(360deg)}}";
  document.head.appendChild(style);
  const indicator=document.createElement("div");
  indicator.id="ahmedkoLiveRefresh";
  indicator.innerHTML='<span class="spin">↓</span><span>اسحب للأسفل للتحديث</span>';
  document.body.appendChild(indicator);
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
        const reg=await navigator.serviceWorker.getRegistration("/");
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
        const reg=await navigator.serviceWorker.register(new URL("service-worker.js",location.origin+"/ahmedko-delivery/"),{updateViaCache:"none"});
        const check=()=>reg.update().catch(()=>{});
        check();setInterval(check,60000);
        document.addEventListener("visibilitychange",()=>{if(!document.hidden)check();});
      }catch(e){console.warn("AHMEDKO service worker:",e);}
    });
  }
})();