import type { HttpRequest, InvocationContext } from '@azure/functions';
import { createTokenVerifier } from './auth.js';
import { loadConfig, type BrokerConfig, type DownstreamTarget } from './config.js';
import { BrokerError } from './errors.js';
import { createDataAgentClient } from './mcp.js';
import { createTokenExchanger } from './obo.js';
import { assertReadOnlyStatement, executeQuery, tableListStatement } from './sql.js';

export interface Runtime {
  config: BrokerConfig;
  authorize(request: HttpRequest): Promise<{ assertion: string; objectId: string; expiresAt: number }>;
  exchange(assertion: string, target: DownstreamTarget, expiresAt: number): Promise<{ accessToken: string; expiresIn: number }>;
  query(token: string, statement: string): ReturnType<typeof executeQuery>;
  askDataAgent(token: string, question: string): Promise<Record<string, unknown>>;
}

export function createRuntime(config = loadConfig(process.env)): Runtime {
  const verify = createTokenVerifier(config);
  const exchange = createTokenExchanger(config);
  const askDataAgent = createDataAgentClient(config);
  return {
    config,
    async authorize(request) {
      const assertion = request.headers.get('x-user-assertion') ?? '';
      const identity = await verify(request.headers.get('authorization') ?? '', assertion);
      return { assertion, ...identity };
    },
    exchange,
    query: (token, statement) => executeQuery(config, token, assertReadOnlyStatement(statement, config.maxStatementLength)),
    askDataAgent,
  };
}

let singleton: Runtime | undefined;
export function runtime(): Runtime {
  singleton ??= createRuntime();
  return singleton;
}

export function audit(context: InvocationContext, route: string, status: number, objectId?: string): void {
  context.log(JSON.stringify({
    event: 'fabric_obo_request', route, status,
    invocationId: context.invocationId,
    userObjectId: objectId ?? null,
  }));
}

export function statementFromBody(body: unknown): string {
  if (!body || typeof body !== 'object' || typeof (body as { statement?: unknown }).statement !== 'string') {
    throw new BrokerError(400, 'invalid_request');
  }
  return (body as { statement: string }).statement;
}

export function questionFromBody(body: unknown): string {
  if (!body || typeof body !== 'object' || typeof (body as { question?: unknown }).question !== 'string') {
    throw new BrokerError(400, 'invalid_request');
  }
  const question = (body as { question: string }).question.trim();
  if (!question || question.length > 4000 || /[\0\r]/.test(question)) throw new BrokerError(400, 'invalid_request');
  return question;
}

export { tableListStatement };