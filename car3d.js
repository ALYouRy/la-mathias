/* Sandero — vue 3D pour l’iPhone (modèle Dacia Sandero 1.2 16V) */
(function(){
"use strict";
var settings={plates:true,plateText:"",plateDept:"13"},Car={gm:null},GL3={parts:[],model:false};
function clamp(v,a,b){return v<a?a:v>b?b:v}
var F16=new Float32Array(16);function f16(m){F16.set(m);return F16}function f3(a,b){a.set(b);return a}
function norm3(v){var l=Math.sqrt(v[0]*v[0]+v[1]*v[1]+v[2]*v[2])||1;return [v[0]/l,v[1]/l,v[2]/l]}
var M4={
  id:function(){return [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
  mul:function(a,b){var o=new Array(16),i,j,k,s;for(i=0;i<4;i++)for(j=0;j<4;j++){s=0;for(k=0;k<4;k++)s+=a[k*4+j]*b[i*4+k];o[i*4+j]=s}return o},
  tr:function(x,y,z){var m=M4.id();m[12]=x;m[13]=y;m[14]=z;return m},
  sc:function(x,y,z){var m=M4.id();m[0]=x;m[5]=y;m[10]=z;return m},
  rx:function(a){var c=Math.cos(a),s=Math.sin(a);return [1,0,0,0,0,c,s,0,0,-s,c,0,0,0,0,1]},
  ry:function(a){var c=Math.cos(a),s=Math.sin(a);return [c,0,-s,0,0,1,0,0,s,0,c,0,0,0,0,1]},
  rz:function(a){var c=Math.cos(a),s=Math.sin(a);return [c,s,0,0,-s,c,0,0,0,0,1,0,0,0,0,1]},
  persp:function(fv,as,n,f){var t=1/Math.tan(fv/2);return [t/as,0,0,0,0,t,0,0,0,0,(f+n)/(n-f),-1,0,0,2*f*n/(n-f),0]},
  look:function(e,c){
    var z=norm3([e[0]-c[0],e[1]-c[1],e[2]-c[2]]),x=norm3([z[2],0,-z[0]]);
    var y=[z[1]*x[2]-z[2]*x[1],z[2]*x[0]-z[0]*x[2],z[0]*x[1]-z[1]*x[0]];
    return [x[0],y[0],z[0],0,x[1],y[1],z[1],0,x[2],y[2],z[2],0,
      -(x[0]*e[0]+x[1]*e[1]+x[2]*e[2]),-(y[0]*e[0]+y[1]*e[1]+y[2]*e[2]),-(z[0]*e[0]+z[1]*e[1]+z[2]*e[2]),1];
  },
  pivot:function(px,py,pz,R){return M4.mul(M4.tr(px,py,pz),M4.mul(R,M4.tr(-px,-py,-pz)))}
};

function gmesh(){return {p:[],c:[],i:[],n:null,line:false}}
function gBox(cx,cy,cz,sx,sy,sz){
  var g=gmesh(),h=[sx/2,sy/2,sz/2],faces=[[0,1],[0,-1],[1,1],[1,-1],[2,1],[2,-1]],cn=[[-1,-1],[1,-1],[1,1],[-1,1]];
  faces.forEach(function(F){
    var ax=F[0],sg=F[1],u=(ax+1)%3,v=(ax+2)%3,base=g.p.length/3;
    cn.forEach(function(k){var q=[0,0,0];q[ax]=sg*h[ax];q[u]=k[0]*h[u];q[v]=k[1]*h[v];g.p.push(cx+q[0],cy+q[1],cz+q[2]);g.c.push(1,1,1)});
    g.i.push(base,base+1,base+2,base,base+2,base+3);
  });
  return g;
}
var VS3='attribute vec3 aP;attribute vec3 aN;attribute vec3 aC;uniform mat4 uVP;uniform mat4 uM;varying vec3 vN;varying vec3 vW;varying vec3 vC;varying vec3 vU;'+
'void main(){vec4 w=uM*vec4(aP,1.0);vW=w.xyz;vN=(uM*vec4(aN,0.0)).xyz;vC=aC;vU=aN;gl_Position=uVP*w;}';
var FS3='#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#else\nprecision mediump float;\n#endif\n'+
'varying vec3 vN;varying vec3 vW;varying vec3 vC;varying vec3 vU;'+
'uniform vec3 uColor;uniform vec3 uEye;uniform vec3 uEmis;uniform float uRefl;uniform float uShin;uniform float uShadow;uniform float uLine;uniform float uAlpha;uniform float uGlow;uniform float uMir;uniform float uBlue;uniform float uPaint;uniform vec3 uPL[4];uniform vec3 uPC[4];'+
'float sdr(vec2 p){return length(p)-2.7;}'+
'float sdb(vec2 p){vec2 q=abs(p)-vec2(1.55,0.50);return length(max(q,0.0))+min(max(q.x,q.y),0.0)-0.45;}'+
/* environnement « studio photo » : murs gris dégradés, sol sombre, grande softbox au plafond, bandes lumineuses */
'vec3 envm(vec3 R){float y=R.y;'+
'vec3 wall=mix(vec3(0.30,0.31,0.34),vec3(0.80,0.82,0.88),smoothstep(0.0,0.95,y));'+
'vec3 flo=mix(vec3(0.24,0.24,0.26),vec3(0.035,0.035,0.04),smoothstep(0.0,-0.75,y));'+
'vec3 e=mix(flo,wall,smoothstep(-0.05,0.07,y));'+
'e+=vec3(1.0)*exp(-abs(y-0.03)*9.0)*0.28;'+
'float az=atan(R.z,R.x);'+
'float tb=smoothstep(0.56,0.46,abs(R.x))*smoothstep(0.42,0.32,abs(R.z))*smoothstep(0.55,0.62,y);'+
'float yy=smoothstep(0.0,0.14,y)*smoothstep(0.80,0.50,y);'+
'float s1=smoothstep(0.15,0.10,abs(az-2.25))*yy;'+
'float s2=smoothstep(0.12,0.08,abs(az+0.85))*yy;'+
'float s3=smoothstep(0.09,0.06,abs(az-0.45))*yy;'+
'float s4=smoothstep(0.18,0.06,abs(az+2.4))*yy;'+
'e+=vec3(1.0)*tb*4.2+vec3(1.0,0.96,0.90)*s1*3.4+vec3(0.92,0.96,1.0)*s2*2.8+vec3(1.0)*s3*2.2+vec3(0.9,0.94,1.0)*s4*2.0;'+
'return e;}'+
'vec3 tmap(vec3 c){c*=0.92;return clamp((c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14),0.0,1.0);}'+
'void main(){'+
'if(uShadow>0.5){float d=sdb(vW.xz);float a=0.60*(1.0-smoothstep(-0.30,0.95,d));a+=0.34*(1.0-smoothstep(-0.12,0.22,d));gl_FragColor=vec4(0.0,0.0,0.0,clamp(a,0.0,0.92));return;}'+
'if(uLine>0.5){gl_FragColor=vec4(uColor,1.0);return;}'+
'if(uGlow>0.5){float a;if(uGlow<1.5){float d=length(vU.xy);a=exp(-d*d*3.2)*smoothstep(1.0,0.75,d);}'+
'else if(uGlow>2.5){float d=sdr(vW.xz);float fd=1.0-smoothstep(0.55,0.98,length(vU.xy));float led=0.0;float so=smoothstep(-0.03,0.06,d);float bl=0.42*exp(-max(d,0.0)*8.0)*so*fd;float sp=0.0;float fl=smoothstep(0.0,0.10,d)*fd*0.93;float a2=clamp(led+bl+sp,0.0,1.0)*uAlpha;vec3 cc=mix(uColor,vec3(0.80,0.92,1.0),led);gl_FragColor=vec4(cc*a2,clamp(a2+fl,0.0,1.0));return;}'+
'else{float u=(vU.x+1.0)*0.5;float w=vU.y/(0.34+0.80*u);float pr=exp(-w*w*2.6);float hot=exp(-pow((u-0.40)/0.22,2.0));a=pr*(exp(-u*2.2)*0.70+hot*0.60)*smoothstep(0.0,0.28,u)*(1.0-smoothstep(0.80,1.0,u));}'+
'a*=uAlpha;gl_FragColor=vec4(uColor*a,a);return;}'+
'if(uMir>0.5){if(vW.y>-0.002)discard;vec3 dd=vW-uEye;float tt=uEye.y/(uEye.y-vW.y);vec2 hp=uEye.xz+dd.xz*tt;if(sdr(hp)>-0.04)discard;}'+
'vec3 L=normalize(vec3(0.35,0.85,0.45));vec3 n=normalize(vN);vec3 V=normalize(uEye-vW);if(dot(n,V)<0.0)n=-n;'+
'vec3 base=uColor*vC;float ndl=max(dot(n,L),0.0);float wl=clamp((dot(n,L)+0.35)/1.35,0.0,1.0);'+
'vec3 amb=mix(vec3(0.20,0.21,0.23),vec3(0.66,0.69,0.74),0.5+0.5*n.y);'+
'float ao=mix(0.40,1.0,smoothstep(0.0,0.55,vW.y))*(0.78+0.22*smoothstep(-0.7,0.3,n.y));'+
'float lo=smoothstep(-0.2,0.2,abs(vW.z)-0.6)*0.0;'+
'float ndv=max(dot(n,V),0.0);float fr=pow(1.0-ndv,5.0);'+
'vec3 R=reflect(-V,n);vec3 env=envm(R);'+
'vec3 H=normalize(L+V);float ndh=max(dot(n,H),0.0);'+
'vec3 col;float oa=uAlpha;vec3 add=vec3(0.0);'+
'if(uPaint>0.5){'+
/* peinture : sous-couche teintée + paillettes métallisées + vernis qui reflète le studio (Fresnel) */
'vec3 diff=base*(amb*0.60+vec3(1.0,0.97,0.92)*wl*0.55)*ao;'+
'vec3 Rr=normalize(mix(R,n,0.50));vec3 flake=envm(Rr)*(base*1.05+0.02);'+
'float F=0.04+0.96*fr;'+
'vec3 cc=env*(0.07+0.93*F);'+
'col=diff*0.52+flake*0.44*ao+cc*uRefl*1.30*mix(0.45,1.0,ao);'+
'col+=vec3(1.0,0.98,0.95)*(pow(ndh,uShin*2.5)*0.65+pow(ndh,uShin*10.0)*2.6)*uRefl;'+
'col+=base*fr*0.22*smoothstep(0.0,0.4,vW.y);'+
'}else if(uAlpha<0.995&&uRefl<0.85){'+
/* verre : très peu de matière, reflets du studio de plus en plus forts en angle rasant, reflet net des lumières */
'float F=0.05+0.95*fr;col=base*amb*0.22;add=env*(0.12+0.88*F)*0.95+vec3(1.0)*pow(ndh,160.0)*1.8;oa=clamp(uAlpha+0.18+F*0.55,0.0,1.0);'+
'}else if(uRefl>0.55&&uRefl<0.75){'+
/* métal (jantes, chromes) : surtout le reflet de l'environnement, teinté par le métal */
'vec3 diff=base*(amb*0.9+vec3(1.0,0.97,0.92)*ndl*0.5)*ao;'+
'col=mix(diff*0.4,env*(base*0.80+0.18),0.72+0.25*fr)*mix(0.55,1.0,ao);'+
'col+=vec3(1.0)*(pow(ndh,max(uShin,20.0)*1.5)*1.1+pow(ndh,400.0)*1.5);'+
'}else{'+
/* plastiques, pneus, intérieur : satiné léger au lieu d'un mat plat */
'vec3 diff=base*(amb*0.9+vec3(1.0,0.97,0.92)*ndl*0.55)*ao;'+
'float k=clamp(uRefl*(0.25+0.75*fr),0.0,0.95);'+
'col=mix(diff,env*mix(vec3(1.0),base*1.5+0.25,0.30),k);'+
'col+=vec3(1.0)*pow(ndh,max(uShin,6.0))*(0.06+uRefl*0.9)*ao;'+
'col+=env*fr*0.06*ao;'+
'}'+
'vec3 pl=vec3(0.0),ps=vec3(0.0);for(int i=0;i<4;i++){vec3 d=uPL[i]-vW;float dl=length(d)+0.001;vec3 ld=d/dl;float at=1.0/(1.0+dl*dl*3.2);pl+=uPC[i]*at*clamp(dot(n,ld)*0.7+0.3,0.0,1.0);ps+=uPC[i]*at*pow(max(dot(R,ld),0.0),36.0);}'+
'if(uPaint>0.5)col+=pl*base*1.4+ps*0.7;else col+=pl*(base*0.9+0.04)+ps*0.35*uRefl;'+
'col=tmap(col);'+
'float up=1.0-smoothstep(0.0,0.75,vW.y);col+=vec3(0.06,0.26,0.95)*up*0.28*uBlue*(0.55+0.45*(1.0-abs(n.y)));'+
'if(uMir>0.5)col*=clamp(1.0+vW.y/1.6,0.0,1.0)*1.15;'+
'col+=uEmis;'+
'gl_FragColor=vec4(col*uAlpha+tmap(add),oa);}';
function shader3(gl,type,src){
  var s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);
  if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s)||'shader');
  return s;
}
function buf3(gl,target,arr){var b=gl.createBuffer();gl.bindBuffer(target,b);gl.bufferData(target,arr,gl.STATIC_DRAW);return b}
/* ---------- Plaques d'immatriculation (format français 52 x 11 cm, texture dessinée dans un canvas) ---------- */
var PLATE={prog:null,tex:null,dirty:true,key:''};
var PLATEPOS=[{x:2.0805,y:0.505,r:0,l:0.90},{x:-1.9215,y:0.42,r:Math.PI,l:0.94}];
var PVS='attribute vec3 aP;attribute vec2 aT;uniform mat4 uVP;uniform mat4 uM;varying vec2 vT;void main(){vT=aT;gl_Position=uVP*uM*vec4(aP,1.0);}';
var PFS='precision mediump float;uniform sampler2D uTex;uniform float uL;varying vec2 vT;void main(){vec3 c=texture2D(uTex,vT).rgb;gl_FragColor=vec4(c*uL,1.0);}';
function rrect(x,X,Y,W,H,R){x.beginPath();x.moveTo(X+R,Y);x.lineTo(X+W-R,Y);x.quadraticCurveTo(X+W,Y,X+W,Y+R);x.lineTo(X+W,Y+H-R);x.quadraticCurveTo(X+W,Y+H,X+W-R,Y+H);x.lineTo(X+R,Y+H);x.quadraticCurveTo(X,Y+H,X,Y+H-R);x.lineTo(X,Y+R);x.quadraticCurveTo(X,Y,X+R,Y);x.closePath()}
function plateCanvas(){
  var W=1024,H=256,LH=W*110/520,c=document.createElement('canvas');c.width=W;c.height=H;
  var x=c.getContext('2d');x.setTransform(1,0,0,H/LH,0,0);
  var txt=String(settings.plateText||'').toUpperCase().slice(0,12),dep=String(settings.plateDept||'').toUpperCase().slice(0,3);
  x.fillStyle='#16181c';rrect(x,0,0,W,LH,22);x.fill();
  x.fillStyle='#f4f5f7';rrect(x,7,7,W-14,LH-14,17);x.fill();
  var bw=92,FB='"Roboto Condensed","sans-serif-condensed","Arial Narrow",Arial,sans-serif';
  [[7,'F'],[W-7-bw,dep]].forEach(function(b,i){
    x.fillStyle='#0b3d91';x.save();rrect(x,b[0],7,bw,LH-14,i?0:17);x.clip();x.fillRect(b[0],7,bw,LH-14);x.restore();
    x.fillStyle='#fff';x.textAlign='center';x.textBaseline='middle';
    if(i===0){
      var cx=b[0]+bw/2,cy=LH*0.34;x.fillStyle='#ffcc00';
      for(var k=0;k<12;k++){var a=k/12*Math.PI*2;x.beginPath();x.arc(cx+Math.cos(a)*24,cy+Math.sin(a)*24,4.2,0,Math.PI*2);x.fill()}
      x.fillStyle='#fff';x.font='bold 66px '+FB;x.fillText('F',cx,LH*0.76);
    }else if(b[1]){x.font='bold 58px '+FB;x.fillText(b[1],b[0]+bw/2,LH*0.74)}
  });
  x.fillStyle='#111317';x.textAlign='center';x.textBaseline='middle';
  x.font='bold 156px '+FB;x.fillText(txt,W/2,LH/2+8,W-2*(bw+34));
  return c;
}
function plateInit(gl){
  var p=gl.createProgram();
  gl.attachShader(p,shader3(gl,gl.VERTEX_SHADER,PVS));gl.attachShader(p,shader3(gl,gl.FRAGMENT_SHADER,PFS));
  gl.bindAttribLocation(p,0,'aP');gl.bindAttribLocation(p,1,'aT');gl.linkProgram(p);
  if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error('plaque');
  PLATE.u={vp:gl.getUniformLocation(p,'uVP'),m:gl.getUniformLocation(p,'uM'),t:gl.getUniformLocation(p,'uTex'),l:gl.getUniformLocation(p,'uL')};
  var w=0.26,h=0.055;
  PLATE.bp=buf3(gl,gl.ARRAY_BUFFER,new Float32Array([0,-h,w,0,-h,-w,0,h,-w,0,h,w]));
  PLATE.bt=buf3(gl,gl.ARRAY_BUFFER,new Float32Array([0,1,1,1,1,0,0,0]));
  PLATE.bi=buf3(gl,gl.ELEMENT_ARRAY_BUFFER,new Uint16Array([0,1,2,0,2,3]));
  PLATE.tex=gl.createTexture();PLATE.dirty=true;PLATE.prog=p;
}
function plateTex(gl){
  var key=(settings.plateText||'')+'|'+(settings.plateDept||'');
  if(!PLATE.dirty&&PLATE.key===key)return;
  PLATE.dirty=false;PLATE.key=key;
  gl.bindTexture(gl.TEXTURE_2D,PLATE.tex);
  gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,gl.RGBA,gl.UNSIGNED_BYTE,plateCanvas());
  gl.generateMipmap(gl.TEXTURE_2D);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR_MIPMAP_LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE);
}
function drawPlates(gl,VP){
  if(!PLATE.prog||settings.plates===false||!GL3.model)return;
  plateTex(gl);
  gl.useProgram(PLATE.prog);
  gl.uniformMatrix4fv(PLATE.u.vp,false,f16(VP));
  gl.activeTexture(gl.TEXTURE0);gl.bindTexture(gl.TEXTURE_2D,PLATE.tex);gl.uniform1i(PLATE.u.t,0);
  gl.bindBuffer(gl.ARRAY_BUFFER,PLATE.bp);gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,0,0);
  gl.bindBuffer(gl.ARRAY_BUFFER,PLATE.bt);gl.enableVertexAttribArray(1);gl.vertexAttribPointer(1,2,gl.FLOAT,false,0,0);
  gl.disableVertexAttribArray(2);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,PLATE.bi);
  PLATEPOS.forEach(function(q){
    var m=M4.mul(M4.tr(q.x,q.y,0),M4.ry(q.r));
    if(Car.gm)m=M4.mul(Car.gm,m);
    gl.uniformMatrix4fv(PLATE.u.m,false,f16(m));
    gl.uniform1f(PLATE.u.l,q.l);
    gl.drawElements(gl.TRIANGLES,6,gl.UNSIGNED_SHORT,0);
  });
  gl.useProgram(GL3.prog);
}
/* ---------- visionneuse autonome ---------- */
var V={hlAcc:[[0,0,0,0],[0,0,0,0]],hl:null,halos:null,flash:null,head:0,tail:0,cine:null,pendingCine:null,cv:null,gl:null,prog:null,u:null,yaw:-0.75,pitch:0.20,dist:6.4,vy:0,drag:null,idle:99,last:0,raf:0,paint:[24,42,126],visible:true,ready:false};
function finishN(g){var p=g.p,ix=g.i,n=new Array(p.length).fill(0),k;for(k=0;k<ix.length;k+=3){var a=ix[k]*3,b=ix[k+1]*3,c=ix[k+2]*3,ux=p[b]-p[a],uy=p[b+1]-p[a+1],uz=p[b+2]-p[a+2],vx=p[c]-p[a],vy=p[c+1]-p[a+1],vz=p[c+2]-p[a+2],nx=uy*vz-uz*vy,ny=uz*vx-ux*vz,nz=ux*vy-uy*vx;[a,b,c].forEach(function(q){n[q]+=nx;n[q+1]+=ny;n[q+2]+=nz})}for(k=0;k<n.length;k+=3){var l=Math.hypot(n[k],n[k+1],n[k+2])||1;n[k]/=l;n[k+1]/=l;n[k+2]/=l}g.n=n;return g}
function upload(gl,g){return {bp:buf3(gl,gl.ARRAY_BUFFER,new Float32Array(g.p)),bn:buf3(gl,gl.ARRAY_BUFFER,new Float32Array(g.n)),bc:null,bi:buf3(gl,gl.ELEMENT_ARRAY_BUFFER,new Uint16Array(g.i)),cnt:g.i.length,line:false}}
function load(buf){
  var gl=V.gl,u8=new Uint8Array(buf),hl=new DataView(buf).getUint32(0,true),hs='',i;
  for(i=0;i<hl;i++)hs+=String.fromCharCode(u8[4+i]);
  var H=JSON.parse(hs),sh=H.shift,rq=H.rq;
  H.pieces.forEach(function(p){
    var pos=new Int16Array(buf,sh+p.op,p.n*3),nor=new Int8Array(buf,sh+p.on,p.n*3),idx=new Uint16Array(buf,sh+p.oi,p.c);
    var P=new Float32Array(p.n*3),N=new Float32Array(p.n*3),k;
    for(k=0;k<P.length;k++){P[k]=pos[k]/rq;N[k]=nor[k]/127}
    if(p.r==='head'){for(k=0;k<P.length;k+=3){var sd=P[k+2]<0?0:1,a_=V.hlAcc[sd];a_[0]+=P[k];a_[1]+=P[k+1];a_[2]+=P[k+2];a_[3]++}}
    var m=H.mats[p.m];
    var PV=H.piv,wm=null;
    if(PV&&p.g.charAt(0)==='w'&&p.g.charAt(1)==='F'&&PV[p.g]&&PV[p.g].length>2)wm=M4.pivot(PV[p.g][0],PV[p.g][1],PV[p.g][2],M4.ry((PV.steer||16)*Math.PI/180));
    GL3.parts.push({g:{bp:buf3(gl,gl.ARRAY_BUFFER,P),bn:buf3(gl,gl.ARRAY_BUFFER,N),bc:null,bi:buf3(gl,gl.ELEMENT_ARRAY_BUFFER,idx),cnt:p.c},col:m.col,refl:m.refl,shin:m.shin,alpha:m.alpha,paint:m.role==='paint',m:wm,role:p.r||'',grp:p.g});
    if(PV)GL3.piv=PV;
  });
  [[2.064,0.505],[-1.905,0.42]].forEach(function(q){GL3.parts.push({g:upload(gl,finishN(gBox(q[0],q[1],0,0.031,0.122,0.534))),col:[0.02,0.02,0.025],refl:0.1,shin:20,alpha:1})});
  var sg={p:[-3.2,0.003,-2,3.2,0.003,-2,3.2,0.003,2,-3.2,0.003,2],i:[0,2,1,0,3,2],n:[0,1,0,0,1,0,0,1,0,0,1,0]};
  GL3.parts.push({g:upload(gl,sg),col:[0,0,0],refl:0,shin:1,alpha:1,shadow:true});
  GL3.model=true;
  V.hl=V.hlAcc.filter(function(a){return a[3]>0}).map(function(a){return [a[0]/a[3]+0.04,a[1]/a[3],a[2]/a[3]]});
}
/* halo lumineux devant chaque phare (calque au-dessus du canvas) */
function halos(VP,eye,cw,ch){
  var cv=V.cv,par=cv&&cv.parentNode;if(!par||!V.hl)return;
  if(!V.halos||V.halos[0].parentNode!==par){
    if(V.halos)V.halos.forEach(function(h){if(h.parentNode)h.parentNode.removeChild(h)});
    V.halos=V.hl.map(function(){var d=document.createElement('div');d.className='hl-halo';par.appendChild(d);return d});
  }
  var el=Math.hypot(eye[0],eye[1],eye[2])||1,front=Math.max(0,Math.min(1,(eye[0]/el+0.15)/0.45));
  var I=V.head*front,ox=cv.offsetLeft,oy=cv.offsetTop,sz=Math.max(60,cw*0.32);
  V.hl.forEach(function(q,i){
    var h=V.halos[i],m=VP,x=q[0],y=q[1],z=q[2];
    var w=m[3]*x+m[7]*y+m[11]*z+m[15];
    if(I<0.02||w<=0){h.style.opacity='0';return}
    var nx=(m[0]*x+m[4]*y+m[8]*z+m[12])/w,ny=(m[1]*x+m[5]*y+m[9]*z+m[13])/w;
    h.style.width=h.style.height=sz+'px';
    h.style.transform='translate('+(ox+(nx*0.5+0.5)*cw-sz/2).toFixed(1)+'px,'+(oy+(0.5-ny*0.5)*ch-sz/2).toFixed(1)+'px)';
    h.style.opacity=I.toFixed(2);
  });
}
function init(cv){
  var gl=cv.getContext('webgl',{antialias:true,alpha:true,premultipliedAlpha:true});
  if(!gl)throw new Error('WebGL indisponible');
  var prog=gl.createProgram();
  gl.attachShader(prog,shader3(gl,gl.VERTEX_SHADER,VS3));gl.attachShader(prog,shader3(gl,gl.FRAGMENT_SHADER,FS3));
  gl.bindAttribLocation(prog,0,'aP');gl.bindAttribLocation(prog,1,'aN');gl.bindAttribLocation(prog,2,'aC');gl.linkProgram(prog);
  if(!gl.getProgramParameter(prog,gl.LINK_STATUS))throw new Error('link');
  var u={};['uVP','uM','uColor','uEye','uEmis','uMir','uBlue','uRefl','uShin','uShadow','uLine','uAlpha','uGlow','uPaint','uPL','uPC'].forEach(function(n){u[n]=gl.getUniformLocation(prog,n)});
  V.gl=gl;V.prog=prog;V.u=u;GL3.prog=prog;
  gl.enable(gl.DEPTH_TEST);gl.enable(gl.BLEND);gl.blendFunc(gl.ONE,gl.ONE_MINUS_SRC_ALPHA);
  try{plateInit(gl)}catch(e){PLATE.prog=null}
}
var F3a=new Float32Array(3),F3c=new Float32Array(3),F3e=new Float32Array(3),NOEM=new Float32Array(3),Z12=new Float32Array(12);
/* ouverture des portes et du hayon : 0 = fermé, 1 = ouvert ; portes avant, puis arrière, puis hayon */
var DOOR={v:0,from:0,to:0,t0:0,dur:1.25},DM={};
var DOPEN={fl:[-65,0],fr:[65,0],rl:[-62,.14],rr:[62,.14],tg:[-78,.28]};
function doorEase(k,open){return open?1-Math.pow(1-k,3)*(1-k*.0):k<.5?4*k*k*k:1-Math.pow(-2*k+2,3)/2}
function doorUpdate(now){
  var P=GL3.piv;DM={};if(!P||V.cine)return;
  var T=(now-DOOR.t0)/1000,open=DOOR.to>DOOR.from;
  Object.keys(DOPEN).forEach(function(g){
    var a=DOPEN[g],k=DOOR.t0?Math.max(0,Math.min(1,(T-(open?a[1]:.28-a[1]))/DOOR.dur)):1,e=doorEase(k,open),v=DOOR.from+(DOOR.to-DOOR.from)*e;
    if(v<=0.001)return;var ang=a[0]*v*Math.PI/180,pv=P[g];if(!pv)return;
    DM[g]=g==='tg'?M4.pivot(pv[0],pv[1],pv[2],M4.rz(ang)):M4.pivot(pv[0],0,pv[1],M4.ry(ang));
  });
  DOOR.v=(DOOR.t0&&T<DOOR.dur+.3)?.5:DOOR.to;
}
function frame(now){
  V.raf=0;
  var gl=V.gl,cv=V.cv;if(!gl||!V.ready)return;
  var dt=Math.min(0.1,((now-V.last)/1000)||0.016);V.last=now;
  V.idle+=dt;
  /* animation d'ouverture : la caméra tourne autour de la voiture, feux arrière puis appel de phares */
  if(V.cine){
    var C=V.cine,tc=(now-C.t0)/1000,k=Math.min(1,tc/C.move),e=k<.5?4*k*k*k:1-Math.pow(-2*k+2,3)/2;
    V.yaw=C.y0+(C.y1-C.y0)*e;V.pitch=C.p0+(C.p1-C.p0)*e;V.dist=C.d0+(C.d1-C.d0)*e;V.vy=0;V.idle=0;
    V.tail=tc>0.55?Math.min(1,(tc-0.55)/0.25):0;
    V.head=tc<0.95?0:tc<1.07?1:tc<1.2?0.08:tc<1.32?1:1;
    if(tc>=C.dur){var res=C.res;V.cine=null;DOOR.from=DOOR.to;DOOR.t0=0;res&&res()}
  }
  /* appel de phares : deux éclats, puis les feux s'éteignent */
  if(V.flash){
    var tf=(now-V.flash.t0)/1000;
    V.head=tf<0.35?0:tf<0.6?1:tf<0.8?0:tf<1.05?1:tf<1.4?Math.max(0,1-(tf-1.05)/0.35):0;
    V.tail=tf<1.4?Math.max(0,V.flash.tail*(1-tf/1.4)):0;
    if(tf>=1.45){V.flash=null;V.head=0;V.tail=0}
  }
  if(!V.drag&&!V.cine){
    if(Math.abs(V.vy)>0.002){V.yaw+=V.vy;V.vy*=Math.exp(-dt*3.5)}
    else if(V.idle>2.5)V.yaw+=dt*0.22;
  }
  var dpr=Math.min(window.devicePixelRatio||1,2),cw=cv.clientWidth,ch=cv.clientHeight;
  if(!cw||!ch){loop();return}
  var W=Math.round(cw*dpr),H=Math.round(ch*dpr);if(cv.width!==W||cv.height!==H){cv.width=W;cv.height=H}
  doorUpdate(now);
  gl.viewport(0,0,W,H);gl.clearColor(0,0,0,0);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
  var tgt=[0,0.62,0],cp=Math.cos(V.pitch),ang=-V.yaw-0.1,d=V.dist*Math.max(1,1.7/(W/H));
  var eye=[tgt[0]+d*cp*Math.cos(ang),tgt[1]+d*Math.sin(V.pitch),tgt[2]+d*cp*Math.sin(ang)];
  var VP=M4.mul(M4.persp(0.52,W/H,0.5,60),M4.look(eye,tgt)),u=V.u;
  gl.useProgram(V.prog);
  gl.uniformMatrix4fv(u.uVP,false,f16(VP));gl.uniform3fv(u.uEye,f3(F3c,eye));
  gl.uniform1f(u.uGlow,0);gl.uniform1f(u.uMir,0);gl.uniform1f(u.uBlue,0);gl.uniform1f(u.uLine,0);
  gl.uniform3fv(u.uPL,Z12);gl.uniform3fv(u.uPC,Z12);gl.uniform3fv(u.uEmis,NOEM);
  var paint=[V.paint[0]/255,V.paint[1]/255,V.paint[2]/255];
  function draw(o){
    var g=o.g,m=(o.grp&&DM[o.grp])||o.m||M4.id();
    gl.uniformMatrix4fv(u.uM,false,f16(m));
    gl.uniform3fv(u.uColor,f3(F3a,o.paint?paint:o.col));
    gl.uniform1f(u.uRefl,o.paint?0.92:o.refl);gl.uniform1f(u.uShin,o.paint?150:o.shin);
    var eh=o.role==='head'?V.head:0,et=o.role==='tail'?V.tail:0;
    if(eh>0)gl.uniform3fv(u.uEmis,f3(F3e,[1.7*eh,1.7*eh,1.85*eh]));else if(et>0)gl.uniform3fv(u.uEmis,f3(F3e,[0.55*et,0.03*et,0.02*et]));else gl.uniform3fv(u.uEmis,NOEM);
    gl.uniform1f(u.uShadow,o.shadow?1:0);gl.uniform1f(u.uPaint,o.paint?1:0);gl.uniform1f(u.uAlpha,o.alpha==null?1:o.alpha);
    gl.bindBuffer(gl.ARRAY_BUFFER,g.bp);gl.enableVertexAttribArray(0);gl.vertexAttribPointer(0,3,gl.FLOAT,false,0,0);
    gl.bindBuffer(gl.ARRAY_BUFFER,g.bn);gl.enableVertexAttribArray(1);gl.vertexAttribPointer(1,3,gl.FLOAT,false,0,0);
    gl.disableVertexAttribArray(2);gl.vertexAttrib3f(2,1,1,1);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,g.bi);gl.drawElements(gl.TRIANGLES,g.cnt,gl.UNSIGNED_SHORT,0);
  }
  gl.depthMask(false);GL3.parts.forEach(function(o){if(o.shadow)draw(o)});gl.depthMask(true);
  GL3.parts.forEach(function(o){if(!o.shadow&&!(o.alpha<1))draw(o)});
  drawPlates(gl,VP);
  halos(VP,eye,cw,ch);
  gl.depthMask(false);GL3.parts.forEach(function(o){if(o.alpha<1)draw(o)});gl.depthMask(true);
  loop();
}
function loop(){if(!V.raf&&V.visible&&!document.hidden){V.raf=requestAnimationFrame(frame)}}
function wire(cv){
  cv.style.touchAction='pan-y';
  cv.addEventListener('pointerdown',function(e){V.drag={x:e.clientX,y:e.clientY,yaw:V.yaw,pitch:V.pitch,lx:e.clientX,id:e.pointerId,h:null};V.vy=0;V.idle=0});
  cv.addEventListener('pointermove',function(e){
    var D=V.drag;if(!D||e.pointerId!==D.id)return;
    var dx=e.clientX-D.x,dy=e.clientY-D.y;
    if(D.h==null&&(Math.abs(dx)>6||Math.abs(dy)>6)){D.h=Math.abs(dx)>=Math.abs(dy);if(D.h)try{cv.setPointerCapture(e.pointerId)}catch(x){}}
    if(!D.h)return;
    V.yaw=D.yaw-dx*0.011;V.vy=-(e.clientX-D.lx)*0.011;D.lx=e.clientX;
    V.pitch=clamp(D.pitch+dy*0.004,0.04,0.6);V.idle=0;
  });
  function up(){if(V.drag){if(!V.drag.h)V.vy=0;V.drag=null;V.idle=0}}
  cv.addEventListener('pointerup',up);cv.addEventListener('pointercancel',up);
  document.addEventListener('visibilitychange',loop);
  if('IntersectionObserver' in window)new IntersectionObserver(function(es){V.visible=es[0].isIntersecting;loop()}).observe(cv);
}
function startCine(){
  if(!V.pendingCine||!V.ready)return;
  var c=V.pendingCine;V.pendingCine=null;
  c.t0=performance.now();V.yaw=c.y0;V.pitch=c.p0;V.dist=c.d0;V.cine=c;
  if(c.onStart)try{c.onStart()}catch(e){}
}
window.Car3D={
  /* animation d'ouverture sur ce canvas ; la promesse se résout à la fin du mouvement de caméra */
  cine:function(cv,opt,onStart){
    return new Promise(function(res){
      V.pendingCine={y0:-3.55,y1:-0.75,p0:0.03,p1:0.18,d0:4.3,d1:5.4,move:2.4,dur:2.7,res:res,onStart:onStart};
      V.head=0;V.tail=0;
      Car3D.mount(cv,opt).then(function(){startCine()},function(){V.pendingCine=null;res(false)});
    });
  },
  lights:function(h,t){V.head=h||0;V.tail=t||0},
  /* ouvre (true) ou ferme (false) les portes et le hayon ; instant = sans animation */
  doors:function(open,instant){var to=open?1:0;if(V.cine)instant=true;if(instant){DOOR.from=to;DOOR.to=to;DOOR.t0=0}else if(DOOR.to!==to){DOOR.from=DOOR.to;DOOR.to=to;DOOR.t0=performance.now()}V.idle=0;loop()},
  flash:function(){V.flash={t0:performance.now(),tail:V.tail||0};loop()},
  mount:function(cv,opt){
    opt=opt||{};
    if(opt.plate!=null)settings.plateText=opt.plate;if(opt.paint)V.paint=opt.paint;
    if(PLATE)PLATE.dirty=true;
    if(V.cv===cv){loop();return Promise.resolve(true)}
    V.cv=cv;V.ready=false;
    try{init(cv)}catch(e){return Promise.reject(e)}
    wire(cv);
    var getBuf=window.SANDERO_CAR?Promise.resolve().then(function(){var t=atob(window.SANDERO_CAR),n=t.length,u=new Uint8Array(n),i;for(i=0;i<n;i++)u[i]=t.charCodeAt(i);window.SANDERO_CAR=null;return u.buffer})
      :fetch(opt.src||'car.bin').then(function(r){if(!r.ok)throw new Error('modèle '+r.status);return r.arrayBuffer()});
    return getBuf.then(function(b){load(b);V.ready=true;V.last=performance.now();startCine();loop();return true});
  },
  set:function(opt){if(opt.plate!=null){settings.plateText=opt.plate;PLATE.dirty=true}if(opt.paint)V.paint=opt.paint}
};

})();
