document.addEventListener("DOMContentLoaded",function(){
  document.querySelectorAll("[data-nav]").forEach(function(a){
    var path=location.pathname;
    var key=a.getAttribute("data-nav");
    var active=(key==="home" && (path==="/"||path==="/index.html")) ||
      (key==="articles" && path.indexOf("/articles/")===0) ||
      (key==="scripts" && path.indexOf("/scripts/")===0);
    if(active)a.classList.add("active");
  });
});