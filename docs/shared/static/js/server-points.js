function E() {
}
function nt(t) {
  return !!t && (typeof t == "object" || typeof t == "function") && typeof t.then == "function";
}
function q(t) {
  return t();
}
function J() {
  return /* @__PURE__ */ Object.create(null);
}
function A(t) {
  t.forEach(q);
}
function B(t) {
  return typeof t == "function";
}
function rt(t, e) {
  return t != t ? e == e : t !== e || t && typeof t == "object" || typeof t == "function";
}
function lt(t) {
  return Object.keys(t).length === 0;
}
function d(t, e) {
  t.appendChild(e);
}
function b(t, e, n) {
  t.insertBefore(e, n || null);
}
function g(t) {
  t.parentNode && t.parentNode.removeChild(t);
}
function ot(t, e) {
  for (let n = 0; n < t.length; n += 1)
    t[n] && t[n].d(e);
}
function v(t) {
  return document.createElement(t);
}
function m(t) {
  return document.createTextNode(t);
}
function F() {
  return m(" ");
}
function st() {
  return m("");
}
function it(t, e, n) {
  n == null ? t.removeAttribute(e) : t.getAttribute(e) !== n && t.setAttribute(e, n);
}
function ct(t) {
  return Array.from(t.childNodes);
}
function S(t, e) {
  e = "" + e, t.data !== e && (t.data = e);
}
function ut(t) {
  const e = {};
  for (const n of t)
    e[n.name] = n.value;
  return e;
}
let O;
function w(t) {
  O = t;
}
function Z() {
  if (!O)
    throw new Error("Function called outside component initialization");
  return O;
}
function ft(t) {
  Z().$$.on_mount.push(t);
}
const T = [], K = [];
let j = [];
const Q = [], at = /* @__PURE__ */ Promise.resolve();
let R = !1;
function dt() {
  R || (R = !0, at.then(M));
}
function V(t) {
  j.push(t);
}
const z = /* @__PURE__ */ new Set();
let N = 0;
function M() {
  if (N !== 0)
    return;
  const t = O;
  do {
    try {
      for (; N < T.length; ) {
        const e = T[N];
        N++, w(e), ht(e.$$);
      }
    } catch (e) {
      throw T.length = 0, N = 0, e;
    }
    for (w(null), T.length = 0, N = 0; K.length; )
      K.pop()();
    for (let e = 0; e < j.length; e += 1) {
      const n = j[e];
      z.has(n) || (z.add(n), n());
    }
    j.length = 0;
  } while (T.length);
  for (; Q.length; )
    Q.pop()();
  R = !1, z.clear(), w(t);
}
function ht(t) {
  if (t.fragment !== null) {
    t.update(), A(t.before_update);
    const e = t.dirty;
    t.dirty = [-1], t.fragment && t.fragment.p(t.ctx, e), t.after_update.forEach(V);
  }
}
function _t(t) {
  const e = [], n = [];
  j.forEach((r) => t.indexOf(r) === -1 ? e.push(r) : n.push(r)), n.forEach((r) => r()), j = e;
}
const L = /* @__PURE__ */ new Set();
let P;
function pt() {
  P = {
    r: 0,
    c: [],
    p: P
    // parent group
  };
}
function mt() {
  P.r || A(P.c), P = P.p;
}
function tt(t, e) {
  t && t.i && (L.delete(t), t.i(e));
}
function bt(t, e, n, r) {
  if (t && t.o) {
    if (L.has(t))
      return;
    L.add(t), P.c.push(() => {
      L.delete(t), r && (n && t.d(1), r());
    }), t.o(e);
  } else
    r && r();
}
function U(t, e) {
  const n = e.token = {};
  function r(o, l, s, $) {
    if (e.token !== n)
      return;
    e.resolved = $;
    let f = e.ctx;
    s !== void 0 && (f = f.slice(), f[s] = $);
    const i = o && (e.current = o)(f);
    let k = !1;
    e.block && (e.blocks ? e.blocks.forEach((u, h) => {
      h !== l && u && (pt(), bt(u, 1, 1, () => {
        e.blocks[h] === u && (e.blocks[h] = null);
      }), mt());
    }) : e.block.d(1), i.c(), tt(i, 1), i.m(e.mount(), e.anchor), k = !0), e.block = i, e.blocks && (e.blocks[l] = i), k && M();
  }
  if (nt(t)) {
    const o = Z();
    if (t.then((l) => {
      w(o), r(e.then, 1, e.value, l), w(null);
    }, (l) => {
      if (w(o), r(e.catch, 2, e.error, l), w(null), !e.hasCatch)
        throw l;
    }), e.current !== e.pending)
      return r(e.pending, 0), !0;
  } else {
    if (e.current !== e.then)
      return r(e.then, 1, e.value, t), !0;
    e.resolved = t;
  }
}
function gt(t, e, n) {
  const r = e.slice(), { resolved: o } = t;
  t.current === t.then && (r[t.value] = o), t.current === t.catch && (r[t.error] = o), t.block.p(r, n);
}
function $t(t, e, n, r) {
  const { fragment: o, after_update: l } = t.$$;
  o && o.m(e, n), r || V(() => {
    const s = t.$$.on_mount.map(q).filter(B);
    t.$$.on_destroy ? t.$$.on_destroy.push(...s) : A(s), t.$$.on_mount = [];
  }), l.forEach(V);
}
function kt(t, e) {
  const n = t.$$;
  n.fragment !== null && (_t(n.after_update), A(n.on_destroy), n.fragment && n.fragment.d(e), n.on_destroy = n.fragment = null, n.ctx = []);
}
function vt(t, e) {
  t.$$.dirty[0] === -1 && (T.push(t), dt(), t.$$.dirty.fill(0)), t.$$.dirty[e / 31 | 0] |= 1 << e % 31;
}
function yt(t, e, n, r, o, l, s, $ = [-1]) {
  const f = O;
  w(t);
  const i = t.$$ = {
    fragment: null,
    ctx: [],
    // state
    props: l,
    update: E,
    not_equal: o,
    bound: J(),
    // lifecycle
    on_mount: [],
    on_destroy: [],
    on_disconnect: [],
    before_update: [],
    after_update: [],
    context: new Map(e.context || (f ? f.$$.context : [])),
    // everything else
    callbacks: J(),
    dirty: $,
    skip_bound: !1,
    root: e.target || f.$$.root
  };
  s && s(i.root);
  let k = !1;
  if (i.ctx = n ? n(t, e.props || {}, (u, h, ...G) => {
    const C = G.length ? G[0] : h;
    return i.ctx && o(i.ctx[u], i.ctx[u] = C) && (!i.skip_bound && i.bound[u] && i.bound[u](C), k && vt(t, u)), h;
  }) : [], i.update(), k = !0, A(i.before_update), i.fragment = r ? r(i.ctx) : !1, e.target) {
    if (e.hydrate) {
      const u = ct(e.target);
      i.fragment && i.fragment.l(u), u.forEach(g);
    } else
      i.fragment && i.fragment.c();
    e.intro && tt(t.$$.fragment), $t(t, e.target, e.anchor, e.customElement), M();
  }
  w(f);
}
let et;
typeof HTMLElement == "function" && (et = class extends HTMLElement {
  constructor() {
    super(), this.attachShadow({ mode: "open" });
  }
  connectedCallback() {
    const { on_mount: t } = this.$$;
    this.$$.on_disconnect = t.map(q).filter(B);
    for (const e in this.$$.slotted)
      this.appendChild(this.$$.slotted[e]);
  }
  attributeChangedCallback(t, e, n) {
    this[t] = n;
  }
  disconnectedCallback() {
    A(this.$$.on_disconnect);
  }
  $destroy() {
    kt(this, 1), this.$destroy = E;
  }
  $on(t, e) {
    if (!B(e))
      return E;
    const n = this.$$.callbacks[t] || (this.$$.callbacks[t] = []);
    return n.push(e), () => {
      const r = n.indexOf(e);
      r !== -1 && n.splice(r, 1);
    };
  }
  $set(t) {
    this.$$set && !lt(t) && (this.$$.skip_bound = !0, this.$$set(t), this.$$.skip_bound = !1);
  }
});
function W(t, e, n) {
  const r = t.slice();
  return r[4] = e[n], r;
}
function wt(t) {
  let e, n, r = (
    /*error*/
    t[7].message + ""
  ), o;
  return {
    c() {
      e = v("p"), n = m("Metrics error: "), o = m(r);
    },
    m(l, s) {
      b(l, e, s), d(e, n), d(e, o);
    },
    p(l, s) {
      s & /*metrics*/
      2 && r !== (r = /*error*/
      l[7].message + "") && S(o, r);
    },
    d(l) {
      l && g(e);
    }
  };
}
function Ct(t) {
  let e, n, r = (
    /*mets*/
    t[3].Global.Points + ""
  ), o, l = (
    /*mets*/
    t[3].PointSymbol + ""
  ), s, $, f, i, k, u, h, G, C, H, I, p = (
    /*verbose*/
    t[0] && X(t)
  ), x = (
    /*mets*/
    t[3].TopCCs
  ), _ = [];
  for (let c = 0; c < x.length; c += 1)
    _[c] = Y(W(t, x, c));
  return {
    c() {
      e = v("p"), n = m("Global points "), o = m(r), s = m(l), $ = F(), f = v("table"), i = v("thead"), k = v("tr"), u = v("th"), h = m(`Top Countries
            `), p && p.c(), G = F(), C = v("tbody");
      for (let c = 0; c < _.length; c += 1)
        _[c].c();
      H = F(), I = st(), it(u, "colspan", "2");
    },
    m(c, y) {
      b(c, e, y), d(e, n), d(e, o), d(e, s), b(c, $, y), b(c, f, y), d(f, i), d(i, k), d(k, u), d(u, h), p && p.m(u, null), d(f, G), d(f, C);
      for (let a = 0; a < _.length; a += 1)
        _[a] && _[a].m(C, null);
      b(c, H, y), b(c, I, y);
    },
    p(c, y) {
      if (y & /*metrics*/
      2 && r !== (r = /*mets*/
      c[3].Global.Points + "") && S(o, r), y & /*metrics*/
      2 && l !== (l = /*mets*/
      c[3].PointSymbol + "") && S(s, l), /*verbose*/
      c[0] ? p ? p.p(c, y) : (p = X(c), p.c(), p.m(u, null)) : p && (p.d(1), p = null), y & /*metrics*/
      2) {
        x = /*mets*/
        c[3].TopCCs;
        let a;
        for (a = 0; a < x.length; a += 1) {
          const D = W(c, x, a);
          _[a] ? _[a].p(D, y) : (_[a] = Y(D), _[a].c(), _[a].m(C, null));
        }
        for (; a < _.length; a += 1)
          _[a].d(1);
        _.length = x.length;
      }
    },
    d(c) {
      c && g(e), c && g($), c && g(f), p && p.d(), ot(_, c), c && g(H), c && g(I);
    }
  };
}
function X(t) {
  let e, n = (
    /*mets*/
    t[3].ServerIP + ""
  ), r, o;
  return {
    c() {
      e = m("("), r = m(n), o = m(")");
    },
    m(l, s) {
      b(l, e, s), b(l, r, s), b(l, o, s);
    },
    p(l, s) {
      s & /*metrics*/
      2 && n !== (n = /*mets*/
      l[3].ServerIP + "") && S(r, n);
    },
    d(l) {
      l && g(e), l && g(r), l && g(o);
    }
  };
}
function Y(t) {
  let e, n, r = (
    /*c*/
    t[4].Name + ""
  ), o, l, s = (
    /*c*/
    t[4].Points + ""
  ), $, f = (
    /*mets*/
    t[3].PointSymbol + ""
  ), i, k;
  return {
    c() {
      e = v("tr"), n = v("td"), o = m(r), l = v("td"), $ = m(s), i = m(f), k = F();
    },
    m(u, h) {
      b(u, e, h), d(e, n), d(n, o), d(e, l), d(l, $), d(l, i), d(e, k);
    },
    p(u, h) {
      h & /*metrics*/
      2 && r !== (r = /*c*/
      u[4].Name + "") && S(o, r), h & /*metrics*/
      2 && s !== (s = /*c*/
      u[4].Points + "") && S($, s), h & /*metrics*/
      2 && f !== (f = /*mets*/
      u[3].PointSymbol + "") && S(i, f);
    },
    d(u) {
      u && g(e);
    }
  };
}
function Pt(t) {
  let e;
  return {
    c() {
      e = v("p"), e.textContent = "Loading metrics";
    },
    m(n, r) {
      b(n, e, r);
    },
    p: E,
    d(n) {
      n && g(e);
    }
  };
}
function Et(t) {
  let e, n, r = {
    ctx: t,
    current: null,
    token: null,
    hasCatch: !0,
    pending: Pt,
    then: Ct,
    catch: wt,
    value: 3,
    error: 7
  };
  return U(n = /*metrics*/
  t[1], r), {
    c() {
      e = v("main"), r.block.c(), this.c = E;
    },
    m(o, l) {
      b(o, e, l), r.block.m(e, r.anchor = null), r.mount = () => e, r.anchor = null;
    },
    p(o, [l]) {
      t = o, r.ctx = t, l & /*metrics*/
      2 && n !== (n = /*metrics*/
      t[1]) && U(n, r) || gt(r, t, l);
    },
    i: E,
    o: E,
    d(o) {
      o && g(e), r.block.d(), r.token = null, r = null;
    }
  };
}
async function St(t) {
  if (t == "")
    throw new Error("missing server IP");
  const e = await fetch(
    // `https://data-api.ntppool.dev/api/server/dns/answers/` + serverIP
    "https://www.ntppool.org/api/data/server/dns/answers/" + t + "?x"
  ), n = await e.json();
  if (e.ok) {
    let r = [], o = {
      ServerIP: t,
      TopCCs: r,
      Global: { Name: "Global", Points: 0 },
      PointSymbol: n.PointSymbol
    };
    for (let l of n.Server) {
      let s = { Name: "", Points: 0 };
      if (l.CC == "") {
        o.Global.Points = l.Points.toFixed(2);
        continue;
      }
      if (s.Name = l.CC, s.Points = l.Points.toFixed(3), (r.length < 2 || l.Count > 5) && r.push(s), r.length >= 5)
        break;
    }
    return o;
  } else
    throw new Error(e.status + " " + e.statusText);
}
function xt(t, e, n) {
  let { serverip: r = "" } = e, { verbose: o = !1 } = e, l = new Promise(() => {
  });
  return ft(() => {
    n(1, l = St(r));
  }), t.$$set = (s) => {
    "serverip" in s && n(2, r = s.serverip), "verbose" in s && n(0, o = s.verbose);
  }, [o, l, r];
}
class Nt extends et {
  constructor(e) {
    super(), yt(
      this,
      {
        target: this.shadowRoot,
        props: ut(this.attributes),
        customElement: !0
      },
      xt,
      Et,
      rt,
      { serverip: 2, verbose: 0 },
      null
    ), e && (e.target && b(e.target, this, e.anchor), e.props && (this.$set(e.props), M()));
  }
  static get observedAttributes() {
    return ["serverip", "verbose"];
  }
  get serverip() {
    return this.$$.ctx[2];
  }
  set serverip(e) {
    this.$$set({ serverip: e }), M();
  }
  get verbose() {
    return this.$$.ctx[0];
  }
  set verbose(e) {
    this.$$set({ verbose: e }), M();
  }
}
customElements.define("server-points", Nt);
