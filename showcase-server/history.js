'use strict';
const { ManagedIdentityCredential } = require('@azure/identity');
const { parseRange } = require('./analytics');

function historyFilter(query, now = new Date()) {
  const range = parseRange({ start: query.start, end: query.end, period: 'day' }, now);
  const outcome = query.outcome ?? 'all';
  if (!['all', 'success', 'failure', 'pending'].includes(outcome)) throw new Error('Invalid outcome filter.');
  const user = query.user ?? '';
  if (typeof user !== 'string' || user.length > 200) throw new Error('Invalid user filter.');
  return { ...range, outcome, user: user.trim().toLowerCase() };
}

function positiveInteger(env, name) {
  const value = Number(env[name]);
  if (!Number.isSafeInteger(value) || value < 1) throw new Error(`${name} must be a positive integer`);
  return value;
}

function buildQuery(range, resourceId, queryMaxResults) {
  if (!/^\/subscriptions\/[a-f0-9-]+\/resourceGroups\/[\w.-]+\/providers\/Microsoft.Insights\/components\/[\w.-]+$/i.test(resourceId ?? '')) {
    throw new Error('LOG_ANALYTICS_RESOURCE_ID must identify the OBO Application Insights resource');
  }
  if (!Number.isSafeInteger(queryMaxResults) || queryMaxResults < 1) throw new Error('Invalid Log Analytics result limit');
  return `AppTraces
| where TimeGenerated >= datetime(${range.start}) and TimeGenerated < datetime(${range.end}) + 1d
| where _ResourceId =~ '${resourceId}'
| where Message startswith '{'
| extend audit = parse_json(Message)
| where tostring(audit.event) in ('genie_request', 'genie_token_exchange')
| project timestamp=TimeGenerated, event=tostring(audit.event), source=tostring(audit.source), correlationId=tostring(audit.correlationId), stage=tostring(audit.stage), outcome=tostring(audit.outcome), status=toint(audit.status), userId=tostring(audit.userId), user=tostring(audit.user), operation=tostring(audit.operation), method=tostring(audit.method), durationMs=todouble(audit.durationMs), code=tostring(audit.code), invocationId=tostring(audit.invocationId)
| order by timestamp desc
| take ${queryMaxResults}`;
}

function groupHistory(events, filter) {
  const groups = new Map();
  for (const event of events) {
    if (!event.correlationId) continue;
    const group = groups.get(event.correlationId) ?? { correlationId: event.correlationId, events: [] };
    group.events.push(event);
    groups.set(event.correlationId, group);
  }
  const requests = [...groups.values()].map(group => {
    group.events.sort((left, right) => right.timestamp.localeCompare(left.timestamp));
    const completed = group.events.find(event => event.source === 'apim' && event.stage === 'request_completed');
    const identity = group.events.find(event => event.source === 'apim' && event.userId);
    const api = group.events.find(event => event.source === 'apim');
    const exchange = group.events.find(event => event.source === 'function')
      ?? group.events.find(event => event.stage === 'token_exchange_completed');
    return { ...group, timestamp: group.events[0].timestamp, user: identity?.user || '', userId: identity?.userId || '',
      operation: api?.operation || '', method: api?.method || '', status: completed?.status ?? null,
      outcome: completed?.outcome ?? 'pending', durationMs: completed?.durationMs ?? null,
      exchangeOutcome: exchange?.outcome ?? 'not-observed', incomplete: !completed };
  }).filter(group => (filter.outcome === 'all' || group.outcome === filter.outcome)
    && `${group.user} ${group.userId}`.toLowerCase().includes(filter.user))
    .sort((left, right) => right.timestamp.localeCompare(left.timestamp));
  const count = outcome => requests.filter(request => request.outcome === outcome).length;
  const duration = requests.filter(request => Number.isFinite(request.durationMs));
  return { requests, stats: { requests: requests.length, success: count('success'), failure: count('failure'), pending: count('pending'),
    exchangeSuccess: requests.filter(request => request.exchangeOutcome === 'success').length,
    exchangeFailure: requests.filter(request => request.exchangeOutcome === 'failure').length,
    averageDurationMs: duration.length ? Math.round(duration.reduce((total, request) => total + request.durationMs, 0) / duration.length) : null },
    generatedAt: new Date().toISOString(), timeZone: 'UTC' };
}

function historyStore(env, credential = new ManagedIdentityCredential(), request = fetch) {
  const queryTimeoutMs = positiveInteger(env, 'LOG_ANALYTICS_QUERY_TIMEOUT_MS');
  const queryMaxResults = positiveInteger(env, 'LOG_ANALYTICS_QUERY_MAX_RESULTS');
  return {
    async read(filter) {
      if (!/^[a-f0-9-]{36}$/i.test(env.LOG_ANALYTICS_WORKSPACE_ID ?? '')) throw new Error('Log workspace is not configured');
      const kql = buildQuery(filter, env.LOG_ANALYTICS_RESOURCE_ID, queryMaxResults);
      const token = await credential.getToken('https://api.loganalytics.io/.default');
      const response = await request(`https://api.loganalytics.io/v1/workspaces/${env.LOG_ANALYTICS_WORKSPACE_ID}/query`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(queryTimeoutMs),
        headers: { Authorization: `Bearer ${token.token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ query: kql }),
      });
      if (!response.ok) throw new Error('Log query unavailable');
      const data = await response.json();
      if (data.error || !Array.isArray(data.tables) || !data.tables[0]) throw new Error('Incomplete log query');
      const table = data.tables[0];
      if (table.rows.length >= queryMaxResults) {
        const error = new Error(`At least ${queryMaxResults.toLocaleString()} events matched. Select a shorter date range.`);
        error.status = 422;
        throw error;
      }
      const events = table.rows.map(row => Object.fromEntries(table.columns.map((column, index) => [column.name, row[index]])));
      return { ...groupHistory(events, filter), kql, filters: filter };
    },
  };
}
module.exports = { historyFilter, buildQuery, groupHistory, historyStore };