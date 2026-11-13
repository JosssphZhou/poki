// The island’s own style sheet. It is a string because it goes into a shadow root, and the island measures
// its content as soon as it is built, so the sheet has to be there at once.
const ISLAND_CSS = `
:host{--spring:linear(0,.18 4%,.62 11%,.93 18%,1.06 24%,1.09 29%,1.06 36%,1 48%,.988 58%,1 75%,1)}
*{box-sizing:border-box}button{font:inherit;border:0;cursor:pointer;touch-action:manipulation;color:inherit;padding:0}
#st{position:absolute;inset:0;pointer-events:none;color:#fff;font-size:17px;line-height:1.3;user-select:none;-webkit-user-select:none}
#st button{pointer-events:auto}
.c{position:absolute;top:0;left:50%;opacity:0;visibility:hidden;filter:blur(7px);pointer-events:none;transition:opacity 140ms ease-out,filter 140ms ease-out,visibility 0s 140ms}
.c[data-on]{opacity:1;visibility:visible;filter:none;pointer-events:auto;transition:opacity 260ms ease-out 160ms,filter 260ms ease-out 160ms,visibility 0s}
.btns{display:flex;gap:8px}.btns button{flex:1;height:46px;border-radius:23px;font-size:16px;font-weight:600;text-align:center;transition:scale 150ms ease-out;white-space:nowrap}
.btns .no{background:rgba(255,255,255,.16);color:#fff}.btns .yes{background:#fff;color:#000}.btns button:active{scale:.96}.btns button:focus-visible{outline:2px solid #fff;outline-offset:2px}
.one{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.dim{color:rgba(255,255,255,.64)}
.g{position:relative;display:inline-block;width:20px;height:20px;flex-shrink:0}.g b{position:absolute;display:block;background:currentColor}
.g-orb{animation:spin 1.5s linear infinite}.g-orb b{border-radius:50%}.g-orb b:nth-child(1){width:5.5px;height:5.5px;left:7px;top:1px}.g-orb b:nth-child(2){width:4.5px;height:4.5px;left:2px;bottom:3px;opacity:.8}.g-orb b:nth-child(3){width:3.5px;height:3.5px;right:2px;bottom:4px;opacity:.6}
@keyframes spin{to{transform:rotate(360deg)}}
.g-done svg{width:20px;height:20px;fill:none;stroke:currentColor;stroke-width:2.4;stroke-linecap:round;stroke-linejoin:round;stroke-dasharray:18;stroke-dashoffset:18}@keyframes draw{to{stroke-dashoffset:0}}
.bb{display:block;transform-origin:50% 100%;pointer-events:none;-webkit-user-drag:none}
.mv-hear .bb{animation:m-lean 2.4s ease-in-out infinite}.mv-think .bb{animation:m-tilt 3s ease-in-out infinite}
.mv-tap .bb{animation:m-tap 1s cubic-bezier(.3,.6,.3,1) infinite}.mv-scroll .bb{animation:m-scroll 1.3s ease-in-out infinite}.mv-type .bb{animation:m-type .24s steps(2) infinite}
@keyframes m-lean{50%{transform:rotate(-3deg) translateY(-1.5%)}}@keyframes m-tilt{0%,100%{transform:rotate(-2.5deg)}50%{transform:rotate(2.5deg)}}
@keyframes m-tap{0%,58%,100%{transform:none}72%{transform:translateY(4%) scale(1.04,.95)}}@keyframes m-scroll{0%,100%{transform:none}40%{transform:translateY(-5%)}}@keyframes m-type{50%{transform:translateY(1.8%)}}
/* ================= Ribbon, second pass, after Apple's Siri island. One sheet of clear dark glass hangs around the camera. Listening is a drop with Poki in the middle of it; every other state keeps Poki and the step dots beside the camera and one centred line of words. The hue is one soft band (blue to warm) along the lower edge. ================= */
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
.gl.m-glass{--gp:6px}.gl.m-black{--gp:0px}
.hw{position:absolute;top:11px;left:50%;width:126px;height:37px;margin-left:-63px;border-radius:18.5px;background:#000;pointer-events:none;z-index:4}
.gl{position:absolute;left:50%;top:calc(11px - var(--gp));overflow:hidden;isolation:isolate;pointer-events:auto;color:#fff;--ho:.34;
  transition:width 620ms var(--spring),height 620ms var(--spring),margin-left 620ms var(--spring),border-radius 620ms var(--spring),opacity 260ms ease-out,filter 380ms ease-out,--t1 480ms ease-out,--t2 480ms ease-out,--bl 480ms ease-out,--br 480ms ease-out}
/* it does not pop in: it comes out of the island soft and sharpens, as Siri's does */
.gl[data-k=rest]{opacity:0;filter:blur(9px);pointer-events:none}
@supports (corner-shape:squircle){.gl{corner-shape:superellipse(1.5)}.gl[data-k=rest],.gl[data-k=think]{corner-shape:round}.gl[data-pill]{corner-shape:round}.gl::after,.el{corner-shape:inherit}}
/* the material. Clear enough to see the app through it, darker in the middle where the words sit, and (in Chrome) the rim bends what is behind it. */
.gl.m-glass{--t1:.34;--t2:.7;--bl:5px;--br:.64;background:radial-gradient(125% 135% at 50% 36%,rgba(6,6,9,var(--t2)) 38%,rgba(18,19,27,var(--t1)) 100%);
  -webkit-backdrop-filter:blur(var(--bl)) saturate(1.8) brightness(var(--br));backdrop-filter:blur(var(--bl)) saturate(1.8) brightness(var(--br));
  box-shadow:inset 0 -18px 26px -18px rgba(255,255,255,.24),inset 0 12px 20px -14px rgba(255,255,255,.1),0 20px 44px -14px rgba(0,0,0,.5),0 3px 10px -3px rgba(0,0,0,.22)}
.gl.m-glass.lq{backdrop-filter:url(#lq) blur(var(--bl)) saturate(1.8) brightness(var(--br))}
.gl.m-glass[data-k=listen]{--t1:.26;--t2:.6;--bl:5px;--br:.84}
.gl.m-glass[data-k=think],.gl.m-glass[data-pill]{--t1:.26;--t2:.56;--bl:5px;--br:.9}
.gl.m-glass[data-card]{--t1:.46;--t2:.8;--bl:10px;--br:.56}
/* the rim: a hairline that is brightest along the lower edge */
.gl::after{content:"";position:absolute;z-index:5;inset:0;border-radius:inherit;pointer-events:none;padding:1px;background:linear-gradient(180deg,rgba(255,255,255,.3),rgba(255,255,255,.07) 30%,rgba(255,255,255,.1) 62%,rgba(255,255,255,.6));
  -webkit-mask:linear-gradient(#000 0 0) content-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask:linear-gradient(#000 0 0) content-box exclude,linear-gradient(#000 0 0)}
.el{position:absolute;z-index:5;inset:0;border-radius:inherit;pointer-events:none;padding:1px;opacity:var(--ho);background:linear-gradient(90deg in oklch,var(--c-b1),var(--c-b0l) 34%,var(--c-w0) 66%,var(--c-w1));
  mask:linear-gradient(transparent calc(100% - 22px),#000) intersect,linear-gradient(#000 0 0) content-box exclude,linear-gradient(#000 0 0);transition:opacity 420ms ease-out}
.gl.m-black{background:#000}.gl.m-black::after{background:rgba(255,255,255,.11)}
/* the hue: one soft band, blue on the left and warm on the right. Script draws its top edge, so it can swell with your voice. */
.hue{position:absolute;z-index:1;left:-6%;right:-6%;bottom:-24px;height:110px;pointer-events:none}
.hue{filter:blur(11px) saturate(var(--hs,1.05));opacity:var(--ho);transition:opacity 420ms ease-out}
.hue u{position:absolute;inset:0;background:linear-gradient(90deg in oklch,transparent 3%,var(--c-b1) 20%,var(--c-b0l) 40%,var(--c-w0) 62%,var(--c-w1) 80%,transparent 97%)}
.gl[data-k=listen]{--ho:.5}
.gl[data-k=think],.gl[data-pill]{--ho:.2}
.gl[data-card]{--ho:.46}
.gl[data-k=done]{--ho:.7}
.gl[data-k=fail]{--ho:.3;--hs:.12}
/* Poki. In the middle of the drop while listening; beside the camera, small, the rest of the time. One element, so it travels between the two. */
.pk{position:absolute;z-index:3;left:50%;top:calc(var(--gp) + 37px);width:80px;height:80px;margin-left:-40px;pointer-events:none;transform:translate(-85px,-58.5px) scale(.425);transition:transform 620ms var(--spring),opacity 200ms ease-out}
.gl[data-k=listen] .pk{transform:none}
.pk .bb{width:80px;height:80px}
.pk[data-pop] .bb{animation-delay:0s}.pk[data-pop]{animation:pkpop 420ms var(--spring)}@keyframes pkpop{from{scale:.86}to{scale:1}}
.chip{position:absolute;z-index:3;left:50%;top:var(--gp);width:40px;height:37px;margin-left:66px;pointer-events:none;transition:opacity 200ms ease-out,transform 620ms var(--spring)}
.chip>*{position:absolute;left:50%;top:50%;translate:-50% -50%;opacity:0;scale:.6;transition:opacity 180ms ease-out,scale 320ms var(--spring)}
.chip[data-m=beat] .g-beat,.chip[data-m=hold] .g-hold,.chip[data-m=orb] .g-orb,.chip[data-m=ok] .g-done,.chip[data-m=time] .g-time{opacity:1;scale:1}
.chip[data-m=ok] .g-done svg{animation:draw 380ms ease-out 220ms forwards}
/* working, as a pill: a dot that beats once each time an action starts */
.g-beat{display:block;width:16px;height:16px}
.g-beat b{position:absolute;left:4px;top:4px;width:8px;height:8px;border-radius:50%;background:#fff}
.g-beat::after{content:"";position:absolute;inset:3px;border-radius:50%;box-shadow:0 0 0 1.5px rgba(255,255,255,.8);opacity:0}
.chip[data-hit] .g-beat b{animation:beat 420ms var(--ease)}.chip[data-hit] .g-beat::after{animation:beatring 720ms ease-out}
@keyframes beat{0%{scale:1}35%{scale:1.55}100%{scale:1}}@keyframes beatring{0%{opacity:.8;scale:.7}100%{opacity:0;scale:2.3}}
/* asking: the time left to answer */
.g-time{display:block;width:22px;height:22px}
.g-time svg{display:block;width:22px;height:22px;rotate:-90deg}
.g-time circle{fill:none;stroke-width:2.2}.g-time .tr{stroke:rgba(255,255,255,.2)}.g-time .pr{stroke:#fff;stroke-linecap:round;stroke-dasharray:56.5;transition:stroke-dashoffset 1s linear}
.g-time em{position:absolute;inset:0;display:grid;place-items:center;font-style:normal;font-size:10px;line-height:1;font-weight:600;font-variant-numeric:tabular-nums}
/* working, as a sheet: Stop, right of the camera */
.stop{position:absolute;z-index:3;left:50%;top:calc(var(--gp) + 2.5px);margin-left:69px;width:32px;height:32px;border:0;padding:0;border-radius:50%;background:rgba(255,255,255,.17);cursor:pointer;opacity:0;scale:.6;pointer-events:none;touch-action:manipulation;transition:opacity 180ms ease-out,scale 320ms var(--spring),background-color 150ms ease-out,transform 620ms var(--spring)}
.stop::before{content:"";position:absolute;inset:-6px}
.stop::after{content:"";position:absolute;left:50%;top:50%;width:10px;height:10px;margin:-5px 0 0 -5px;border-radius:2.5px;background:#fff}
.gl[data-stop] .stop{opacity:1;scale:1;pointer-events:auto;transition-delay:160ms}
.gl[data-stop] .stop:active{scale:.96;transition-delay:0s}
@media (hover:hover) and (pointer:fine){.gl:not([data-held]) .stop:hover{background:rgba(255,255,255,.26)}}
/* paused: the same button, now white, offers Resume; the square becomes a triangle */
.stop::after{clip-path:polygon(0 0,100% 0,100% 100%,0 100%);transition:clip-path 240ms var(--ease),background-color 150ms ease-out,translate 240ms var(--ease)}
.gl[data-held] .stop{background:#fff}
.gl[data-held] .stop::after{background:#000;border-radius:1px;clip-path:polygon(8% 0,100% 50%,100% 50%,8% 100%);translate:1px 0}
.gl[data-held]{--ho:.18}
.gl[data-held] .c[data-on]{opacity:0;visibility:hidden;filter:blur(7px);scale:.97;translate:0 5px;pointer-events:none;transition:opacity 150ms ease-out,filter 150ms ease-out,scale 150ms ease-out,translate 150ms ease-out,visibility 0s 150ms}
.gl[data-held]:not([data-shut]) .c.hold{opacity:1;visibility:visible;filter:none;scale:1;translate:0 0;transition:opacity 300ms ease-out 120ms,filter 300ms ease-out 120ms,scale 420ms var(--ease) 120ms,translate 420ms var(--ease) 120ms,visibility 0s}
.g-hold{display:block;width:16px;height:16px}
.g-hold b{position:absolute;top:3px;width:3.5px;height:10px;border-radius:1.75px;background:#fff}.g-hold b:first-child{left:3.5px}.g-hold b:last-child{right:3.5px}
.stop:focus-visible,.gl[data-pill]:focus-visible{outline:2px solid #fff;outline-offset:2px}
.gl[data-pill]{cursor:pointer}
/* the words: they blur out and the next ones blur in, a beat after the sheet starts to move */
.gl .c{z-index:2;text-align:left;scale:.97;translate:0 5px;transition:opacity 150ms ease-out,filter 150ms ease-out,scale 150ms ease-out,translate 150ms ease-out,visibility 0s 150ms}
.gl .c[data-on]{scale:1;translate:0 0;transition:opacity 300ms ease-out 170ms,filter 300ms ease-out 170ms,scale 420ms var(--ease) 170ms,translate 420ms var(--ease) 170ms,visibility 0s}
.cx{padding:calc(var(--gp) + 46px) 60px 0 68px}
.gl[data-shut] .c[data-on]{opacity:0;visibility:hidden;filter:blur(7px);scale:.97;translate:0 5px;pointer-events:none;transition:opacity 150ms ease-out,filter 150ms ease-out,scale 150ms ease-out,translate 150ms ease-out,visibility 0s 150ms}
.cx .line i{font-style:normal;color:rgba(255,255,255,.6)}
.cx .line{margin:0;padding-bottom:26px;font-size:18px;line-height:24px;font-weight:600;letter-spacing:-.012em}
.cdn{padding:calc(var(--gp) + 43px) 14px 14px}
.cdn h5{margin:0 0 0 48px;font-size:20px;line-height:25px;font-weight:600;letter-spacing:-.018em}
.cdn[data-k=ask] h5,.cdn[data-k=ask] p{margin-right:40px}
.cdn p{margin:2px 0 0 48px;font-size:14px;line-height:20px;text-wrap:balance}.cdn p.q{font-size:15px}
.cdn .btns{margin-top:12px}.cdn .btns button{height:44px;border-radius:22px}
.gl.m-glass .cdn .btns .no{background:rgba(255,255,255,.14);box-shadow:inset 0 0 0 1px rgba(255,255,255,.12),inset 0 1px 0 rgba(255,255,255,.22)}
@media (prefers-reduced-motion:reduce){.gl,.gl .c,.gl .c[data-on],.hue,.pk,.stop,.chip,.chip>*{transition-duration:1ms!important;transition-delay:0s!important}.chip[data-m=ok] .g-done svg{stroke-dashoffset:0}}
`;
// Added in frames (?embed=1): no motion, so a frame is a still picture.
const ISLAND_STILL = `*,*::before,*::after{transition-duration:1ms!important;transition-delay:0s!important;animation:none!important}.g-done svg{stroke-dashoffset:0!important}`;
