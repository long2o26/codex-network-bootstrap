#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { basename } from "node:path";

function usage() {
  console.error(`Usage:
  node client/generate-mihomo-config.mjs --tokyo secrets/tokyo.json --singapore secrets/singapore.json --out mihomo-codex.yaml

Optional:
  --tokyo-ip IP          Override Tokyo server_ip from JSON.
  --singapore-ip IP      Override Singapore server_ip from JSON.
`);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) {
      throw new Error(`Unexpected argument: ${key}`);
    }
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for ${key}`);
    }
    args[key.slice(2)] = value;
    i += 1;
  }
  return args;
}

function loadNode(path, ipOverride) {
  const node = JSON.parse(readFileSync(path, "utf8"));
  node.server_ip = ipOverride || node.server_ip;
  if (!node.server_ip) {
    throw new Error(`${basename(path)} is missing server_ip. Pass an explicit --*-ip value.`);
  }
  for (const field of ["node_name", "vless", "hysteria2"]) {
    if (!node[field]) throw new Error(`${basename(path)} is missing ${field}`);
  }
  return node;
}

function q(value) {
  return JSON.stringify(String(value));
}

function proxyName(node, protocol) {
  return `${node.node_name.toUpperCase()}-${protocol}`;
}

function vlessProxy(node) {
  return `  - name: ${q(proxyName(node, "VLESS"))}
    type: vless
    server: ${q(node.server_ip)}
    port: ${node.vless.port}
    uuid: ${q(node.vless.uuid)}
    network: tcp
    tls: true
    udp: true
    flow: ${q(node.vless.flow || "xtls-rprx-vision")}
    servername: ${q(node.vless.server_name)}
    client-fingerprint: chrome
    reality-opts:
      public-key: ${q(node.vless.public_key)}
      short-id: ${q(node.vless.short_id)}`;
}

function hy2Proxy(node) {
  return `  - name: ${q(proxyName(node, "HY2"))}
    type: hysteria2
    server: ${q(node.server_ip)}
    port: ${node.hysteria2.port}
    password: ${q(node.hysteria2.password)}
    sni: ${q(node.hysteria2.sni)}
    skip-cert-verify: ${node.hysteria2.skip_cert_verify ? "true" : "false"}
    udp: true`;
}

function list(items) {
  return items.map((item) => `      - ${q(item)}`).join("\n");
}

function buildConfig(tokyo, singapore) {
  const tokyoProxies = [proxyName(tokyo, "VLESS"), proxyName(tokyo, "HY2")];
  const singaporeProxies = [proxyName(singapore, "VLESS"), proxyName(singapore, "HY2")];
  const allProxies = [...tokyoProxies, ...singaporeProxies];

  return `mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: false
unified-delay: true
tcp-concurrent: true

profile:
  store-selected: true
  store-fake-ip: true

geodata-mode: true
geox-url:
  geoip: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.dat"
  geosite: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat"
  mmdb: "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"

dns:
  enable: true
  listen: 127.0.0.1:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://223.5.5.5/dns-query
    - https://doh.pub/dns-query
  proxy-server-nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
  nameserver-policy:
    "geosite:cn":
      - https://223.5.5.5/dns-query
      - https://doh.pub/dns-query
    "geosite:private":
      - https://223.5.5.5/dns-query
      - https://doh.pub/dns-query
    "geosite:geolocation-!cn":
      - https://1.1.1.1/dns-query
      - https://8.8.8.8/dns-query

proxies:
${[vlessProxy(tokyo), hy2Proxy(tokyo), vlessProxy(singapore), hy2Proxy(singapore)].join("\n")}

proxy-groups:
  - name: AUTO-CODEX
    type: url-test
    url: https://www.gstatic.com/generate_204
    interval: 300
    tolerance: 50
    proxies:
${list(allProxies)}
  - name: TOKYO
    type: select
    proxies:
${list(tokyoProxies)}
  - name: SINGAPORE
    type: select
    proxies:
${list(singaporeProxies)}
  - name: PROXY
    type: select
    proxies:
      - "AUTO-CODEX"
      - "TOKYO"
      - "SINGAPORE"
      - "DIRECT"

rules:
  - DOMAIN-SUFFIX,openai.com,AUTO-CODEX
  - DOMAIN-SUFFIX,chatgpt.com,AUTO-CODEX
  - DOMAIN-SUFFIX,oaiusercontent.com,AUTO-CODEX
  - DOMAIN-SUFFIX,oaistatic.com,AUTO-CODEX
  - DOMAIN-SUFFIX,auth0.com,AUTO-CODEX
  - DOMAIN-SUFFIX,github.com,AUTO-CODEX
  - DOMAIN-SUFFIX,githubusercontent.com,AUTO-CODEX
  - DOMAIN-SUFFIX,githubassets.com,AUTO-CODEX
  - DOMAIN-SUFFIX,jsdelivr.net,AUTO-CODEX
  - DOMAIN-SUFFIX,cloudflare.com,AUTO-CODEX
  - GEOSITE,cn,DIRECT
  - IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
  - IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  - IP-CIDR,127.0.0.0/8,DIRECT,no-resolve
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
`;
}

try {
  const args = parseArgs(process.argv.slice(2));
  if (!args.tokyo || !args.singapore || !args.out) {
    usage();
    process.exit(1);
  }
  const tokyo = loadNode(args.tokyo, args["tokyo-ip"]);
  const singapore = loadNode(args.singapore, args["singapore-ip"]);
  writeFileSync(args.out, buildConfig(tokyo, singapore));
  console.log(`Wrote ${args.out}`);
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
