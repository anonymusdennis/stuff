(window["webpackJsonp"]=window["webpackJsonp"]||[]).push([["graph"],{4057:function(t,e,n){var r=n("23e7"),o=Math.hypot,i=Math.abs,a=Math.sqrt,u=!!o&&o(1/0,NaN)!==1/0;r({target:"Math",stat:!0,forced:u},{hypot:function(t,e){var n,r,o=0,u=0,c=arguments.length,s=0;while(u<c)n=i(arguments[u++]),s<n?(r=s/n,o=o*r*r+1,s=n):n>0?(r=n/s,o+=r*r):o+=n;return s===1/0?1/0:s*a(o)}})},"8b30":function(t,e,n){"use strict";n.r(e);var r=function(){var t=this,e=t.$createElement,n=t._self._c||e;return n("div",{staticStyle:{position:"relative",height:"100%"}},[n("div",{staticClass:"ma-4",staticStyle:{position:"absolute"}},[t.selectedNode?n("tree-entry",{attrs:{node:t.selectedNode,size:"64"}}):t._e()],1),n("svg",{staticStyle:{width:"100%",height:"100%"},attrs:{id:"viz"}})])},o=[],i=n("53ca");n("99af"),n("4de4"),n("7db0"),n("c740"),n("a15b"),n("4057");function a(){var t=1;return function(e,n){var r=Math.floor(20*Math.log(e));return r!==t&&(t=r,!0)}}var u=d3.forceManyBodyReuse().update(a),c=window.innerWidth,s=window.innerHeight,l=null,d=null,f=null,h=null,p=null,g=null;function v(){l=d3.select("#viz"),f=l.append("g"),d=d3.zoom().scaleExtent([.1,4]).on("zoom",(function(){f.attr("transform",d3.event.transform)})),l.call(d),h=f.append("g").attr("class","linksLayer"),p=f.append("g")}function y(t){var e=Math.hypot(t.target.x-t.source.x,t.target.y-t.source.y);return"\n    M".concat(t.source.x,",").concat(t.source.y,"\n    A").concat(e,",").concat(e," 0 0,1 ").concat(t.target.x,",").concat(t.target.y,"\n    ")}function w(t,e,r){f||v(),g&&(g.on("tick",null),g.stop());var o=null;if(r.q){var i=t.nodes.find((function(t){return t.id===r.q}));i&&(o=[i],i.safeDive((function(t){o.find((function(e){return e.id===t.it.id}))||o.push(t.it)}),r.outputs?"outputs":"inputs"))}o||(o=t.nodes.filter((function(t){return t.inputs.length>0||t.outputs.length>0})));for(var a=[],l=0;l<o.length;l++)for(var d=o[l],w=function(t){var e=d.inputs[t],n=o.findIndex((function(t){return t.id===e.it.id}));n>-1&&a.push({source:n,target:l,weight:e.weight,index:a.length})},x=0;x<d.inputs.length;x++)w(x);var k={showLinks:o.length<500,showCurvedLinks:o.length<100,useReuse:o.length>500};function m(t){return Math.sqrt(t)}function b(t,e,n){return(t-e)/(n+1)}function M(e){return m(b(e.complexity,t.minC,t.maxC))}function N(e){return m(b(e.usability,t.minU,t.maxU))}function D(t){return m(m(t.weight))}var L=20,q=parseInt(o.length/9),j=q-L;function C(t){var e=(M(t)+N(t))/2*q+L;return Math.max(L,Math.min(q,e))}function A(t){return c/2+M(t)*j*20-N(t)*j*20}g=d3.forceSimulation(o).force("charge",(k.useReuse?u:d3.forceManyBody()).strength(-2e3)).force("x",d3.forceX(A).strength(1)).force("y",d3.forceY(s/2).strength((function(t){return N(t)+1}))).force("link",d3.forceLink(a).distance(j/2).strength(1)).force("collision",d3.forceCollide().radius(C).strength(.75)).on("tick",E);var I=void 0;h.selectAll("*").remove(),k.showLinks&&(I=k.showCurvedLinks?h.attr("fill","none").selectAll("path").data(a).join("path").attr("stroke-width",1).attr("stroke","#555"):h.attr("stroke","#555").attr("stroke-width",1).selectAll("line").data(a).join("line"),I.each((function(t,e){var n=d3.select(this);t.source.outputs.find((function(e){return e.it.id===t.target.id})).d3node=n,t.target.inputs.find((function(e){return e.it.id===t.source.id})).d3node=n})));var z=p.selectAll("g").data(o).join(B,S);function B(t){var e=t.append("g").style("cursor","pointer");return e.append("circle"),e.append("svg").append("image"),S(e)}function R(t,n){e.$router.push({path:"graph",query:{q:t.id,outputs:n}}).catch((function(t){}))}function S(t){return t.on("click",(function(t){return R(t)})).on("contextmenu",(function(t){d3.event.preventDefault(),R(t,!0)})).select("circle").attr("r",C).attr("stroke-width",(function(t){return 10*N(t)+1})).attr("stroke","#fff").attr("fill",(function(t){return 0===t.inputs.length?"rgba(67, 113, 165, 0.3)":0===t.outputs.length?"rgba(0, 145, 7, 0.4)":"#111"})),t.select("svg").attr("height",(function(t,e){return 2*C(t,e)*.9})).attr("width",(function(t,e){return 2*C(t,e)*.9})).attr("x",(function(t,e){return.9*-C(t,e)})).attr("y",(function(t,e){return.9*-C(t,e)})).attr("viewBox",(function(t){return t.viewBox})).select("image").attr("xlink:href",n("f61d")).attr("image-rendering","pixelated"),t}function E(){I&&(k.showCurvedLinks?I.attr("d",y):I.attr("x1",(function(t){return t.source.x})).attr("y1",(function(t){return t.source.y})).attr("x2",(function(t){return t.target.x})).attr("y2",(function(t){return t.target.y}))),z.attr("transform",(function(t){return"translate(".concat(t.x,",").concat(t.y,")")}))}function O(t,e,n,r){e=e||999999999;var o="inputs"===n,i=0;return t.safeDive((function(t,n,a){var u=1+e-a;i=Math.max(i,u),u!==e&&999999999!==e||t.d3node&&(r?r(t.d3node):t.d3node.attr("stroke-width",3*D(t)/a+1).attr("stroke",o?"#7f7":"#38f"))}),n,null,e),i}function U(t){t.attr("stroke-width",1).attr("stroke","#555")}function $(t){e.selectedNode&&(O(t,null,"inputs",U),O(t,null,"outputs",U))}z.each((function(t,e){t.d3node=d3.select(this)}));var _=null;function J(){var t=O(e.selectedNode,e.selectedDeph,"inputs");if(e.selectedDeph>t){var n=e.selectedDeph-t;n>O(e.selectedNode,n,"outputs")&&clearInterval(_)}e.selectedDeph+=1}function T(t){if(k.showLinks&&$(e.selectedNode),e.selectedNode=t,k.showLinks)e.selectedDeph=1,clearInterval(_),_=setInterval(J,100);else{var n=a.filter((function(e){return e.target===t||e.source===t}));I=h.attr("stroke-width",3).selectAll("line").data(n).join("line").attr("stroke",(function(e){return e.target===t?"#7f7":"#38f"}))}}function G(t){k.showLinks&&($(e.selectedNode),e.selectedDeph=0,clearInterval(_))}z.on("mouseover",T),z.on("mouseout",G);{function H(t){d3.event.sourceEvent.stopPropagation(),d3.event.active||g.alphaTarget(.3).restart(),t.fx=t.x,t.fy=t.y}function P(t){t.fx=d3.event.x,t.fy=d3.event.y}function W(t){d3.event.active||g.alphaTarget(0),t.fx=null,t.fy=null}z.call(d3.drag().on("start",H).on("drag",P).on("end",W))}return z}var x={name:"Graph",data:function(){return{selectedNode:void 0,selectedDeph:0}},props:{graph:{type:Object,required:!0}},beforeRouteUpdate:function(t,e,n){w(this.graph,this,t.query),n()},mounted:function(){"object"==Object(i["a"])(this.graph)&&w(this.graph,this,this.$route.query)}},k=x,m=n("2877"),b=Object(m["a"])(k,r,o,!1,null,null,null);e["default"]=b.exports}}]);
//# sourceMappingURL=graph.e5b5722c.js.map