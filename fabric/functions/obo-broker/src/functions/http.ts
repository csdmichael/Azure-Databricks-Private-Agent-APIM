import { app, type HttpRequest, type HttpResponseInit, type InvocationContext } from '@azure/functions';
import type { DownstreamTarget } from '../config.js';
import { BrokerError, safeError } from '../errors.js';
import { audit, questionFromBody, runtime, statementFromBody, tableListStatement } from '../runtime.js';

const noStoreHeaders = { 'Cache-Control': 'no-store', Pragma: 'no-cache' };

async function handle(route: string, request: HttpRequest, context: InvocationContext,
  action: (body: unknown, objectId: string, assertion: string, expiresAt: number) => Promise<unknown>): Promise<HttpResponseInit> {
  let objectId: string | undefined;
  let status = 503;
  try {
    const identity = await runtime().authorize(request);
    objectId = identity.objectId;
    const body = request.method === 'GET' ? undefined : await request.json().catch(() => undefined);
    const result = await action(body, identity.objectId, identity.assertion, identity.expiresAt);
    status = 200;
    return { status, headers: noStoreHeaders, jsonBody: result };
  } catch (error) {
    const failure = safeError(error);
    status = failure.status;
    return { status, headers: noStoreHeaders, jsonBody: { error: failure.code } };
  } finally {
    audit(context, route, status, objectId);
  }
}

app.http('health', {
  methods: ['GET'], route: 'health', authLevel: 'anonymous',
  handler: async () => ({ status: 200, headers: noStoreHeaders, jsonBody: { status: 'ok' } }),
});

app.http('exchange', {
  methods: ['POST'], route: 'exchange', authLevel: 'anonymous',
  handler: (request, context) => handle('exchange', request, context, async (body, _objectId, assertion, expiresAt) => {
    const target = (body as { target?: unknown } | undefined)?.target;
    if (target !== 'fabric' && target !== 'powerbi') throw new BrokerError(400, 'invalid_target');
    const token = await runtime().exchange(assertion, target as DownstreamTarget, expiresAt);
    return { access_token: token.accessToken, token_type: 'Bearer', expires_in: token.expiresIn };
  }),
});

app.http('query', {
  methods: ['POST'], route: 'lakehouse/query', authLevel: 'anonymous',
  handler: (request, context) => handle('lakehouse_query', request, context, async (body, _objectId, assertion, expiresAt) => {
    const statement = statementFromBody(body);
    const token = await runtime().exchange(assertion, 'powerbi', expiresAt);
    return runtime().query(token.accessToken, statement);
  }),
});

app.http('tables', {
  methods: ['GET'], route: 'lakehouse/tables', authLevel: 'anonymous',
  handler: (request, context) => handle('lakehouse_tables', request, context, async (_body, _objectId, assertion, expiresAt) => {
    const token = await runtime().exchange(assertion, 'powerbi', expiresAt);
    return runtime().query(token.accessToken, tableListStatement());
  }),
});

app.http('dataAgent', {
  methods: ['POST'], route: 'data-agent/query', authLevel: 'anonymous',
  handler: (request, context) => handle('data_agent_query', request, context, async (body, _objectId, assertion, expiresAt) => {
    const question = questionFromBody(body);
    const token = await runtime().exchange(assertion, 'fabric', expiresAt);
    return runtime().askDataAgent(token.accessToken, question);
  }),
});