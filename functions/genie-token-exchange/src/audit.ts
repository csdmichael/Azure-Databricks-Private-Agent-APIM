export function auditEvent(correlationId: string | null, invocationId: string, status: number, code: string, durationMs: number): string {
  const correlation = correlationId && /^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(correlationId) ? correlationId : invocationId;
  return JSON.stringify({
    event: 'genie_token_exchange', source: 'function', correlationId: correlation,
    invocationId, outcome: status === 200 ? 'success' : 'failure', status,
    code: /^[a-z_]{1,64}$/.test(code) ? code : 'unknown_error', durationMs: Math.max(0, Math.round(durationMs)),
  });
}