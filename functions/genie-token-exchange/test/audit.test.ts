import assert from 'node:assert/strict';
import { test } from 'node:test';
import { auditEvent } from '../src/audit.js';

test('audit events retain outcomes and correlation but never arbitrary caller text', () => {
  const correlation = '11111111-1111-1111-1111-111111111111';
  const success = JSON.parse(auditEvent(correlation, 'invocation', 200, 'exchanged', 12.6));
  assert.equal(success.correlationId, correlation);
  assert.equal(success.outcome, 'success');
  assert.equal(success.durationMs, 13);
  const failure = auditEvent('Bearer secret-token', 'invocation', 401, 'secret token detail', 1);
  assert.equal(JSON.parse(failure).outcome, 'failure');
  assert.equal(JSON.parse(failure).correlationId, 'invocation');
  assert.doesNotMatch(failure, /secret|Bearer/);
});