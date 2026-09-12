import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';

export interface BrokerConfig {
  tenantId: string;
  audience: string;
  brokerAudience: string;
  apimPrincipalId: string;
  clientIds: string[];
  scope: string;
  workspaceUrl: string;
}

export class BrokerError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code);
  }
}

export function loadConfig(env: NodeJS.ProcessEnv): BrokerConfig {
  const required = (name: string): string => {
    const value = env[name]?.trim();
    if (!value) throw new Error(`Missing ${name}`);
    return value;
  };
  const config: BrokerConfig = {
    tenantId: required('ENTRA_TENANT_ID'),
    audience: required('ENTRA_API_CLIENT_ID'),
    brokerAudience: required('BROKER_AUDIENCE'),
    apimPrincipalId: required('APIM_PRINCIPAL_ID'),
    clientIds: required('ALLOWED_CLIENT_IDS').split(',').map(value => value.trim()).filter(Boolean),
    scope: 'Genie.Access',
    workspaceUrl: required('DATABRICKS_WORKSPACE_URL'),
  };
  const workspace = new URL(config.workspaceUrl);
  if (workspace.protocol !== 'https:' || !/^adb-[0-9]+\.[0-9]+\.azuredatabricks\.net$/.test(workspace.hostname)
      || workspace.port || workspace.username || workspace.password || workspace.search || workspace.hash
      || workspace.pathname !== '/' || !config.clientIds.length
      || !/^[0-9a-f-]{36}$/i.test(config.tenantId)) {
    throw new Error('Invalid broker configuration');
  }
  config.workspaceUrl = workspace.origin;
  return config;
}

export function createBroker(config: BrokerConfig, keys?: JWTVerifyGetKey, request: typeof fetch = fetch) {
  const signingKeys = keys ?? createRemoteJWKSet(
    new URL(`https://login.microsoftonline.com/${config.tenantId}/discovery/v2.0/keys`),
    { timeoutDuration: 5000 },
  );
  return async (callerToken: string, userToken: string) => {
    if (!callerToken || !userToken || callerToken.length > 32768 || userToken.length > 32768) {
      throw new BrokerError(401, 'invalid_token');
    }
    let userExpiry: number;
    try {
      const caller = (await jwtVerify(callerToken, signingKeys, {
        issuer: [`https://sts.windows.net/${config.tenantId}/`, `https://login.microsoftonline.com/${config.tenantId}/v2.0`],
        audience: config.brokerAudience,
        algorithms: ['RS256'],
        requiredClaims: ['exp', 'iat', 'nbf', 'tid', 'oid'],
      })).payload;
      if (caller.tid !== config.tenantId || caller.oid !== config.apimPrincipalId || caller.scp) {
        throw new Error('Invalid broker caller');
      }
      const user = (await jwtVerify(userToken, signingKeys, {
        issuer: `https://login.microsoftonline.com/${config.tenantId}/v2.0`,
        audience: config.audience,
        algorithms: ['RS256'],
        requiredClaims: ['exp', 'iat', 'nbf', 'tid', 'oid', 'azp', 'scp', 'preferred_username'],
      })).payload;
      if (user.tid !== config.tenantId || user.idtyp === 'app'
          || typeof user.azp !== 'string' || !config.clientIds.includes(user.azp)
          || typeof user.scp !== 'string' || !user.scp.split(' ').includes(config.scope)
          || typeof user.preferred_username !== 'string' || !user.preferred_username.trim()
          || typeof user.oid !== 'string' || !user.oid) {
        throw new Error('Invalid delegated user');
      }
      userExpiry = user.exp!;
    } catch {
      throw new BrokerError(401, 'invalid_token');
    }
    let response: Response;
    try {
      response = await request(`${config.workspaceUrl}/oidc/v1/token`, {
        method: 'POST',
        redirect: 'error',
        signal: AbortSignal.timeout(10000),
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
          grant_type: 'urn:ietf:params:oauth:grant-type:token-exchange',
          subject_token_type: 'urn:ietf:params:oauth:token-type:jwt',
          subject_token: userToken,
          scope: 'all-apis',
        }),
      });
    } catch {
      throw new BrokerError(502, 'exchange_unavailable');
    }
    if (!response.ok) {
      throw new BrokerError([400, 401, 403].includes(response.status) ? 403 : 502, 'exchange_rejected');
    }
    try {
      const result = await response.json() as Record<string, unknown>;
      if (typeof result.access_token !== 'string' || !result.access_token
          || /[\r\n]/.test(result.access_token) || result.access_token.length > 32768
          || typeof result.token_type !== 'string' || result.token_type.toLowerCase() !== 'bearer'
          || typeof result.expires_in !== 'number' || !Number.isFinite(result.expires_in) || result.expires_in <= 0) {
        throw new Error('Invalid exchange response');
      }
      const expiresIn = Math.min(result.expires_in, userExpiry - Math.ceil(Date.now() / 1000));
      if (expiresIn <= 0) throw new Error('Expired exchange response');
      return { access_token: result.access_token, token_type: 'Bearer', expires_in: expiresIn };
    } catch {
      throw new BrokerError(502, 'invalid_exchange_response');
    }
  };
}