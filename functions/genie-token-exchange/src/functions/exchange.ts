import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from '@azure/functions';
import { BrokerError, createBroker, loadConfig } from '../broker.js';
import { auditEvent } from '../audit.js';

let broker: ReturnType<typeof createBroker> | undefined;

export async function exchange(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
  const headers = { 'Cache-Control': 'no-store', Pragma: 'no-cache' };
  const started = performance.now();
  let status = 503;
  let code = 'broker_unavailable';
  try {
    broker ??= createBroker(loadConfig(process.env));
    const authorization = request.headers.get('authorization') ?? '';
    if (!authorization.startsWith('Bearer ')) throw new BrokerError(401, 'invalid_token');
    const result = await broker(authorization.slice(7), request.headers.get('x-user-assertion') ?? '');
    status = 200;
    code = 'exchanged';
    return { status: 200, headers, jsonBody: result };
  } catch (error) {
    const failure = error instanceof BrokerError ? error : new BrokerError(503, 'broker_unavailable');
    status = failure.status;
    code = failure.code;
    return { status: failure.status, headers, jsonBody: { error: failure.code } };
  } finally {
    context.log(auditEvent(request.headers.get('x-correlation-id'), context.invocationId, status, code, performance.now() - started));
  }
}

app.http('exchange', { methods: ['POST'], route: 'exchange', authLevel: 'anonymous', handler: exchange });