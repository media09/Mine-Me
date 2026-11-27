'use strict';

const http = require('node:http');
const net = require('node:net');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { randomInt } = require('node:crypto');

const ROOT = __dirname;
const BASE_PATH = '/mineme';
const HEALTH_PATH = BASE_PATH + '/healthz';
const GATEWAY_ENTRY = path.join(ROOT, 'services', 'pool-gateway', 'index.mjs');
const PROXY_TEMPLATE = path.join(ROOT, 'services', 'pool-proxy', 'config.example.json');

let gateway = null;
let proxy = null;
let gatewayPort = null;
let state = process.env.MINE_ME_GATEWAY_ENABLED === 'true' ? 'starting' : 'disabled';
let failureCode = null;
let proxyConfigPath = null;
let stopping = false;

function json(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff'
  });
  res.end(JSON.stringify(body));
}

function stripBasePath(rawUrl) {
  const parsed = new URL(rawUrl || '/', 'http://localhost');
  if (parsed.pathname === BASE_PATH) return '/' + parsed.search;
  if (!parsed.pathname.startsWith(BASE_PATH + '/')) return null;
  return parsed.pathname.slice(BASE_PATH.length) + parsed.search;
}

function waitForTcp(host, port, timeoutMs, child) {
  const deadline = Date.now() + timeoutMs;

  return new Promise((resolve, reject) => {
    let settled = false;
    let checkTimer;

    const finish = (error) => {
      if (settled) return;
      settled = true;
      clearInterval(checkTimer);
      if (error) reject(error);
      else resolve();
    };

    const check = () => {
      if (child.exitCode !== null || child.signalCode !== null) {
        finish(new Error('PROXY_EXITED_BEFORE_LISTEN'));
        return;
      }
      const socket = net.connect({ host, port });
      socket.setTimeout(700);
      socket.once('connect', () => {
        socket.destroy();
        finish();
      });
      socket.once('error', () => socket.destroy());
      socket.once('timeout', () => socket.destroy());
      if (Date.now() >= deadline) finish(new Error('PROXY_LISTENER_TIMEOUT'));
    };

    checkTimer = setInterval(check, 500);
    check();
  });
}

function startProxyAndGateway() {
  if (process.env.MINE_ME_GATEWAY_ENABLED !== 'true') return;

  try {
    const required = [
      'SUPABASE_URL',
      'SUPABASE_SERVICE_ROLE_KEY',
      'MINING_GATEWAY_TOKEN_SECRET',
      'ALLOWED_WEB_ORIGINS',
      'CENTRAL_MONERO_WALLET_ADDRESS',
      'VLTRIG_PROXY_PATH'
    ];
    for (const name of required) {
      if (!process.env[name]) throw new Error('MISSING_' + name);
    }
    if (Buffer.byteLength(process.env.MINING_GATEWAY_TOKEN_SECRET, 'utf8') < 32) {
      throw new Error('INVALID_MINING_GATEWAY_TOKEN_SECRET');
    }
    if (!/^[48][1-9A-HJ-NP-Za-km-z]{94,105}$/.test(process.env.CENTRAL_MONERO_WALLET_ADDRESS)) {
      throw new Error('INVALID_CENTRAL_MONERO_WALLET_ADDRESS');
    }
    if (!fs.existsSync(GATEWAY_ENTRY) || !fs.existsSync(PROXY_TEMPLATE)) {
      throw new Error('GATEWAY_DEPLOYMENT_FILES_MISSING');
    }

    const proxyRelativePath = process.env.VLTRIG_PROXY_PATH;
    if (path.isAbsolute(proxyRelativePath)) throw new Error('VLTRIG_PROXY_PATH_MUST_BE_RELATIVE');
    const proxyBinary = path.resolve(ROOT, proxyRelativePath);
    if (!proxyBinary.startsWith(ROOT + path.sep)) throw new Error('VLTRIG_PROXY_PATH_OUTSIDE_APP');
    if (!fs.existsSync(proxyBinary)) throw new Error('VLTRIG_PROXY_BINARY_NOT_FOUND');
    fs.accessSync(proxyBinary, fs.constants.X_OK);

    const template = JSON.parse(fs.readFileSync(PROXY_TEMPLATE, 'utf8'));
    if (!Array.isArray(template.pools) || template.pools.length < 1) {
      throw new Error('INVALID_PROXY_CONFIG_TEMPLATE');
    }
    for (const pool of template.pools) {
      pool.user = process.env.CENTRAL_MONERO_WALLET_ADDRESS;
    }

    const privateDir = path.join(ROOT, 'tmp', 'mine-me-proxy');
    fs.mkdirSync(privateDir, { recursive: true, mode: 0o700 });
    try { fs.chmodSync(privateDir, 0o700); } catch {}
    proxyConfigPath = path.join(privateDir, 'config.json');
    fs.writeFileSync(proxyConfigPath, JSON.stringify(template, null, 2), { mode: 0o600 });
    try { fs.chmodSync(proxyConfigPath, 0o600); } catch {}

    proxy = spawn(proxyBinary, ['--config=' + proxyConfigPath], {
      cwd: ROOT,
      stdio: ['ignore', 'ignore', 'pipe'],
      env: process.env
    });
    proxy.once('error', () => fail('PROXY_SPAWN_FAILED'));
    proxy.once('exit', (code, signal) => {
      if (!stopping && state === 'ready') fail('PROXY_EXITED_' + code + '_' + (signal || 'NONE'));
    });
    proxy.stderr.on('data', () => {
      // Deliberately do not forward proxy output: it may contain wallet or pool details.
    });

    waitForTcp('127.0.0.1', 3333, 30000, proxy)
      .then(startGateway)
      .catch((error) => fail(error.message || 'PROXY_START_FAILED'));
  } catch (error) {
    fail(error.message || 'GATEWAY_CONFIGURATION_FAILED');
  }
}

function startGateway() {
  if (stopping || state === 'failed') return;

  const port = randomInt(40000, 60000);
  gateway = spawn(process.execPath, [GATEWAY_ENTRY], {
    cwd: ROOT,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: Object.assign({}, process.env, {
      GATEWAY_BIND_HOST: '127.0.0.1',
      GATEWAY_PORT: String(port),
      GATEWAY_WS_PATH: '/ws',
      POOL_PROXY_HOST: '127.0.0.1',
      POOL_PROXY_PORT: '3333'
    })
  });

  let stdoutBuffer = '';
  gateway.stdout.on('data', (chunk) => {
    stdoutBuffer += chunk.toString('utf8');
    const lines = stdoutBuffer.split('\n');
    stdoutBuffer = lines.pop() || '';
    for (const line of lines) {
      try {
        const event = JSON.parse(line);
        if (event.event === 'gateway_started' && event.port === port) {
          gatewayPort = port;
          state = 'ready';
          failureCode = null;
        }
      } catch {
        // Ignore non-JSON child output.
      }
    }
  });
  gateway.stderr.on('data', () => {
    // Do not expose child diagnostics or environment details in public responses.
  });
  gateway.once('error', () => fail('GATEWAY_SPAWN_FAILED'));
  gateway.once('exit', (code, signal) => {
    gatewayPort = null;
    if (!stopping) fail('GATEWAY_EXITED_' + code + '_' + (signal || 'NONE'));
  });

  setTimeout(() => {
    if (state === 'starting' && gatewayPort === null) fail('GATEWAY_START_TIMEOUT');
  }, 15000).unref();
}

function fail(code) {
  if (stopping) return;
  state = 'failed';
  failureCode = String(code).replace(/[^A-Z0-9_-]/gi, '_').slice(0, 80);
  gatewayPort = null;
  if (gateway && gateway.exitCode === null) gateway.kill('SIGTERM');
  if (proxy && proxy.exitCode === null) proxy.kill('SIGTERM');
}

function proxyHttpRequest(req, res, upstreamPath) {
  if (state !== 'ready' || !gatewayPort) {
    return json(res, 503, { ok: false, service: 'mine-me-pool-gateway', status: state, error: failureCode });
  }

  const headers = Object.assign({}, req.headers, { host: '127.0.0.1:' + gatewayPort });
  delete headers.connection;
  delete headers['proxy-connection'];

  const upstream = http.request({
    host: '127.0.0.1',
    port: gatewayPort,
    method: req.method,
    path: upstreamPath,
    headers
  }, (upstreamRes) => {
    res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
    upstreamRes.pipe(res);
  });

  upstream.once('error', () => {
    if (!res.headersSent) json(res, 502, { ok: false, error: 'GATEWAY_UPSTREAM_UNAVAILABLE' });
    else res.destroy();
  });
  req.pipe(upstream);
}

function proxyWebSocket(req, socket, head, upstreamPath) {
  if (state !== 'ready' || !gatewayPort) {
    socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n');
    return;
  }

  const upstream = net.connect({ host: '127.0.0.1', port: gatewayPort });
  let connected = false;

  upstream.once('connect', () => {
    connected = true;
    const lines = [
      req.method + ' ' + upstreamPath + ' HTTP/' + req.httpVersion,
      'Host: 127.0.0.1:' + gatewayPort
    ];
    for (let index = 0; index < req.rawHeaders.length; index += 2) {
      const name = req.rawHeaders[index];
      if (name.toLowerCase() !== 'host') {
        lines.push(name + ': ' + req.rawHeaders[index + 1]);
      }
    }
    upstream.write(lines.join('\r\n') + '\r\n\r\n');
    if (head && head.length) upstream.write(head);
    socket.pipe(upstream);
    upstream.pipe(socket);
  });

  upstream.once('error', () => {
    if (!connected && !socket.destroyed) {
      socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n');
    }
    socket.destroy();
  });
  socket.once('error', () => upstream.destroy());
  socket.once('close', () => upstream.destroy());
  upstream.once('close', () => socket.destroy());
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url && req.url.split('?')[0] === HEALTH_PATH) {
    return json(res, 200, {
      ok: state === 'ready',
      service: 'mine-me-sharedboost-gateway',
      status: state,
      gatewayRunning: Boolean(gateway && gateway.exitCode === null),
      proxyRunning: Boolean(proxy && proxy.exitCode === null),
      uptimeSeconds: Math.floor(process.uptime()),
      error: failureCode
    });
  }

  const upstreamPath = stripBasePath(req.url);
  if (upstreamPath === null) return json(res, 404, { error: 'NOT_FOUND' });
  proxyHttpRequest(req, res, upstreamPath);
});

server.on('upgrade', (req, socket, head) => {
  const upstreamPath = stripBasePath(req.url);
  if (upstreamPath === null) {
    socket.end('HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n');
    return;
  }
  proxyWebSocket(req, socket, head, upstreamPath);
});

function shutdown() {
  if (stopping) return;
  stopping = true;
  state = 'stopping';
  server.close();
  if (gateway && gateway.exitCode === null) gateway.kill('SIGTERM');
  if (proxy && proxy.exitCode === null) proxy.kill('SIGTERM');
  if (proxyConfigPath) {
    try { fs.unlinkSync(proxyConfigPath); } catch {}
  }
}

process.once('SIGTERM', shutdown);
process.once('SIGINT', shutdown);

server.listen();
startProxyAndGateway();
