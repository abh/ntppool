function n(o, e, t) {
  const r = { Name: o, Points: e, Netspeed: 0, Ratio: 0 };
  return typeof t == "number" && t > 0 && (r.Netspeed = t, r.Ratio = e / t), r;
}
function l(o, e) {
  const t = [];
  for (const r of o)
    if ((t.length < 2 || r.Count > 5) && t.push(e(r)), t.length >= 5)
      break;
  return t;
}
function a(o) {
  return typeof o == "object" && o !== null;
}
function d(o, e) {
  if (a(e) && Array.isArray(e.Zones) && a(e.Global)) {
    const t = e;
    return {
      ServerIP: o,
      Global: n("Global", t.Global.Points, void 0),
      TopCCs: l(t.Zones, (r) => n(r.Zone, r.Points, r.Netspeed)),
      PointSymbol: t.PointSymbol,
      Heading: "Top zones"
    };
  }
  if (a(e) && Array.isArray(e.Server)) {
    const t = e;
    let r = n("Global", 0, void 0);
    const i = [];
    for (const s of t.Server)
      s.CC === "" ? r = n("Global", s.Points, s.Netspeed) : i.push(s);
    return {
      ServerIP: o,
      Global: r,
      TopCCs: l(i, (s) => n(s.CC, s.Points, s.Netspeed)),
      PointSymbol: t.PointSymbol,
      Heading: "Top Countries"
    };
  }
  throw new Error("unexpected response");
}
class c extends HTMLElement {
  serverip = "";
  verbose = !1;
  apiurl = "";
  debug = !1;
  hasInitialLoad = !1;
  constructor() {
    super();
  }
  static get observedAttributes() {
    return ["serverip", "verbose", "apiurl"];
  }
  attributeChangedCallback(e, t, r) {
    switch (e) {
      case "serverip":
        this.serverip = r || "", this.isConnected && t !== r && this.hasInitialLoad && this.fetchAndRender();
        break;
      case "verbose":
        this.verbose = r === "true";
        break;
      case "apiurl":
        this.apiurl = r || "";
        break;
    }
  }
  connectedCallback() {
    this.render(), this.serverip && (this.fetchAndRender(), this.hasInitialLoad = !0);
  }
  get defaultApiUrl() {
    return "https://data-api.ntppool.dev/api/server/dns/answers/";
  }
  async getMetrics(e) {
    if (e === "")
      throw new Error("missing server IP");
    const t = this.apiurl || this.defaultApiUrl, r = t.endsWith("/") ? t + e : t + "/" + e, i = await fetch(r);
    if (i.ok)
      return d(e, await i.json());
    {
      let s;
      throw i.status === 404 ? s = "Server not found" : s = "Failed to load server metrics", new Error(s);
    }
  }
  async fetchAndRender() {
    if (this.serverip) {
      this.renderLoading();
      try {
        const e = await this.getMetrics(this.serverip);
        this.renderMetrics(e);
      } catch (e) {
        this.renderError(e);
      }
    }
  }
  escapeHtml(e) {
    const t = document.createElement("div");
    return t.textContent = e, t.innerHTML;
  }
  render() {
    this.innerHTML = "<p>Initializing...</p>";
  }
  renderLoading() {
    this.innerHTML = "<p>Loading metrics</p>";
  }
  renderError(e) {
    const t = "Unable to load server metrics";
    this.innerHTML = `<p class="server-points__error">${t}</p>`;
  }
  renderMetrics(e) {
    const t = e.Global.Points > 2 ? 2 : 3, r = this.escapeHtml(e.PointSymbol);
    let i = `
      <p>
        Global points ${e.Global.Points.toFixed(t)}${r}
      </p>
    `;
    e.Global.Points > 0 && e.TopCCs.length > 0 && (i += `
        <table class="server-points__table">
          <thead>
            <tr>
              <th class="server-points__th" colspan="3">
                ${e.Heading}
                ${this.verbose ? `(${this.escapeHtml(e.ServerIP)})` : ""}
              </th>
            </tr>
          </thead>
          <tbody>
            ${e.TopCCs.map((s) => `
              <tr>
                <td class="server-points__td">${this.escapeHtml(s.Name === "@" ? "global" : s.Name)}</td>
                <td class="server-points__td">
                  ${s.Points.toFixed(t)}
                  ${r}
                </td>
                ${s.Netspeed > 0 ? `
                  <td class="server-points__td">
                    ${s.Netspeed.toFixed(t)}
                    ${r} (${s.Ratio.toFixed(2)}x)
                  </td>
                ` : ""}
              </tr>
            `).join("")}
          </tbody>
        </table>
      `), this.debug && (i += `<code class="server-points__debug">${JSON.stringify(e, null, 2)}</code>`), this.innerHTML = i;
  }
}
customElements.define("server-points", c);
//# sourceMappingURL=server-points.js.map
