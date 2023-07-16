function v() {
}
function Q(t) {
  return !!t && (typeof t == "object" || typeof t == "function") && typeof t.then == "function";
}
function F(t) {
  return t();
}
function L() {
  return /* @__PURE__ */ Object.create(null);
}
function S(t) {
  t.forEach(F);
}
function x(t) {
  return typeof t == "function";
}
function U(t, e) {
  return t != t ? e == e : t !== e || t && typeof t == "object" || typeof t == "function";
}
function W(t) {
  return Object.keys(t).length === 0;
}
function _(t, e) {
  t.appendChild(e);
}
function m(t, e, n) {
  t.insertBefore(e, n || null);
}
function b(t) {
  t.parentNode && t.parentNode.removeChild(t);
}
function X(t, e) {
  for (let n = 0; n < t.length; n += 1)
    t[n] && t[n].d(e);
}
function g(t) {
  return document.createElement(t);
}
function p(t) {
  return document.createTextNode(t);
}
function j() {
  return p(" ");
}
function Y() {
  return p("");
}
function Z(t, e, n) {
  n == null ? t.removeAttribute(e) : t.getAttribute(e) !== n && t.setAttribute(e, n);
}
function tt(t) {
  return Array.from(t.childNodes);
}
function y(t, e) {
  e = "" + e, t.data !== e && (t.data = e);
}
function et(t) {
  const e = {};
  for (const n of t)
    e[n.name] = n.value;
  return e;
}
let T;
function $(t) {
  T = t;
}
function D() {
  if (!T)
    throw new Error("Function called outside component initialization");
  return T;
}
function nt(t) {
  D().$$.on_mount.push(t);
}
const w = [], H = [];
let P = [];
const I = [], rt = /* @__PURE__ */ Promise.resolve();
let A = !1;
function lt() {
  A || (A = !0, rt.then(E));
}
function O(t) {
  P.push(t);
}
const M = /* @__PURE__ */ new Set();
let C = 0;
function E() {
  if (C !== 0)
    return;
  const t = T;
  do {
    try {
      for (; C < w.length; ) {
        const e = w[C];
        C++, $(e), ot(e.$$);
      }
    } catch (e) {
      throw w.length = 0, C = 0, e;
    }
    for ($(null), w.length = 0, C = 0; H.length; )
      H.pop()();
    for (let e = 0; e < P.length; e += 1) {
      const n = P[e];
      M.has(n) || (M.add(n), n());
    }
    P.length = 0;
  } while (w.length);
  for (; I.length; )
    I.pop()();
  A = !1, M.clear(), $(t);
}
function ot(t) {
  if (t.fragment !== null) {
    t.update(), S(t.before_update);
    const e = t.dirty;
    t.dirty = [-1], t.fragment && t.fragment.p(t.ctx, e), t.after_update.forEach(O);
  }
}
function st(t) {
  const e = [], n = [];
  P.forEach((r) => t.indexOf(r) === -1 ? e.push(r) : n.push(r)), n.forEach((r) => r()), P = e;
}
const G = /* @__PURE__ */ new Set();
let k;
function it() {
  k = {
    r: 0,
    c: [],
    p: k
    // parent group
  };
}
function ct() {
  k.r || S(k.c), k = k.p;
}
function J(t, e) {
  t && t.i && (G.delete(t), t.i(e));
}
function ut(t, e, n, r) {
  if (t && t.o) {
    if (G.has(t))
      return;
    G.add(t), k.c.push(() => {
      G.delete(t), r && (n && t.d(1), r());
    }), t.o(e);
  } else
    r && r();
}
function z(t, e) {
  const n = e.token = {};
  function r(s, o, i, h) {
    if (e.token !== n)
      return;
    e.resolved = h;
    let f = e.ctx;
    i !== void 0 && (f = f.slice(), f[i] = h);
    const u = s && (e.current = s)(f);
    let c = !1;
    e.block && (e.blocks ? e.blocks.forEach((l, a) => {
      a !== o && l && (it(), ut(l, 1, 1, () => {
        e.blocks[a] === l && (e.blocks[a] = null);
      }), ct());
    }) : e.block.d(1), u.c(), J(u, 1), u.m(e.mount(), e.anchor), c = !0), e.block = u, e.blocks && (e.blocks[o] = u), c && E();
  }
  if (Q(t)) {
    const s = D();
    if (t.then((o) => {
      $(s), r(e.then, 1, e.value, o), $(null);
    }, (o) => {
      if ($(s), r(e.catch, 2, e.error, o), $(null), !e.hasCatch)
        throw o;
    }), e.current !== e.pending)
      return r(e.pending, 0), !0;
  } else {
    if (e.current !== e.then)
      return r(e.then, 1, e.value, t), !0;
    e.resolved = t;
  }
}
function ft(t, e, n) {
  const r = e.slice(), { resolved: s } = t;
  t.current === t.then && (r[t.value] = s), t.current === t.catch && (r[t.error] = s), t.block.p(r, n);
}
function at(t, e, n, r) {
  const { fragment: s, after_update: o } = t.$$;
  s && s.m(e, n), r || O(() => {
    const i = t.$$.on_mount.map(F).filter(x);
    t.$$.on_destroy ? t.$$.on_destroy.push(...i) : S(i), t.$$.on_mount = [];
  }), o.forEach(O);
}
function dt(t, e) {
  const n = t.$$;
  n.fragment !== null && (st(n.after_update), S(n.on_destroy), n.fragment && n.fragment.d(e), n.on_destroy = n.fragment = null, n.ctx = []);
}
function ht(t, e) {
  t.$$.dirty[0] === -1 && (w.push(t), lt(), t.$$.dirty.fill(0)), t.$$.dirty[e / 31 | 0] |= 1 << e % 31;
}
function _t(t, e, n, r, s, o, i, h = [-1]) {
  const f = T;
  $(t);
  const u = t.$$ = {
    fragment: null,
    ctx: [],
    // state
    props: o,
    update: v,
    not_equal: s,
    bound: L(),
    // lifecycle
    on_mount: [],
    on_destroy: [],
    on_disconnect: [],
    before_update: [],
    after_update: [],
    context: new Map(e.context || (f ? f.$$.context : [])),
    // everything else
    callbacks: L(),
    dirty: h,
    skip_bound: !1,
    root: e.target || f.$$.root
  };
  i && i(u.root);
  let c = !1;
  if (u.ctx = n ? n(t, e.props || {}, (l, a, ...d) => {
    const N = d.length ? d[0] : a;
    return u.ctx && s(u.ctx[l], u.ctx[l] = N) && (!u.skip_bound && u.bound[l] && u.bound[l](N), c && ht(t, l)), a;
  }) : [], u.update(), c = !0, S(u.before_update), u.fragment = r ? r(u.ctx) : !1, e.target) {
    if (e.hydrate) {
      const l = tt(e.target);
      u.fragment && u.fragment.l(l), l.forEach(b);
    } else
      u.fragment && u.fragment.c();
    e.intro && J(t.$$.fragment), at(t, e.target, e.anchor, e.customElement), E();
  }
  $(f);
}
let K;
typeof HTMLElement == "function" && (K = class extends HTMLElement {
  constructor() {
    super(), this.attachShadow({ mode: "open" });
  }
  connectedCallback() {
    const { on_mount: t } = this.$$;
    this.$$.on_disconnect = t.map(F).filter(x);
    for (const e in this.$$.slotted)
      this.appendChild(this.$$.slotted[e]);
  }
  attributeChangedCallback(t, e, n) {
    this[t] = n;
  }
  disconnectedCallback() {
    S(this.$$.on_disconnect);
  }
  $destroy() {
    dt(this, 1), this.$destroy = v;
  }
  $on(t, e) {
    if (!x(e))
      return v;
    const n = this.$$.callbacks[t] || (this.$$.callbacks[t] = []);
    return n.push(e), () => {
      const r = n.indexOf(e);
      r !== -1 && n.splice(r, 1);
    };
  }
  $set(t) {
    this.$$set && !W(t) && (this.$$.skip_bound = !0, this.$$set(t), this.$$.skip_bound = !1);
  }
});
function B(t, e, n) {
  const r = t.slice();
  return r[4] = e[n], r;
}
function pt(t) {
  let e, n, r = (
    /*error*/
    t[7].message + ""
  ), s;
  return {
    c() {
      e = g("p"), n = p("Metrics error: "), s = p(r);
    },
    m(o, i) {
      m(o, e, i), _(e, n), _(e, s);
    },
    p(o, i) {
      i & /*metrics*/
      2 && r !== (r = /*error*/
      o[7].message + "") && y(s, r);
    },
    d(o) {
      o && b(e);
    }
  };
}
function mt(t) {
  let e, n, r = (
    /*mets*/
    t[3].Global.Points + ""
  ), s, o = (
    /*mets*/
    t[3].PointSymbol + ""
  ), i, h, f, u, c = (
    /*mets*/
    t[3].Global.Points > 0 && /*mets*/
    t[3].TopCCs.length > 0 && R(t)
  );
  return {
    c() {
      e = g("p"), n = p("Global points "), s = p(r), i = p(o), h = j(), c && c.c(), f = j(), u = Y();
    },
    m(l, a) {
      m(l, e, a), _(e, n), _(e, s), _(e, i), m(l, h, a), c && c.m(l, a), m(l, f, a), m(l, u, a);
    },
    p(l, a) {
      a & /*metrics*/
      2 && r !== (r = /*mets*/
      l[3].Global.Points + "") && y(s, r), a & /*metrics*/
      2 && o !== (o = /*mets*/
      l[3].PointSymbol + "") && y(i, o), /*mets*/
      l[3].Global.Points > 0 && /*mets*/
      l[3].TopCCs.length > 0 ? c ? c.p(l, a) : (c = R(l), c.c(), c.m(f.parentNode, f)) : c && (c.d(1), c = null);
    },
    d(l) {
      l && b(e), l && b(h), c && c.d(l), l && b(f), l && b(u);
    }
  };
}
function R(t) {
  let e, n, r, s, o, i, h, f = (
    /*verbose*/
    t[0] && V(t)
  ), u = (
    /*mets*/
    t[3].TopCCs
  ), c = [];
  for (let l = 0; l < u.length; l += 1)
    c[l] = q(B(t, u, l));
  return {
    c() {
      e = g("table"), n = g("thead"), r = g("tr"), s = g("th"), o = p(`Top Countries
              `), f && f.c(), i = j(), h = g("tbody");
      for (let l = 0; l < c.length; l += 1)
        c[l].c();
      Z(s, "colspan", "2");
    },
    m(l, a) {
      m(l, e, a), _(e, n), _(n, r), _(r, s), _(s, o), f && f.m(s, null), _(e, i), _(e, h);
      for (let d = 0; d < c.length; d += 1)
        c[d] && c[d].m(h, null);
    },
    p(l, a) {
      if (/*verbose*/
      l[0] ? f ? f.p(l, a) : (f = V(l), f.c(), f.m(s, null)) : f && (f.d(1), f = null), a & /*metrics*/
      2) {
        u = /*mets*/
        l[3].TopCCs;
        let d;
        for (d = 0; d < u.length; d += 1) {
          const N = B(l, u, d);
          c[d] ? c[d].p(N, a) : (c[d] = q(N), c[d].c(), c[d].m(h, null));
        }
        for (; d < c.length; d += 1)
          c[d].d(1);
        c.length = u.length;
      }
    },
    d(l) {
      l && b(e), f && f.d(), X(c, l);
    }
  };
}
function V(t) {
  let e, n = (
    /*mets*/
    t[3].ServerIP + ""
  ), r, s;
  return {
    c() {
      e = p("("), r = p(n), s = p(")");
    },
    m(o, i) {
      m(o, e, i), m(o, r, i), m(o, s, i);
    },
    p(o, i) {
      i & /*metrics*/
      2 && n !== (n = /*mets*/
      o[3].ServerIP + "") && y(r, n);
    },
    d(o) {
      o && b(e), o && b(r), o && b(s);
    }
  };
}
function q(t) {
  let e, n, r = (
    /*c*/
    t[4].Name + ""
  ), s, o, i = (
    /*c*/
    t[4].Points + ""
  ), h, f = (
    /*mets*/
    t[3].PointSymbol + ""
  ), u, c;
  return {
    c() {
      e = g("tr"), n = g("td"), s = p(r), o = g("td"), h = p(i), u = p(f), c = j();
    },
    m(l, a) {
      m(l, e, a), _(e, n), _(n, s), _(e, o), _(o, h), _(o, u), _(e, c);
    },
    p(l, a) {
      a & /*metrics*/
      2 && r !== (r = /*c*/
      l[4].Name + "") && y(s, r), a & /*metrics*/
      2 && i !== (i = /*c*/
      l[4].Points + "") && y(h, i), a & /*metrics*/
      2 && f !== (f = /*mets*/
      l[3].PointSymbol + "") && y(u, f);
    },
    d(l) {
      l && b(e);
    }
  };
}
function bt(t) {
  let e;
  return {
    c() {
      e = g("p"), e.textContent = "Loading metrics";
    },
    m(n, r) {
      m(n, e, r);
    },
    p: v,
    d(n) {
      n && b(e);
    }
  };
}
function gt(t) {
  let e, n, r = {
    ctx: t,
    current: null,
    token: null,
    hasCatch: !0,
    pending: bt,
    then: mt,
    catch: pt,
    value: 3,
    error: 7
  };
  return z(n = /*metrics*/
  t[1], r), {
    c() {
      e = g("main"), r.block.c(), this.c = v;
    },
    m(s, o) {
      m(s, e, o), r.block.m(e, r.anchor = null), r.mount = () => e, r.anchor = null;
    },
    p(s, [o]) {
      t = s, r.ctx = t, o & /*metrics*/
      2 && n !== (n = /*metrics*/
      t[1]) && z(n, r) || ft(r, t, o);
    },
    i: v,
    o: v,
    d(s) {
      s && b(e), r.block.d(), r.token = null, r = null;
    }
  };
}
async function $t(t) {
  if (t == "")
    throw new Error("missing server IP");
  const e = await fetch(
    // `https://data-api.ntppool.dev/api/server/dns/answers/` + serverIP
    "https://www.ntppool.org/api/data/server/dns/answers/" + t
  ), n = await e.json();
  if (e.ok) {
    let r = [], s = {
      ServerIP: t,
      TopCCs: r,
      Global: { Name: "Global", Points: 0 },
      PointSymbol: n.PointSymbol
    };
    for (let o of n.Server) {
      let i = { Name: "", Points: 0 };
      if (o.CC == "") {
        s.Global.Points = o.Points.toFixed(2);
        continue;
      }
      if (i.Name = o.CC, i.Points = o.Points.toFixed(3), (r.length < 2 || o.Count > 5) && r.push(i), r.length >= 5)
        break;
    }
    return s;
  } else
    throw new Error(e.status + " " + e.statusText);
}
function kt(t, e, n) {
  let { serverip: r = "" } = e, { verbose: s = !1 } = e, o = new Promise(() => {
  });
  return nt(() => {
    n(1, o = $t(r));
  }), t.$$set = (i) => {
    "serverip" in i && n(2, r = i.serverip), "verbose" in i && n(0, s = i.verbose);
  }, [s, o, r];
}
class vt extends K {
  constructor(e) {
    super(), _t(
      this,
      {
        target: this.shadowRoot,
        props: et(this.attributes),
        customElement: !0
      },
      kt,
      gt,
      U,
      { serverip: 2, verbose: 0 },
      null
    ), e && (e.target && m(e.target, this, e.anchor), e.props && (this.$set(e.props), E()));
  }
  static get observedAttributes() {
    return ["serverip", "verbose"];
  }
  get serverip() {
    return this.$$.ctx[2];
  }
  set serverip(e) {
    this.$$set({ serverip: e }), E();
  }
  get verbose() {
    return this.$$.ctx[0];
  }
  set verbose(e) {
    this.$$set({ verbose: e }), E();
  }
}
customElements.define("server-points", vt);
//# sourceMappingURL=server-points.js.map
