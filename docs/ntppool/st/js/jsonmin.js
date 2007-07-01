// Copyright (c) 2005 JSON.org

var JSON={copyright:'(c)2005 JSON.org',license:'http://www.crockford.com/JSON/license.html',stringify:function(v){var a=[];function e(s){a[a.length]=s;}
function g(x){var c,i,l,v;switch(typeof x){case'object':if(x){if(x instanceof Array){e('[');l=a.length;for(i=0;i<x.length;i+=1){v=x[i];if(typeof v!='undefined'&&typeof v!='function'){if(l<a.length){e(',');}
g(v);}}
e(']');return;}else if(typeof x.valueOf=='function'){e('{');l=a.length;for(i in x){v=x[i];if(typeof v!='undefined'&&typeof v!='function'&&(!v||typeof v!='object'||typeof v.valueOf=='function')){if(l<a.length){e(',');}
g(i);e(':');g(v);}}
return e('}');}}
e('null');return;case'number':e(isFinite(x)?+x:'null');return;case'string':l=x.length;e('"');for(i=0;i<l;i+=1){c=x.charAt(i);if(c>=' '){if(c=='\\'||c=='"'){e('\\');}
e(c);}else{switch(c){case'\b':e('\\b');break;case'\f':e('\\f');break;case'\n':e('\\n');break;case'\r':e('\\r');break;case'\t':e('\\t');break;default:c=c.charCodeAt();e('\\u00'+Math.floor(c/16).toString(16)+
(c%16).toString(16));}}}
e('"');return;case'boolean':e(String(x));return;default:e('null');return;}}
g(v);return a.join('');},parse:function(text){return(/^(\s+|[,:{}\[\]]|"(\\["\\\/bfnrtu]|[^\x00-\x1f"\\]+)*"|-?\d+(\.\d*)?([eE][+-]?\d+)?|true|false|null)+$/.test(text))&&eval('('+text+')');}};