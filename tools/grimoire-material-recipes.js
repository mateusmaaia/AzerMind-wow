'use strict';
function make(id) {
const leather=id==="leather";const warm=id==="parchment-warm";
const colors=leather?["#24160F","#281911","#2B1C14","#2F1F16","#332219","#38251B","#3B281D"]:warm?["#E1CDA6","#E4D1AC","#E7D5B2","#EAD9B8","#EDDCBE","#EFE0C4","#F2E4CA"]:["#DFD0B2","#E3D5B9","#E6D9BF","#E9DDC5","#ECE0CA","#EFE4D0","#F2E8D6"];
const hash=(x,y)=>{let n=Math.imul(x+19,374761393)^Math.imul(y+71,668265263);n=Math.imul(n^(n>>>13),1274126177);return ((n^(n>>>16))>>>0)/4294967295;};
const rows=[];for(let y=0;y<256;y++){let row="";for(let x=0;x<256;x++){const px=x%255,py=y%255;const coarse=Math.sin(2*Math.PI*px/255*5+0.6*Math.cos(2*Math.PI*py/255*3))*Math.cos(2*Math.PI*py/255*6)*0.45;const noise=(hash(px,py)-0.5)*(leather?2.3:1.7);const fiber=hash(Math.floor(px/3),py)<0.12?-0.8:0;const v=Math.max(0,Math.min(6,Math.round(3+coarse+noise+fiber)));row+=String(v);}rows.push(row);}
const recipe={job:{canvas:[256,256],frame_count:1,views:[{id:"material",offset:[0,0]}],source_bookends_exact:false,body_palette_exact:false},scene:{version:1,template:"layered-drawing-v1",layers:[{id:"surface",name:"Body - material"}],views:{}}};
recipe.scene.views.material={nodes:{texture:{layer:"surface",draw:[{op:"grid",rows,legend:Object.fromEntries(colors.map((c,i)=>[String(i),c]))}]}}};
return recipe;
}
module.exports=make;
if(require.main===module) {
  const fs=require('node:fs'); const path=require('node:path');
  const folder=path.join(__dirname,'../art/grimoire/recipes');
  fs.mkdirSync(folder,{recursive:true});
  for(const id of ['leather','parchment','parchment-warm']) {
    const recipe=make(id), grid=recipe.scene.views.material.nodes.texture.draw[0];
    recipe.scene.views.material.nodes.texture.draw=[0,64,128,192].map(y=>({op:'grid',at:[0,y],rows:grid.rows.slice(y,y+64),legend:grid.legend}));
    fs.writeFileSync(path.join(folder,id+'.json'),JSON.stringify(recipe));
  }
}
