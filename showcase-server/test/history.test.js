'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { historyFilter, buildQuery, groupHistory, historyStore } = require('../history');
const filter = { start: '2026-09-01', end: '2026-09-12', outcome: 'all', user: '' };
const resource = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/test/providers/Microsoft.Insights/components/obo';

test('groups by request id, not user/time, and separates API from exchange outcomes', () => {
  const event = (correlationId, stage, timestamp, extra = {}) => ({ correlationId, stage, timestamp, source: 'apim', userId: 'same-user', user: 'admin@example.com', ...extra });
  const result = groupHistory([
    event('request-1', 'request_completed', '2026-09-12T10:00:03Z', { outcome: 'failure', status: 403, durationMs: 300 }),
    event('request-1', '', '2026-09-12T10:00:02Z', { source: 'function', outcome: 'success', userId: '', user: '' }),
    event('request-1', 'token_exchange_completed', '2026-09-12T10:00:02Z', { outcome: 'success' }),
    event('request-2', 'request_completed', '2026-09-12T10:00:04Z', { outcome: 'success', durationMs: 100 }),
    event('request-3', 'request_started', '2026-09-12T10:00:05Z', { userId: '', user: '' }),
  ], filter);
  assert.deepEqual(result.requests.map(request => request.correlationId), ['request-3', 'request-2', 'request-1']);
  assert.equal(result.requests[2].events.length, 3);
  assert.equal(result.requests[2].exchangeOutcome, 'success');
  assert.equal(result.stats.exchangeSuccess, 1);
  assert.equal(result.stats.failure, 1);
  assert.equal(result.stats.pending, 1);
  assert.equal(result.stats.averageDurationMs, 200);
  assert.equal(groupHistory(result.requests.flatMap(request => request.events), { ...filter, user: 'admin', outcome: 'failure' }).requests.length, 1);
});
test('defaults to last 30 UTC dates and prevents query injection', () => {
  const range = historyFilter({}, new Date('2026-09-12T12:00:00Z'));
  assert.equal(range.start, '2026-08-14');
  assert.throws(() => historyFilter({ start: "2026-09-01');union *" }));
  assert.throws(() => historyFilter({ outcome: 'arbitrary' }));
  assert.throws(() => buildQuery(filter, "resource';union *"));
  const query = buildQuery(filter, resource);
  assert.match(query, /order by timestamp desc/);
  assert.match(query, /take 10001/);
});
test('partial logs are not presented as complete history', async () => {
  const store = historyStore({ LOG_ANALYTICS_WORKSPACE_ID: '11111111-1111-1111-1111-111111111111', LOG_ANALYTICS_RESOURCE_ID: resource },
    { getToken: async () => ({ token: 'test' }) }, async () => Response.json({ error: { code: 'PartialError' }, tables: [] }));
  await assert.rejects(store.read(filter), /Incomplete log query/);
});