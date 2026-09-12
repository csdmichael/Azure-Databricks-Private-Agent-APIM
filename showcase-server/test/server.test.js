'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { readFileSync } = require('node:fs');
const { createApp } = require('../server');

test('IISNode entry starts when required by a wrapper', () => {
  const entry = path.resolve(__dirname, '../iisnode.js');
  const probe = `
    const assert = require('node:assert/strict');
    const http = require('node:http');
    process.env.PORT = process.platform === 'win32'
      ? String.raw\`\\\\.\\pipe\\showcase-test-\` + require('node:crypto').randomUUID() : '0';
    process.env.COSMOS_ENDPOINT = 'https://example.documents.azure.com:443/';
    const server = require(${JSON.stringify(entry)});
    server.on('listening', () => {
      const address = server.address();
      const options = typeof address === 'string' ? { socketPath: address } : { port: address.port };
      http.get({ ...options, path: '/api/health' }, response => {
        let body = '';
        response.on('data', chunk => { body += chunk; });
        response.on('end', () => {
          try {
            assert.equal(response.statusCode, 200);
            assert.deepEqual(JSON.parse(body), { status: 'ok' });
          } finally { server.close(); }
        });
      }).on('error', error => { server.close(); throw error; });
    });
  `;
  execFileSync(process.execPath, ['-e', probe], { timeout: 15000 });
  const config = readFileSync(path.resolve(__dirname, '../web.config'), 'utf8');
  assert.match(config, /path="iisnode\.js"/);
  assert.match(config, /type="Rewrite" url="iisnode\.js"/);
  const deployment = readFileSync(path.resolve(__dirname, '../../scripts/deploy-showcase-analytics.ps1'), 'utf8');
  assert.match(deployment, /foreach \(\$name in @\('iisnode\.js'/);
  assert.match(deployment, /--http1\.1.+-H 'Expect:'.+-T \$zipPath/);
  assert.match(deployment, /api\/publish\?type=zip&clean=true&restart=false/);
});

test('document visits are recorded once; existing SPA routes remain available', async () => {
  const records = [];
  const app = createApp({
    store: { async read() { return []; }, async record(visit) { records.push(visit); } },
    env: {}, staticRoot: path.resolve(__dirname, '../../ui/www'),
  });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    for (const route of ['/showcase?private=value', '/packages', '/stats', '/privacy']) {
      const response = await fetch(`${base}${route}`);
      assert.equal(response.status, 200);
      assert.match(await response.text(), /<app-root/);
    }
    await fetch(`${base}/showcase`, { method: 'HEAD' });
    assert.equal(records.length, 1);
    assert.equal(records[0].path, '/showcase');
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('anonymous stats requests cannot query storage; health is public', async () => {
  let reads = 0;
  const app = createApp({ store: { async read() { reads++; return []; }, async record() {} }, env: {} });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const base = `http://127.0.0.1:${server.address().port}`;
    const stats = await fetch(`${base}/api/visits/stats`);
    assert.equal(stats.status, 401);
    assert.equal(stats.headers.get('cache-control'), 'no-store');
    assert.equal(reads, 0);
    assert.equal((await fetch(`${base}/api/health`)).status, 200);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('authorized platform identity receives summaries, no other principal does', async () => {
  let reads = 0;
  const env = { WEBSITE_INSTANCE_ID: 'platform', ENTRA_TENANT_ID: 'tenant', STATS_ADMIN_OBJECT_IDS: 'admin' };
  const app = createApp({ store: { async read() { reads++; return []; }, async record() {} }, env });
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const principal = oid => Buffer.from(JSON.stringify({ auth_typ: 'aad', claims: [{ typ: 'tid', val: 'tenant' }, { typ: 'oid', val: oid }] })).toString('base64');
  try {
    const url = `http://127.0.0.1:${server.address().port}/api/visits/stats`;
    assert.equal((await fetch(url, { headers: { 'x-ms-client-principal': principal('other') } })).status, 403);
    const allowed = await fetch(url, { headers: { 'x-ms-client-principal': principal('admin') } });
    assert.equal(allowed.status, 200);
    assert.equal((await allowed.json()).totalVisits, 0);
    assert.equal(reads, 1);
  } finally { await new Promise(resolve => server.close(resolve)); }
});