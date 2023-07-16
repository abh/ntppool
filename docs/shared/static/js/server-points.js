function P() {
}
function Y(t) {
  return !!t && (typeof t == "object" || typeof t == "function") && typeof t.then == "function";
}
function H(t) {
  return t();
}
function I() {
  return /* @__PURE__ */ Object.create(null);
}
function G(t) {
  t.forEach(H);
}
function R(t) {
  return typeof t == "function";
}
function Z(t, e) {
  return t != t ? e == e : t !== e || t && typeof t == "object" || typeof t == "function";
}
function x(t) {
  return Object.keys(t).length === 0;
}
function _(t, e) {
  t.appendChild(e);
}
function g(t, e, n) {
  t.insertBefore(e, n || null);
}
function k(t) {
  t.parentNode && t.parentNode.removeChild(t);
}
function ee(t, e) {
  for (let n = 0; n < t.length; n += 1)
    t[n] && t[n].d(e);
}
function $(t) {
  return document.createElement(t);
}
function b(t) {
  return document.createTextNode(t);
}
function y() {
  return b(" ");
}
function te() {
  return b("");
}
function ne(t, e, n) {
  n == null ? t.removeAttribute(e) : t.getAttribute(e) !== n && t.setAttribute(e, n);
}
function le(t) {
  return Array.from(t.childNodes);
}
function v(t, e) {
  e = "" + e, t.data !== e && (t.data = e);
}
function re(t) {
  const e = {};
  for (const n of t)
    e[n.name] = n.value;
  return e;
}
let j;
function C(t) {
  j = t;
}
function U() {
  if (!j)
    throw new Error("Function called outside component initialization");
  return j;
}
function oe(t) {
  U().$$.on_mount.push(t);
}
const S = [], z = [];
let F = [];
const B = [], ie = /* @__PURE__ */ Promise.resolve();
let O = !1;
function se() {
  O || (O = !0, ie.then(T));
}
function L(t) {
  F.push(t);
}
const A = /* @__PURE__ */ new Set();
let E = 0;
function T() {
  if (E !== 0)
    return;
  const t = j;
  do {
    try {
      for (; E < S.length; ) {
        const e = S[E];
        E++, C(e), ue(e.$$);
      }
    } catch (e) {
      throw S.length = 0, E = 0, e;
    }
    for (C(null), S.length = 0, E = 0; z.length; )
      z.pop()();
    for (let e = 0; e < F.length; e += 1) {
      const n = F[e];
      A.has(n) || (A.add(n), n());
    }
    F.length = 0;
  } while (S.length);
  for (; B.length; )
    B.pop()();
  O = !1, A.clear(), C(t);
}
function ue(t) {
  if (t.fragment !== null) {
    t.update(), G(t.before_update);
    const e = t.dirty;
    t.dirty = [-1], t.fragment && t.fragment.p(t.ctx, e), t.after_update.forEach(L);
  }
}
function ce(t) {
  const e = [], n = [];
  F.forEach((l) => t.indexOf(l) === -1 ? e.push(l) : n.push(l)), n.forEach((l) => l()), F = e;
}
const M = /* @__PURE__ */ new Set();
let w;
function fe() {
  w = {
    r: 0,
    c: [],
    p: w
    // parent group
  };
}
function ae() {
  w.r || G(w.c), w = w.p;
}
function W(t, e) {
  t && t.i && (M.delete(t), t.i(e));
}
function de(t, e, n, l) {
  if (t && t.o) {
    if (M.has(t))
      return;
    M.add(t), w.c.push(() => {
      M.delete(t), l && (n && t.d(1), l());
    }), t.o(e);
  } else
    l && l();
}
function V(t, e) {
  const n = e.token = {};
  function l(i, o, f, p) {
    if (e.token !== n)
      return;
    e.resolved = p;
    let u = e.ctx;
    f !== void 0 && (u = u.slice(), u[f] = p);
    const s = i && (e.current = i)(u);
    let d = !1;
    e.block && (e.blocks ? e.blocks.forEach((r, c) => {
      c !== o && r && (fe(), de(r, 1, 1, () => {
        e.blocks[c] === r && (e.blocks[c] = null);
      }), ae());
    }) : e.block.d(1), s.c(), W(s, 1), s.m(e.mount(), e.anchor), d = !0), e.block = s, e.blocks && (e.blocks[o] = s), d && T();
  }
  if (Y(t)) {
    const i = U();
    if (t.then((o) => {
      C(i), l(e.then, 1, e.value, o), C(null);
    }, (o) => {
      if (C(i), l(e.catch, 2, e.error, o), C(null), !e.hasCatch)
        throw o;
    }), e.current !== e.pending)
      return l(e.pending, 0), !0;
  } else {
    if (e.current !== e.then)
      return l(e.then, 1, e.value, t), !0;
    e.resolved = t;
  }
}
function he(t, e, n) {
  const l = e.slice(), { resolved: i } = t;
  t.current === t.then && (l[t.value] = i), t.current === t.catch && (l[t.error] = i), t.block.p(l, n);
}
function _e(t, e, n, l) {
  const { fragment: i, after_update: o } = t.$$;
  i && i.m(e, n), l || L(() => {
    const f = t.$$.on_mount.map(H).filter(R);
    t.$$.on_destroy ? t.$$.on_destroy.push(...f) : G(f), t.$$.on_mount = [];
  }), o.forEach(L);
}
function pe(t, e) {
  const n = t.$$;
  n.fragment !== null && (ce(n.after_update), G(n.on_destroy), n.fragment && n.fragment.d(e), n.on_destroy = n.fragment = null, n.ctx = []);
}
function me(t, e) {
  t.$$.dirty[0] === -1 && (S.push(t), se(), t.$$.dirty.fill(0)), t.$$.dirty[e / 31 | 0] |= 1 << e % 31;
}
function be(t, e, n, l, i, o, f, p = [-1]) {
  const u = j;
  C(t);
  const s = t.$$ = {
    fragment: null,
    ctx: [],
    // state
    props: o,
    update: P,
    not_equal: i,
    bound: I(),
    // lifecycle
    on_mount: [],
    on_destroy: [],
    on_disconnect: [],
    before_update: [],
    after_update: [],
    context: new Map(e.context || (u ? u.$$.context : [])),
    // everything else
    callbacks: I(),
    dirty: p,
    skip_bound: !1,
    root: e.target || u.$$.root
  };
  f && f(s.root);
  let d = !1;
  if (s.ctx = n ? n(t, e.props || {}, (r, c, ...a) => {
    const h = a.length ? a[0] : c;
    return s.ctx && i(s.ctx[r], s.ctx[r] = h) && (!s.skip_bound && s.bound[r] && s.bound[r](h), d && me(t, r)), c;
  }) : [], s.update(), d = !0, G(s.before_update), s.fragment = l ? l(s.ctx) : !1, e.target) {
    if (e.hydrate) {
      const r = le(e.target);
      s.fragment && s.fragment.l(r), r.forEach(k);
    } else
      s.fragment && s.fragment.c();
    e.intro && W(t.$$.fragment), _e(t, e.target, e.anchor, e.customElement), T();
  }
  C(u);
}
let X;
typeof HTMLElement == "function" && (X = class extends HTMLElement {
  constructor() {
    super(), this.attachShadow({ mode: "open" });
  }
  connectedCallback() {
    const { on_mount: t } = this.$$;
    this.$$.on_disconnect = t.map(H).filter(R);
    for (const e in this.$$.slotted)
      this.appendChild(this.$$.slotted[e]);
  }
  attributeChangedCallback(t, e, n) {
    this[t] = n;
  }
  disconnectedCallback() {
    G(this.$$.on_disconnect);
  }
  $destroy() {
    pe(this, 1), this.$destroy = P;
  }
  $on(t, e) {
    if (!R(e))
      return P;
    const n = this.$$.callbacks[t] || (this.$$.callbacks[t] = []);
    return n.push(e), () => {
      const l = n.indexOf(e);
      l !== -1 && n.splice(l, 1);
    };
  }
  $set(t) {
    this.$$set && !x(t) && (this.$$.skip_bound = !0, this.$$set(t), this.$$.skip_bound = !1);
  }
});
function q(t, e, n) {
  const l = t.slice();
  return l[6] = e[n], l;
}
function ge(t) {
  let e, n, l = (
    /*error*/
    t[9].message + ""
  ), i;
  return {
    c() {
      e = $("p"), n = b("Metrics error: "), i = b(l);
    },
    m(o, f) {
      g(o, e, f), _(e, n), _(e, i);
    },
    p(o, f) {
      f & /*metrics*/
      4 && l !== (l = /*error*/
      o[9].message + "") && v(i, l);
    },
    d(o) {
      o && k(e);
    }
  };
}
function ke(t) {
  let e, n, l = (
    /*mets*/
    t[5].Global.Points.toFixed(
      /*decimals*/
      t[1]
    ) + ""
  ), i, o = (
    /*mets*/
    t[5].PointSymbol + ""
  ), f, p, u, s, d, r = (
    /*mets*/
    t[5].Global.Points > 0 && /*mets*/
    t[5].TopCCs.length > 0 && D(t)
  );
  return {
    c() {
      e = $("p"), n = b("Global points "), i = b(l), f = b(o), p = y(), u = y(), r && r.c(), s = y(), d = te();
    },
    m(c, a) {
      g(c, e, a), _(e, n), _(e, i), _(e, f), _(e, p), g(c, u, a), r && r.m(c, a), g(c, s, a), g(c, d, a);
    },
    p(c, a) {
      a & /*metrics, decimals*/
      6 && l !== (l = /*mets*/
      c[5].Global.Points.toFixed(
        /*decimals*/
        c[1]
      ) + "") && v(i, l), a & /*metrics*/
      4 && o !== (o = /*mets*/
      c[5].PointSymbol + "") && v(f, o), /*mets*/
      c[5].Global.Points > 0 && /*mets*/
      c[5].TopCCs.length > 0 ? r ? r.p(c, a) : (r = D(c), r.c(), r.m(s.parentNode, s)) : r && (r.d(1), r = null);
    },
    d(c) {
      c && k(e), c && k(u), r && r.d(c), c && k(s), c && k(d);
    }
  };
}
function D(t) {
  let e, n, l, i, o, f, p, u = (
    /*verbose*/
    t[0] && J(t)
  ), s = (
    /*mets*/
    t[5].TopCCs
  ), d = [];
  for (let r = 0; r < s.length; r += 1)
    d[r] = Q(q(t, s, r));
  return {
    c() {
      e = $("table"), n = $("thead"), l = $("tr"), i = $("th"), o = b(`Top Countries
              `), u && u.c(), f = y(), p = $("tbody");
      for (let r = 0; r < d.length; r += 1)
        d[r].c();
      ne(i, "colspan", "3");
    },
    m(r, c) {
      g(r, e, c), _(e, n), _(n, l), _(l, i), _(i, o), u && u.m(i, null), _(e, f), _(e, p);
      for (let a = 0; a < d.length; a += 1)
        d[a] && d[a].m(p, null);
    },
    p(r, c) {
      if (/*verbose*/
      r[0] ? u ? u.p(r, c) : (u = J(r), u.c(), u.m(i, null)) : u && (u.d(1), u = null), c & /*metrics, decimals*/
      6) {
        s = /*mets*/
        r[5].TopCCs;
        let a;
        for (a = 0; a < s.length; a += 1) {
          const h = q(r, s, a);
          d[a] ? d[a].p(h, c) : (d[a] = Q(h), d[a].c(), d[a].m(p, null));
        }
        for (; a < d.length; a += 1)
          d[a].d(1);
        d.length = s.length;
      }
    },
    d(r) {
      r && k(e), u && u.d(), ee(d, r);
    }
  };
}
function J(t) {
  let e, n = (
    /*mets*/
    t[5].ServerIP + ""
  ), l, i;
  return {
    c() {
      e = b("("), l = b(n), i = b(")");
    },
    m(o, f) {
      g(o, e, f), g(o, l, f), g(o, i, f);
    },
    p(o, f) {
      f & /*metrics*/
      4 && n !== (n = /*mets*/
      o[5].ServerIP + "") && v(l, n);
    },
    d(o) {
      o && k(e), o && k(l), o && k(i);
    }
  };
}
function K(t) {
  let e, n = (
    /*c*/
    t[6].Netspeed.toFixed(
      /*decimals*/
      t[1]
    ) + ""
  ), l, i, o = (
    /*mets*/
    t[5].PointSymbol + ""
  ), f, p, u = (
    /*c*/
    t[6].Ratio.toFixed(2) + ""
  ), s, d;
  return {
    c() {
      e = $("td"), l = b(n), i = y(), f = b(o), p = b(" ("), s = b(u), d = b("x)");
    },
    m(r, c) {
      g(r, e, c), _(e, l), _(e, i), _(e, f), _(e, p), _(e, s), _(e, d);
    },
    p(r, c) {
      c & /*metrics, decimals*/
      6 && n !== (n = /*c*/
      r[6].Netspeed.toFixed(
        /*decimals*/
        r[1]
      ) + "") && v(l, n), c & /*metrics*/
      4 && o !== (o = /*mets*/
      r[5].PointSymbol + "") && v(f, o), c & /*metrics*/
      4 && u !== (u = /*c*/
      r[6].Ratio.toFixed(2) + "") && v(s, u);
    },
    d(r) {
      r && k(e);
    }
  };
}
function Q(t) {
  let e, n, l = (
    /*c*/
    t[6].Name + ""
  ), i, o, f, p = (
    /*c*/
    t[6].Points.toFixed(
      /*decimals*/
      t[1]
    ) + ""
  ), u, s, d = (
    /*mets*/
    t[5].PointSymbol + ""
  ), r, c, a, h = (
    /*c*/
    t[6].Netspeed > 0 && K(t)
  );
  return {
    c() {
      e = $("tr"), n = $("td"), i = b(l), o = y(), f = $("td"), u = b(p), s = y(), r = b(d), c = y(), h && h.c(), a = y();
    },
    m(m, N) {
      g(m, e, N), _(e, n), _(n, i), _(e, o), _(e, f), _(f, u), _(f, s), _(f, r), _(e, c), h && h.m(e, null), _(e, a);
    },
    p(m, N) {
      N & /*metrics*/
      4 && l !== (l = /*c*/
      m[6].Name + "") && v(i, l), N & /*metrics, decimals*/
      6 && p !== (p = /*c*/
      m[6].Points.toFixed(
        /*decimals*/
        m[1]
      ) + "") && v(u, p), N & /*metrics*/
      4 && d !== (d = /*mets*/
      m[5].PointSymbol + "") && v(r, d), /*c*/
      m[6].Netspeed > 0 ? h ? h.p(m, N) : (h = K(m), h.c(), h.m(e, a)) : h && (h.d(1), h = null);
    },
    d(m) {
      m && k(e), h && h.d();
    }
  };
}
function $e(t) {
  let e;
  return {
    c() {
      e = $("p"), e.textContent = "Loading metrics";
    },
    m(n, l) {
      g(n, e, l);
    },
    p: P,
    d(n) {
      n && k(e);
    }
  };
}
function ve(t) {
  let e, n, l = {
    ctx: t,
    current: null,
    token: null,
    hasCatch: !0,
    pending: $e,
    then: ke,
    catch: ge,
    value: 5,
    error: 9
  };
  return V(n = /*metrics*/
  t[2], l), {
    c() {
      e = $("main"), l.block.c(), this.c = P;
    },
    m(i, o) {
      g(i, e, o), l.block.m(e, l.anchor = null), l.mount = () => e, l.anchor = null;
    },
    p(i, [o]) {
      t = i, l.ctx = t, o & /*metrics*/
      4 && n !== (n = /*metrics*/
      t[2]) && V(n, l) || he(l, t, o);
    },
    i: P,
    o: P,
    d(i) {
      i && k(e), l.block.d(), l.token = null, l = null;
    }
  };
}
function ye(t, e, n) {
  let { serverip: l = "" } = e, { verbose: i = !1 } = e, o = 3;
  async function f(u) {
    if (u == "")
      throw new Error("missing server IP");
    const s = await fetch("https://www.ntppool.org/api/data/server/dns/answers/" + u), d = await s.json();
    if (s.ok) {
      let r = [], c = {
        ServerIP: u,
        TopCCs: r,
        Global: {
          Name: "Global",
          Points: 0,
          Netspeed: 0,
          Ratio: 0
        },
        PointSymbol: d.PointSymbol
      }, a = function(h, m) {
        h.Netspeed != 0 && (m.Netspeed = h.Netspeed, m.Ratio = m.Points / m.Netspeed);
      };
      for (let h of d.Server) {
        let m = {
          Name: "",
          Points: 0,
          Netspeed: 0,
          Ratio: 0
        };
        if (h.CC == "") {
          c.Global.Points = h.Points, a(h, c.Global), h.Points > 2 ? n(1, o = 2) : n(1, o = 3);
          continue;
        }
        if (m.Name = h.CC, m.Points = h.Points, a(h, m), (r.length < 2 || h.Count > 5) && r.push(m), r.length >= 5)
          break;
      }
      return c;
    } else
      throw new Error(s.status + " " + s.statusText);
  }
  let p = new Promise(() => {
  });
  return oe(() => {
    n(2, p = f(l));
  }), t.$$set = (u) => {
    "serverip" in u && n(3, l = u.serverip), "verbose" in u && n(0, i = u.verbose);
  }, [i, o, p, l];
}
class Ce extends X {
  constructor(e) {
    super(), be(
      this,
      {
        target: this.shadowRoot,
        props: re(this.attributes),
        customElement: !0
      },
      ye,
      ve,
      Z,
      { serverip: 3, verbose: 0 },
      null
    ), e && (e.target && g(e.target, this, e.anchor), e.props && (this.$set(e.props), T()));
  }
  static get observedAttributes() {
    return ["serverip", "verbose"];
  }
  get serverip() {
    return this.$$.ctx[3];
  }
  set serverip(e) {
    this.$$set({ serverip: e }), T();
  }
  get verbose() {
    return this.$$.ctx[0];
  }
  set verbose(e) {
    this.$$set({ verbose: e }), T();
  }
}
customElements.define("server-points", Ce);
//# sourceMappingURL=server-points.js.map
