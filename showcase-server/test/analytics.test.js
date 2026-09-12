'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { normalizeIp, clientIp, createVisit, parseRange, summarize, isStatsAdmin } = require('../analytics');

test('bundled GeoIP database resolves locally without a network service', () => {
  const geoip = require('geoip-lite');
  const location = geoip.lookup('8.8.8.8');
  assert.equal(typeof location.country, 'string');
  assert.equal(typeof location.region, 'string');
  assert.equal(typeof location.city, 'string');
});

test('canonicalizes public addresses and ignores forged leading proxy headers', () => {
  assert.equal(normalizeIp('::ffff:8.8.8.8'), '8.8.8.8');
  assert.equal(normalizeIp('8.8.8.8:12345'), '8.8.8.8');
  assert.equal(normalizeIp('[2001:4860:4860::8888]:443'), '2001:4860:4860::8888');
  for (const value of ['127.0.0.1', '10.1.2.3', '::1', 'invalid']) assert.equal(normalizeIp(value), null);
  assert.equal(clientIp({ headers: { 'x-forwarded-for': '1.1.1.1, 8.8.8.8:123' }, socket: {} }, true), '8.8.8.8');
  assert.equal(clientIp({ headers: {}, socket: {} }, true), null);
});

test('counts distinct IPs across the range, not sums of daily or location uniques', () => {
  const visits = [
    createVisit('8.8.8.8', '/', () => ({ country: 'US', region: 'CA', city: 'Mountain View' }), new Date('2026-08-31T23:00:00Z')),
    createVisit('8.8.8.8', '/showcase', () => ({ country: 'CA', region: 'ON', city: 'Toronto' }), new Date('2026-09-01T01:00:00Z')),
    createVisit('1.1.1.1', '/', () => null, new Date('2026-09-01T02:00:00Z')),
    createVisit(null, '/', () => null, new Date('2026-09-01T03:00:00Z')),
  ];
  const range = parseRange({ start: '2026-08-31', end: '2026-09-02', period: 'day' }, new Date('2026-09-11'));
  const result = summarize(visits, range);
  assert.equal(result.totalVisits, 4);
  assert.equal(result.uniqueIps, 2);
  assert.equal(result.unknownIpVisits, 1);
  assert.deepEqual(result.periods.map(entry => [entry.visits, entry.uniqueIps]), [[1, 1], [3, 2], [0, 0]]);
  assert.equal(summarize(visits, { ...range, period: 'month' }).periods.length, 2);
  assert.equal(summarize(visits, { ...range, period: 'year' }).periods[0].uniqueIps, 2);
  assert.equal(result.recentVisits[0].timestamp, '2026-09-01T03:00:00.000Z');
});

test('validates date ranges and produces complete empty buckets', () => {
  const now = new Date('2026-09-11T15:00:00Z');
  for (const query of [{ start: "' OR true" }, { start: '2026-02-30' }, { start: '2020-01-01' }, { end: '2030-01-01' }, { period: 'hour' }]) {
    assert.throws(() => parseRange(query, now));
  }
  const result = summarize([], parseRange({}, now));
  assert.equal(result.periods.length, 30);
  assert.equal(result.uniqueIps, 0);
});

test('requires a platform-authenticated principal, correct tenant, and explicit admin allowlist', () => {
  const encode = data => Buffer.from(JSON.stringify(data)).toString('base64');
  const principal = { auth_typ: 'aad', claims: [{ typ: 'tid', val: 'tenant' }, { typ: 'oid', val: 'admin' }] };
  assert.equal(isStatsAdmin(encode(principal), 'tenant', ['admin']), true);
  assert.equal(isStatsAdmin(encode(principal), 'other', ['admin']), false);
  assert.equal(isStatsAdmin(encode(principal), 'tenant', ['someone-else']), false);
  assert.equal(isStatsAdmin(undefined, 'tenant', ['admin']), false);
  assert.equal(isStatsAdmin('invalid', 'tenant', ['admin']), false);
});