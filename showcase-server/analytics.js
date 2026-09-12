'use strict';

const { randomUUID } = require('node:crypto');
const ipaddr = require('ipaddr.js');

function normalizeIp(value) {
  if (typeof value !== 'string' || value.length > 128) return null;
  let address = value.trim();
  const bracketed = address.match(/^\[([^\]]+)\](?::\d+)?$/);
  if (bracketed) address = bracketed[1];
  if (/^\d+\.\d+\.\d+\.\d+:\d+$/.test(address)) address = address.slice(0, address.lastIndexOf(':'));
  try {
    const parsed = ipaddr.process(address);
    return parsed.range() === 'unicast' ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function clientIp(request, behindAzure) {
  if (!behindAzure) return normalizeIp(request.socket.remoteAddress);
  const chain = request.headers['x-forwarded-for'];
  if (typeof chain !== 'string' || chain.length > 4096) return null;
  return normalizeIp(chain.split(',').at(-1));
}

function createVisit(ip, path, lookup, now = new Date()) {
  const location = ip ? lookup(ip) : null;
  return {
    id: randomUUID(), day: now.toISOString().slice(0, 10), timestamp: now.toISOString(),
    ip, country: location?.country || 'Unknown', state: location?.region || 'Unknown',
    city: location?.city || 'Unknown', path, ttl: 90 * 24 * 60 * 60,
  };
}

function parseRange(query, now = new Date()) {
  const today = now.toISOString().slice(0, 10);
  const oldest = new Date(now.getTime() - 89 * 86400000).toISOString().slice(0, 10);
  const start = query.start ?? new Date(now.getTime() - 29 * 86400000).toISOString().slice(0, 10);
  const end = query.end ?? today;
  for (const value of [start, end]) {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)
        || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) {
      throw new Error('Dates must use YYYY-MM-DD.');
    }
  }
  if (start > end || start < oldest || end > today) throw new Error('Choose a range within the last 90 UTC calendar days.');
  const period = query.period ?? 'day';
  if (!['day', 'month', 'year'].includes(period)) throw new Error('Period must be day, month, or year.');
  return { start, end, period, oldest, today };
}

function summarize(visits, range) {
  const unique = new Set();
  const periods = new Map();
  const locations = new Map();
  let unknownIpVisits = 0;
  const bucket = (map, key, fields) => {
    if (!map.has(key)) map.set(key, { ...fields, visits: 0, ips: new Set() });
    return map.get(key);
  };
  for (const visit of visits) {
    if (visit.ip) unique.add(visit.ip); else unknownIpVisits++;
    const label = visit.day.slice(0, range.period === 'day' ? 10 : range.period === 'month' ? 7 : 4);
    const time = bucket(periods, label, { period: label });
    const place = { country: visit.country, state: visit.state, city: visit.city };
    const location = bucket(locations, JSON.stringify(place), place);
    for (const target of [time, location]) {
      target.visits++;
      if (visit.ip) target.ips.add(visit.ip);
    }
  }
  const cursor = new Date(`${range.start}T00:00:00Z`);
  while (cursor.toISOString().slice(0, 10) <= range.end) {
    const label = cursor.toISOString().slice(0, range.period === 'day' ? 10 : range.period === 'month' ? 7 : 4);
    bucket(periods, label, { period: label });
    cursor.setUTCDate(cursor.getUTCDate() + 1);
  }
  const serialize = ({ ips, ...entry }) => ({ ...entry, uniqueIps: ips.size });
  return {
    range, totalVisits: visits.length, uniqueIps: unique.size, unknownIpVisits,
    periods: [...periods.values()].map(serialize).sort((left, right) => left.period.localeCompare(right.period)),
    locations: [...locations.values()].map(serialize).sort((left, right) => right.visits - left.visits),
    recentVisits: [...visits].sort((left, right) => right.timestamp.localeCompare(left.timestamp)).slice(0, 100)
      .map(({ timestamp, ip, country, state, city, path }) => ({ timestamp, ip, country, state, city, path })),
    retentionDays: 90, timeZone: 'UTC', generatedAt: new Date().toISOString(),
  };
}

function isStatsAdmin(principalHeader, tenantId, allowedIds) {
  if (!tenantId || !allowedIds.length || typeof principalHeader !== 'string' || principalHeader.length > 32768) return false;
  try {
    const principal = JSON.parse(Buffer.from(principalHeader, 'base64').toString('utf8'));
    if (principal.auth_typ !== 'aad' || !Array.isArray(principal.claims)) return false;
    const claim = (...names) => principal.claims.find(entry => names.includes(entry.typ))?.val;
    return claim('tid', 'http://schemas.microsoft.com/identity/claims/tenantid') === tenantId
      && allowedIds.includes(claim('oid', 'http://schemas.microsoft.com/identity/claims/objectidentifier'));
  } catch { return false; }
}

module.exports = { normalizeIp, clientIp, createVisit, parseRange, summarize, isStatsAdmin };