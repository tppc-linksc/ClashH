// ShareLinkParser：把节点分享链接（ss / ssr / vmess / vless / trojan / hysteria / hysteria2 / tuic）
// 转换成 mihomo 可直接加载的 YAML。
// 解析规则对齐 mihomo 的 common/convert，保证扫同一个二维码时与 v2rayN、小火箭的结果一致。

import { util } from '@kit.ArkTS';

const BASE64_TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** 生成配置中的代理组名，rules 与代理页都引用它。 */
const GROUP_NAME = '节点选择';

/** 分享链接不带 UA，ws 传输补一个常见浏览器 UA，行为与 mihomo 一致。 */
const DEFAULT_USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36';

/** 支持的分享链接协议头。 */
const SHARE_SCHEMES: string[] = [
  'ss', 'ssr', 'vmess', 'vless', 'trojan', 'hysteria', 'hysteria2', 'hy2', 'tuic'
];

export interface ShareLinkResult {
  /** 生成的 mihomo YAML 文本 */
  yaml: string;
  /** 解析成功的节点数 */
  count: number;
  /** 第一个节点名，用来给配置取名 */
  firstName: string;
}

// ---------------------------------------------------------------------------
// JSON 片段构造器
// YAML 是 JSON 的超集，节点直接以 JSON 流式映射写入，可以完全绕开 YAML 转义问题。
// ---------------------------------------------------------------------------

class JsonNode {
  private parts: string[] = [];
  /** 节点名。写入 name 字段时自动记录，供代理组引用。 */
  label: string = '';

  /** 写入字符串字段，空值自动跳过。 */
  str(key: string, value: string): JsonNode {
    if (value.length > 0) {
      if (key === 'name') {
        this.label = value;
      }
      this.parts.push(`${quote(key)}:${quote(value)}`);
    }
    return this;
  }

  /** 写入字符串字段，允许空值。 */
  strAlways(key: string, value: string): JsonNode {
    this.parts.push(`${quote(key)}:${quote(value)}`);
    return this;
  }

  num(key: string, value: number): JsonNode {
    this.parts.push(`${quote(key)}:${value}`);
    return this;
  }

  bool(key: string, value: boolean): JsonNode {
    this.parts.push(`${quote(key)}:${value ? 'true' : 'false'}`);
    return this;
  }

  /** 写入字符串数组字段，空数组自动跳过。 */
  list(key: string, values: string[]): JsonNode {
    if (values.length > 0) {
      this.parts.push(`${quote(key)}:[${values.map((item: string) => quote(item)).join(',')}]`);
    }
    return this;
  }

  /** 写入嵌套对象字段，空对象自动跳过。 */
  child(key: string, value: JsonNode): JsonNode {
    if (!value.isEmpty()) {
      this.parts.push(`${quote(key)}:${value.toText()}`);
    }
    return this;
  }

  isEmpty(): boolean {
    return this.parts.length === 0;
  }

  toText(): string {
    return `{${this.parts.join(',')}}`;
  }
}

/** 按 JSON 规则给字符串加引号，YAML 双引号标量的转义规则与 JSON 一致。 */
function quote(value: string): string {
  let out = '"';
  for (let i = 0; i < value.length; i++) {
    const ch = value.charAt(i);
    const code = value.charCodeAt(i);
    if (ch === '"') {
      out += '\\"';
    } else if (ch === '\\') {
      out += '\\\\';
    } else if (code < 0x20) {
      out += '\\u' + code.toString(16).padStart(4, '0');
    } else {
      out += ch;
    }
  }
  return out + '"';
}

// ---------------------------------------------------------------------------
// base64 / 百分号编码
// ---------------------------------------------------------------------------

/** 解码 base64（同时兼容标准与 URL-safe 字母表、有无补位），失败返回 undefined。 */
function base64ToBytes(input: string): Uint8Array | undefined {
  const cleaned = input.replace(/[\r\n\t ]/g, '').replace(/-/g, '+').replace(/_/g, '/')
    .replace(/=+$/, '');
  if (cleaned.length === 0 || cleaned.length % 4 === 1) {
    return undefined;
  }
  const bytes: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < cleaned.length; i++) {
    const index = BASE64_TABLE.indexOf(cleaned.charAt(i));
    if (index < 0) {
      return undefined;
    }
    buffer = (buffer << 6) | index;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 0xff);
    }
  }
  return new Uint8Array(bytes);
}

/** 解码 base64 文本，失败返回 undefined。 */
export function decodeBase64Text(input: string): string | undefined {
  const bytes = base64ToBytes(input);
  if (!bytes) {
    return undefined;
  }
  try {
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  } catch (error) {
    return undefined;
  }
}

/** 百分号解码，遇到非法编码时原样返回。 */
function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (error) {
    return value;
  }
}

// ---------------------------------------------------------------------------
// 分享链接结构解析
// ---------------------------------------------------------------------------

class ShareLink {
  scheme: string = '';
  /** 原始 userinfo（未解码），ss 需要它做 base64 还原 */
  rawUserInfo: string = '';
  username: string = '';
  password: string = '';
  hasPassword: boolean = false;
  host: string = '';
  port: string = '';
  path: string = '';
  fragment: string = '';
  query: Map<string, string> = new Map<string, string>();

  /** 取查询参数，缺失时返回空串。 */
  get(key: string): string {
    return this.query.get(key) ?? '';
  }
}

function parseQuery(raw: string): Map<string, string> {
  const result: Map<string, string> = new Map<string, string>();
  if (raw.length === 0) {
    return result;
  }
  const pairs = raw.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const pair = pairs[i];
    if (pair.length === 0) {
      continue;
    }
    const index = pair.indexOf('=');
    const key = index >= 0 ? pair.substring(0, index) : pair;
    const value = index >= 0 ? pair.substring(index + 1) : '';
    result.set(safeDecode(key), safeDecode(value));
  }
  return result;
}

/** 解析 scheme://[userinfo@]host[:port][/path][?query][#fragment] */
function parseShareLink(line: string): ShareLink | undefined {
  const separator = line.indexOf('://');
  if (separator <= 0) {
    return undefined;
  }
  const link = new ShareLink();
  link.scheme = line.substring(0, separator).toLowerCase();
  let rest = line.substring(separator + 3);

  const hash = rest.indexOf('#');
  if (hash >= 0) {
    link.fragment = safeDecode(rest.substring(hash + 1));
    rest = rest.substring(0, hash);
  }
  const mark = rest.indexOf('?');
  if (mark >= 0) {
    link.query = parseQuery(rest.substring(mark + 1));
    rest = rest.substring(0, mark);
  }
  const at = rest.lastIndexOf('@');
  if (at >= 0) {
    link.rawUserInfo = rest.substring(0, at);
    rest = rest.substring(at + 1);
    const colon = link.rawUserInfo.indexOf(':');
    if (colon >= 0) {
      link.username = safeDecode(link.rawUserInfo.substring(0, colon));
      link.password = safeDecode(link.rawUserInfo.substring(colon + 1));
      link.hasPassword = true;
    } else {
      link.username = safeDecode(link.rawUserInfo);
    }
  }
  const slash = rest.indexOf('/');
  if (slash >= 0) {
    link.path = rest.substring(slash);
    rest = rest.substring(0, slash);
  }
  if (rest.startsWith('[')) {
    // IPv6 字面量：[::1]:443
    const close = rest.indexOf(']');
    if (close < 0) {
      return undefined;
    }
    link.host = rest.substring(1, close);
    const tail = rest.substring(close + 1);
    if (tail.startsWith(':')) {
      link.port = tail.substring(1);
    }
  } else {
    const colon = rest.lastIndexOf(':');
    if (colon >= 0) {
      link.host = rest.substring(0, colon);
      link.port = rest.substring(colon + 1);
    } else {
      link.host = rest;
    }
  }
  return link;
}

// ---------------------------------------------------------------------------
// 工具
// ---------------------------------------------------------------------------

function toPort(value: string): number {
  const port = Number.parseInt(value, 10);
  return Number.isNaN(port) ? 0 : port;
}

function splitAlpn(value: string): string[] {
  if (value.length === 0) {
    return [];
  }
  return value.split(',').map((item: string) => item.trim())
    .filter((item: string) => item.length > 0);
}

function isTruthy(value: string): boolean {
  const normalized = value.toLowerCase();
  return normalized === '1' || normalized === 'true';
}

/** 与 mihomo uniqueName 一致：重名时追加 -01、-02。 */
class NameRegistry {
  private used: Map<string, number> = new Map<string, number>();

  unique(name: string, fallback: string): string {
    const base = name.trim().length > 0 ? name.trim() : fallback;
    const index = this.used.get(base);
    if (index === undefined) {
      this.used.set(base, 0);
      return base;
    }
    const next = index + 1;
    this.used.set(base, next);
    return `${base}-${next < 10 ? '0' : ''}${next}`;
  }
}

// ---------------------------------------------------------------------------
// 各协议解析
// ---------------------------------------------------------------------------

/** VMess / VLESS 共用的 Xray 分享链接字段（handleVShareLink 的移植）。 */
function applyVShareLink(link: ShareLink, node: JsonNode): boolean {
  if (link.host.length === 0 || link.port.length === 0) {
    return false;
  }
  node.str('server', link.host);
  node.num('port', toPort(link.port));
  node.str('uuid', link.username);
  node.bool('udp', true);

  const security = link.get('security').toLowerCase();
  if (security.endsWith('tls') || security === 'reality') {
    node.bool('tls', true);
    const fingerprint = link.get('fp');
    node.str('client-fingerprint', fingerprint.length > 0 ? fingerprint : 'chrome');
    node.list('alpn', splitAlpn(link.get('alpn')));
    node.str('fingerprint', link.get('pcs'));
  }
  node.str('servername', link.get('sni'));

  const publicKey = link.get('pbk');
  if (publicKey.length > 0) {
    const reality = new JsonNode();
    reality.str('public-key', publicKey);
    reality.strAlways('short-id', link.get('sid'));
    node.child('reality-opts', reality);
  }

  const packetEncoding = link.get('packetEncoding');
  if (packetEncoding === 'packet') {
    node.bool('packet-addr', true);
  } else if (packetEncoding !== 'none') {
    node.bool('xudp', true);
  }

  let network = link.get('type').toLowerCase();
  if (network.length === 0) {
    network = 'tcp';
  }
  const fakeType = link.get('headerType').toLowerCase();
  if (network === 'tcp' && fakeType === 'http') {
    network = 'http';
  } else if (network === 'http') {
    network = 'h2';
  }
  node.str('network', network);
  applyTransport(link, node, network);
  return true;
}

/** 按传输层类型补上 ws-opts / grpc-opts 等字段。 */
function applyTransport(link: ShareLink, node: JsonNode, network: string): void {
  if (network === 'http') {
    const headers = new JsonNode();
    headers.list('Host', link.get('host').length > 0 ? [link.get('host')] : []);
    const httpOpts = new JsonNode();
    httpOpts.str('method', link.get('method'));
    httpOpts.list('path', [link.get('path').length > 0 ? link.get('path') : '/']);
    httpOpts.child('headers', headers);
    node.child('http-opts', httpOpts);
  } else if (network === 'h2') {
    const h2Opts = new JsonNode();
    h2Opts.strAlways('path', link.get('path').length > 0 ? link.get('path') : '/');
    h2Opts.list('host', link.get('host').length > 0 ? [link.get('host')] : []);
    node.child('h2-opts', h2Opts);
  } else if (network === 'ws' || network === 'httpupgrade') {
    const headers = new JsonNode();
    headers.str('User-Agent', DEFAULT_USER_AGENT);
    headers.str('Host', link.get('host'));
    const wsOpts = new JsonNode();
    wsOpts.strAlways('path', link.get('path'));
    wsOpts.child('headers', headers);
    const earlyData = Number.parseInt(link.get('ed'), 10);
    if (!Number.isNaN(earlyData)) {
      if (network === 'ws') {
        wsOpts.num('max-early-data', earlyData);
        wsOpts.str('early-data-header-name', 'Sec-WebSocket-Protocol');
      } else {
        wsOpts.bool('v2ray-http-upgrade-fast-open', true);
      }
    }
    const earlyDataHeader = link.get('eh');
    if (earlyDataHeader.length > 0) {
      wsOpts.str('early-data-header-name', earlyDataHeader);
    }
    node.child('ws-opts', wsOpts);
  } else if (network === 'grpc') {
    const grpcOpts = new JsonNode();
    grpcOpts.strAlways('grpc-service-name', link.get('serviceName'));
    node.child('grpc-opts', grpcOpts);
  } else if (network === 'xhttp') {
    const xhttpOpts = new JsonNode();
    xhttpOpts.str('path', link.get('path'));
    xhttpOpts.str('host', link.get('host'));
    xhttpOpts.str('mode', link.get('mode'));
    node.child('xhttp-opts', xhttpOpts);
  }
}

function parseVless(link: ShareLink, name: string): JsonNode | undefined {
  const node = new JsonNode();
  node.str('name', name);
  node.str('type', 'vless');
  if (!applyVShareLink(link, node)) {
    return undefined;
  }
  const flow = link.get('flow');
  if (flow.length > 0) {
    node.str('flow', flow.toLowerCase());
  }
  node.str('encryption', link.get('encryption'));
  return node;
}

/** v2rayN 风格的 vmess://base64(JSON) */
interface VmessJson {
  ps?: string;
  add?: string;
  port?: string | number;
  id?: string;
  aid?: string | number;
  scy?: string;
  net?: string;
  type?: string;
  host?: string;
  path?: string;
  tls?: string;
  sni?: string;
  alpn?: string;
}

function textOf(value: string | number | undefined): string {
  if (value === undefined) {
    return '';
  }
  return `${value}`;
}

function parseVmessJson(body: string, names: NameRegistry): JsonNode | undefined {
  const decoded = decodeBase64Text(body);
  if (decoded === undefined || decoded.indexOf('{') < 0) {
    return undefined;
  }
  let values: VmessJson;
  try {
    values = JSON.parse(decoded) as VmessJson;
  } catch (error) {
    return undefined;
  }
  const server = textOf(values.add);
  const port = toPort(textOf(values.port));
  if (server.length === 0 || port === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', names.unique(textOf(values.ps), `${server}:${port}`));
  node.str('type', 'vmess');
  node.str('server', server);
  node.num('port', port);
  node.str('uuid', textOf(values.id));
  const alterId = Number.parseInt(textOf(values.aid), 10);
  node.num('alterId', Number.isNaN(alterId) ? 0 : alterId);
  node.bool('udp', true);
  node.bool('xudp', true);

  const cipher = textOf(values.scy);
  node.str('cipher', cipher.length > 0 ? cipher : 'auto');
  node.str('servername', textOf(values.sni));

  let network = textOf(values.net).toLowerCase();
  if (textOf(values.type) === 'http') {
    network = 'http';
  } else if (network === 'http') {
    network = 'h2';
  }
  if (network.length > 0) {
    node.str('network', network);
  }

  const tls = textOf(values.tls).toLowerCase();
  if (tls.endsWith('tls') && tls.length > 0) {
    node.bool('tls', true);
    node.list('alpn', splitAlpn(textOf(values.alpn)));
  }

  // 复用传输层构造逻辑：把 JSON 字段映射成同名查询参数。
  const transport = new ShareLink();
  transport.query.set('host', textOf(values.host));
  transport.query.set('path', textOf(values.path));
  transport.query.set('serviceName', textOf(values.path));
  applyTransport(transport, node, network);
  return node;
}

function parseTrojan(link: ShareLink, name: string): JsonNode | undefined {
  if (link.host.length === 0 || link.port.length === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', name);
  node.str('type', 'trojan');
  node.str('server', link.host);
  node.num('port', toPort(link.port));
  node.str('password', link.username);
  node.bool('udp', true);
  if (isTruthy(link.get('allowInsecure'))) {
    node.bool('skip-cert-verify', true);
  }
  node.str('sni', link.get('sni'));
  node.list('alpn', splitAlpn(link.get('alpn')));

  const network = link.get('type').toLowerCase();
  if (network.length > 0) {
    node.str('network', network);
  }
  if (network === 'ws') {
    const headers = new JsonNode();
    headers.str('User-Agent', DEFAULT_USER_AGENT);
    headers.str('Host', link.get('host'));
    const wsOpts = new JsonNode();
    wsOpts.strAlways('path', link.get('path'));
    wsOpts.child('headers', headers);
    node.child('ws-opts', wsOpts);
  } else if (network === 'grpc') {
    const grpcOpts = new JsonNode();
    grpcOpts.strAlways('grpc-service-name', link.get('serviceName'));
    node.child('grpc-opts', grpcOpts);
  }
  const fingerprint = link.get('fp');
  node.str('client-fingerprint', fingerprint.length > 0 ? fingerprint : 'chrome');
  node.str('fingerprint', link.get('pcs'));
  return node;
}

function parseShadowsocks(link: ShareLink, names: NameRegistry): JsonNode | undefined {
  let target = link;
  if (target.port.length === 0) {
    // ss://base64(method:password@host:port) 的旧格式
    const decoded = decodeBase64Text(target.host + target.path);
    if (decoded === undefined) {
      return undefined;
    }
    const reparsed = parseShareLink('ss://' + decoded);
    if (!reparsed) {
      return undefined;
    }
    reparsed.fragment = target.fragment;
    reparsed.query = target.query;
    target = reparsed;
  }
  let cipher = target.username;
  let password = target.password;
  if (!target.hasPassword) {
    // SIP002：userinfo 是 base64(method:password)
    const decoded = decodeBase64Text(target.rawUserInfo);
    if (decoded === undefined) {
      return undefined;
    }
    const colon = decoded.indexOf(':');
    if (colon < 0) {
      return undefined;
    }
    cipher = decoded.substring(0, colon);
    password = decoded.substring(colon + 1);
  }
  if (target.host.length === 0 || target.port.length === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', names.unique(target.fragment, `${target.host}:${target.port}`));
  node.str('type', 'ss');
  node.str('server', target.host);
  node.num('port', toPort(target.port));
  node.str('cipher', cipher);
  node.str('password', password);
  node.bool('udp', true);
  if (target.get('udp-over-tcp') === 'true' || target.get('uot') === '1') {
    node.bool('udp-over-tcp', true);
  }
  applySsPlugin(target.get('plugin'), node);
  return node;
}

/** 解析 ss 的 plugin 参数（obfs / v2ray-plugin）。 */
function applySsPlugin(plugin: string, node: JsonNode): void {
  if (plugin.indexOf(';') < 0) {
    return;
  }
  const info: Map<string, string> = parseQuery(plugin.replace(/;/g, '&'));
  const pluginName = plugin.split(';')[0];
  const opts = new JsonNode();
  if (pluginName.indexOf('obfs') >= 0 && pluginName.indexOf('v2ray') < 0) {
    node.str('plugin', 'obfs');
    opts.strAlways('mode', info.get('obfs') ?? '');
    opts.str('host', info.get('obfs-host') ?? '');
    node.child('plugin-opts', opts);
  } else if (pluginName.indexOf('v2ray-plugin') >= 0) {
    const mode = info.get('mode') ?? info.get('obfs') ?? '';
    const host = info.get('host') ?? info.get('obfs-host') ?? '';
    node.str('plugin', 'v2ray-plugin');
    opts.strAlways('mode', mode.length > 0 ? mode : 'websocket');
    opts.str('host', host);
    opts.str('path', info.get('path') ?? '');
    opts.bool('tls', plugin.indexOf('tls') >= 0);
    node.child('plugin-opts', opts);
  }
}

function parseHysteria2(link: ShareLink, name: string): JsonNode | undefined {
  if (link.host.length === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', name);
  node.str('type', 'hysteria2');
  node.str('server', link.host);
  node.num('port', link.port.length > 0 ? toPort(link.port) : 443);
  const password = link.hasPassword ? `${link.username}:${link.password}` : link.username;
  node.str('password', password.length > 0 ? password : link.get('auth'));
  node.str('obfs', link.get('obfs'));
  node.str('obfs-password', link.get('obfs-password'));
  node.str('sni', link.get('sni'));
  if (isTruthy(link.get('insecure'))) {
    node.bool('skip-cert-verify', true);
  }
  node.list('alpn', splitAlpn(link.get('alpn')));
  node.str('fingerprint', link.get('pinSHA256'));
  node.str('down', link.get('down'));
  node.str('up', link.get('up'));
  return node;
}

function parseHysteria(link: ShareLink, name: string): JsonNode | undefined {
  if (link.host.length === 0 || link.port.length === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', name);
  node.str('type', 'hysteria');
  node.str('server', link.host);
  node.num('port', toPort(link.port));
  node.str('sni', link.get('peer'));
  node.str('obfs', link.get('obfs'));
  node.list('alpn', splitAlpn(link.get('alpn')));
  node.str('auth_str', link.get('auth'));
  node.str('protocol', link.get('protocol'));
  const up = link.get('up').length > 0 ? link.get('up') : link.get('upmbps');
  const down = link.get('down').length > 0 ? link.get('down') : link.get('downmbps');
  node.str('up', up);
  node.str('down', down);
  if (isTruthy(link.get('insecure'))) {
    node.bool('skip-cert-verify', true);
  }
  return node;
}

function parseTuic(link: ShareLink, name: string): JsonNode | undefined {
  if (link.host.length === 0 || link.port.length === 0) {
    return undefined;
  }
  const node = new JsonNode();
  node.str('name', name);
  node.str('type', 'tuic');
  node.str('server', link.host);
  node.num('port', toPort(link.port));
  node.bool('udp', true);
  if (link.hasPassword) {
    node.str('uuid', link.username);
    node.str('password', link.password);
  } else {
    node.str('token', link.username);
  }
  node.str('congestion-controller', link.get('congestion_control'));
  node.list('alpn', splitAlpn(link.get('alpn')));
  node.str('sni', link.get('sni'));
  if (link.get('disable_sni') === '1') {
    node.bool('disable-sni', true);
  }
  node.str('udp-relay-mode', link.get('udp_relay_mode'));
  return node;
}

function parseSsr(body: string, names: NameRegistry): JsonNode | undefined {
  const decoded = decodeBase64Text(body);
  if (decoded === undefined) {
    return undefined;
  }
  const cut = decoded.indexOf('/?');
  const head = cut >= 0 ? decoded.substring(0, cut) : decoded;
  const tail = cut >= 0 ? decoded.substring(cut + 2) : '';
  const fields = head.split(':');
  if (fields.length !== 6) {
    return undefined;
  }
  const query = parseQuery(tail);
  const node = new JsonNode();
  const host = fields[0];
  const port = fields[1];
  node.str('name', names.unique(decodeBase64Text(query.get('remarks') ?? '') ?? '', `${host}:${port}`));
  node.str('type', 'ssr');
  node.str('server', host);
  node.num('port', toPort(port));
  node.str('protocol', fields[2]);
  node.str('cipher', fields[3]);
  node.str('obfs', fields[4]);
  node.str('password', decodeBase64Text(fields[5]) ?? '');
  node.bool('udp', true);
  node.str('obfs-param', decodeBase64Text(query.get('obfsparam') ?? '') ?? '');
  node.str('protocol-param', decodeBase64Text(query.get('protoparam') ?? '') ?? '');
  return node;
}

// ---------------------------------------------------------------------------
// 对外接口
// ---------------------------------------------------------------------------

/** 判断一段文本是否是（可能经过 base64 编码的）分享链接集合。 */
export function isShareLinkPayload(raw: string): boolean {
  const text = raw.trim();
  if (text.length === 0) {
    return false;
  }
  if (hasShareScheme(text)) {
    return true;
  }
  const decoded = decodeBase64Text(text);
  return decoded !== undefined && hasShareScheme(decoded);
}

function hasShareScheme(text: string): boolean {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    const separator = line.indexOf('://');
    if (separator > 0 && SHARE_SCHEMES.indexOf(line.substring(0, separator).toLowerCase()) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * 把一条或多条分享链接（也接受 base64 编码的订阅正文）转换成 mihomo YAML。
 * 解析失败时抛出带原因的错误，方便页面直接提示用户。
 */
export function convertShareLinks(raw: string): ShareLinkResult {
  let text = raw.trim();
  if (!hasShareScheme(text)) {
    const decoded = decodeBase64Text(text);
    if (decoded !== undefined && hasShareScheme(decoded)) {
      text = decoded;
    }
  }

  const names = new NameRegistry();
  const nodes: JsonNode[] = [];
  const nodeNames: string[] = [];
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line.length === 0) {
      continue;
    }
    const node = parseLine(line, names);
    if (node) {
      nodes.push(node);
    }
  }
  if (nodes.length === 0) {
    throw new Error('没有解析出可用的节点');
  }

  for (let i = 0; i < nodes.length; i++) {
    nodeNames.push(nodes[i].label);
  }

  const group = new JsonNode();
  group.str('name', GROUP_NAME);
  group.str('type', 'select');
  group.list('proxies', nodeNames.concat(['DIRECT']));

  const yaml = buildYaml(nodes, group);
  return { yaml, count: nodes.length, firstName: nodeNames[0] };
}

function parseLine(line: string, names: NameRegistry): JsonNode | undefined {
  const separator = line.indexOf('://');
  if (separator <= 0) {
    return undefined;
  }
  const scheme = line.substring(0, separator).toLowerCase();
  const body = line.substring(separator + 3);

  if (scheme === 'vmess') {
    const fromJson = parseVmessJson(body, names);
    if (fromJson) {
      return fromJson;
    }
  }
  if (scheme === 'ssr') {
    return parseSsr(body, names);
  }

  const link = parseShareLink(line);
  if (!link) {
    return undefined;
  }
  if (scheme === 'ss') {
    // ss 可能要先还原 base64 才知道真实的 host:port，名字由它自己登记。
    return parseShadowsocks(link, names);
  }
  const fallbackName = link.port.length > 0 ? `${link.host}:${link.port}` : link.host;
  const name = names.unique(link.fragment, fallbackName);

  if (scheme === 'vless') {
    return parseVless(link, name);
  }
  if (scheme === 'vmess') {
    // Xray VMessAEAD 分享链接
    const node = new JsonNode();
    node.str('name', name);
    node.str('type', 'vmess');
    if (!applyVShareLink(link, node)) {
      return undefined;
    }
    node.num('alterId', 0);
    const encryption = link.get('encryption');
    node.str('cipher', encryption.length > 0 ? encryption : 'auto');
    return node;
  }
  if (scheme === 'trojan') {
    return parseTrojan(link, name);
  }
  if (scheme === 'hysteria2' || scheme === 'hy2') {
    return parseHysteria2(link, name);
  }
  if (scheme === 'hysteria') {
    return parseHysteria(link, name);
  }
  if (scheme === 'tuic') {
    return parseTuic(link, name);
  }
  return undefined;
}

function buildYaml(nodes: JsonNode[], group: JsonNode): string {
  const lines: string[] = [];
  lines.push('# 由 ClashH 从分享链接生成');
  lines.push('mixed-port: 7890');
  lines.push('allow-lan: false');
  lines.push('mode: rule');
  lines.push('log-level: info');
  lines.push('unified-delay: true');
  lines.push('find-process-mode: off');
  lines.push('');
  lines.push('proxies:');
  for (let i = 0; i < nodes.length; i++) {
    lines.push('  - ' + nodes[i].toText());
  }
  lines.push('');
  lines.push('proxy-groups:');
  lines.push('  - ' + group.toText());
  lines.push('');
  lines.push('rules:');
  lines.push('  - "IP-CIDR,127.0.0.0/8,DIRECT,no-resolve"');
  lines.push('  - "IP-CIDR,10.0.0.0/8,DIRECT,no-resolve"');
  lines.push('  - "IP-CIDR,172.16.0.0/12,DIRECT,no-resolve"');
  lines.push('  - "IP-CIDR,192.168.0.0/16,DIRECT,no-resolve"');
  lines.push('  - "IP-CIDR6,fc00::/7,DIRECT,no-resolve"');
  lines.push(`  - ${quote('MATCH,' + GROUP_NAME)}`);
  lines.push('');
  return lines.join('\n');
}
