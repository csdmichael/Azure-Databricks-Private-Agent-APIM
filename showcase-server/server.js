'use strict';

const path = require('node:path');
const express = require('express');
const { CosmosClient } = require('@azure/cosmos');
const { ManagedIdentityCredential } = require('@azure/identity');
const geoip = require('geoip-lite');
const { clientIp, createVisit, parseRange, summarize, isStatsAdmin } = require('./analytics');
const { historyFilter, historyStore } = require('./history');

function cosmosStore(env) {
  if (!env.COSMOS_ENDPOINT) throw new Error('COSMOS_ENDPOINT is required');
  const client = new CosmosClient({
    endpoint: env.COSMOS_ENDPOINT, aadCredentials: new ManagedIdentityCredential(),
    connectionPolicy: { requestTimeout: 4000, retryOptions: { maxRetryAttemptCount: 1, maxWaitTimeInSeconds: 2 } },
  });
  const container = client.database('showcase-analytics').container('visits');
  return {
    record: visit => container.items.create(visit),
    async read(range) {
      const iterator = container.items.query({
        query: 'SELECT c.timestamp, c.day, c.ip, c.country, c.state, c.city, c.path FROM c WHERE c.day >= @start AND c.day <= @end',
        parameters: [{ name: '@start', value: range.start }, { name: '@end', value: range.end }],
      }, { maxItemCount: 1000 });
      const visits = [];
      while (iterator.hasMoreResults()) {
        const page = await iterator.fetchNext();
        visits.push(...page.resources);
        if (visits.length > 100000) {
          const error = new Error('The selected range is too large. Choose fewer days.');
          error.status = 422;
          throw error;
        }
      }
      return visits;
    },
  };
}

function createApp({ store, env = process.env, lookup = geoip.lookup, staticRoot = path.join(__dirname, 'public'), logs = historyStore(env) }) {
  const server = express();
  server.disable('x-powered-by');
  server.use((_request, response, next) => {
    response.set({ 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'strict-origin-when-cross-origin' });
    next();
  });
  server.get('/api/visits/stats', async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const admins = (env.STATS_ADMIN_OBJECT_IDS ?? '').split(',').map(value => value.trim()).filter(Boolean);
    const principal = request.headers['x-ms-client-principal'];
    if (!env.WEBSITE_INSTANCE_ID || !isStatsAdmin(principal, env.ENTRA_TENANT_ID, admins)) {
      return response.status(principal ? 403 : 401).json({ error: 'An authorized administrator must sign in.' });
    }
    let range;
    try { range = parseRange(request.query); }
    catch (error) { return response.status(400).json({ error: error.message }); }
    try {
      const visits = await store.read(range);
      return response.json(summarize(visits, range));
    } catch (error) {
      if (error.status === 422) return response.status(422).json({ error: error.message });
      console.error('Analytics query failed');
      return response.status(503).json({ error: 'Visitor statistics are temporarily unavailable.' });
    }
  });
  server.get('/api/health', (_request, response) => response.json({ status: 'ok' }));
  server.get('/api/exchanges/history', async (request, response) => {
    response.set('Cache-Control', 'no-store');
    const admins = (env.STATS_ADMIN_OBJECT_IDS ?? '').split(',').map(value => value.trim()).filter(Boolean);
    const principal = request.headers['x-ms-client-principal'];
    if (!env.WEBSITE_INSTANCE_ID || !isStatsAdmin(principal, env.ENTRA_TENANT_ID, admins)) {
      return response.status(principal ? 403 : 401).json({ error: 'An authorized administrator must sign in.' });
    }
    let filter;
    try { filter = historyFilter(request.query); }
    catch (error) { return response.status(400).json({ error: error.message }); }
    try { return response.json(await logs.read(filter)); }
    catch (error) {
      return response.status(error.status === 422 ? 422 : 503).json({ error: error.status === 422 ? error.message : 'Request history is temporarily unavailable.' });
    }
  });
  server.use('/api', (_request, response) => response.status(404).json({ error: 'Not found' }));
  server.get(['/', '/showcase', '/showcase/', '/index.html'], async (request, response, next) => {
    response.set('Cache-Control', 'no-store');
    if (request.method === 'GET') {
      try {
        await store.record(createVisit(clientIp(request, Boolean(env.WEBSITE_INSTANCE_ID)), request.path, lookup));
      } catch { console.error('Visit persistence failed'); }
    }
    response.sendFile(path.join(staticRoot, 'index.html'), error => { if (error) next(error); });
  });
  server.use(express.static(staticRoot, { index: false, dotfiles: 'deny' }));
  server.get(['/stats', '/privacy', '/packages', '/history'], (_request, response) => {
    response.set('Cache-Control', 'no-store').sendFile(path.join(staticRoot, 'index.html'));
  });
  server.use((_request, response) => response.status(404).send('Not found'));
  return server;
}

if (require.main === module) {
  const server = createApp({ store: cosmosStore(process.env) });
  server.listen(process.env.PORT || 8080);
}

module.exports = { createApp, cosmosStore };