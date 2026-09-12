import assert from 'node:assert/strict';
import { test } from 'node:test';
import { generateKeyPair, SignJWT, type JWTPayload } from 'jose';
import { BrokerError, createBroker, loadConfig, type BrokerConfig } from '../src/broker.js';

const config: BrokerConfig = {
  tenantId: '11111111-1111-1111-1111-111111111111', audience: '22222222-2222-2222-2222-222222222222',
  brokerAudience: '22222222-2222-2222-2222-222222222222', apimPrincipalId: 'apim-object', clientIds: ['connector-client'],
  scope: 'Genie.Access', workspaceUrl: 'https://adb-123.10.azuredatabricks.net',
};
const keys = await generateKeyPair('RS256');
const issuer = `https://login.microsoftonline.com/${config.tenantId}/v2.0`;
const sign = (claims: JWTPayload, audience = config.audience, expiry: string | number = '5m') =>
  new SignJWT({ tid: config.tenantId, ...claims }).setProtectedHeader({ alg: 'RS256' })
    .setIssuer(issuer).setAudience(audience).setIssuedAt().setNotBefore('0s').setExpirationTime(expiry).sign(keys.privateKey);
const userClaims = { oid: 'user-object', azp: 'connector-client', scp: 'Genie.Access', preferred_username: 'user@example.com' };
const caller = await sign({ oid: config.apimPrincipalId }, config.brokerAudience);
const user = await sign(userClaims);
const rejected = (status: number) => (error: unknown) => error instanceof BrokerError && error.status === status;

test('exchanges the verified user, with no service principal client_id or redirects', async () => {
  const subjects: string[] = [];
  const broker = createBroker(config, async () => keys.publicKey, async (url, options) => {
    assert.equal(url, `${config.workspaceUrl}/oidc/v1/token`);
    assert.equal(options?.redirect, 'error');
    const body = options?.body as URLSearchParams;
    subjects.push(body.get('subject_token')!);
    assert.equal(body.get('client_id'), null);
    assert.equal(body.get('grant_type'), 'urn:ietf:params:oauth:grant-type:token-exchange');
    return Response.json({ access_token: `databricks-user-token-${subjects.length}`, token_type: 'Bearer', expires_in: 3600 });
  });
  const result = await broker(caller, user);
  assert.equal(result.access_token, 'databricks-user-token-1');
  assert.ok(result.expires_in <= 300);
  const otherUser = await sign({ ...userClaims, oid: 'other-user', preferred_username: 'other@example.com' });
  const otherResult = await broker(caller, otherUser);
  assert.equal(otherResult.access_token, 'databricks-user-token-2');
  assert.deepEqual(subjects, [user, otherUser]);
});

test('rejects wrong audience, scope, client, tenant, service identity, expiry and signature before exchange', async () => {
  const broker = createBroker(config, async () => keys.publicKey, async () => { throw new Error('Must not exchange'); });
  const invalid = [
    'not-a-jwt', await sign(userClaims, 'graph'), await sign({ ...userClaims, scp: 'Other.Scope' }),
    await sign({ ...userClaims, azp: 'unapproved' }), await sign({ ...userClaims, tid: 'other-tenant' }),
    await sign({ ...userClaims, idtyp: 'app' }), await sign({ oid: 'service', roles: ['Genie.Access'] }),
    await sign({ ...userClaims, preferred_username: '' }), await sign(userClaims, config.audience, ' -1s'.trim()),
  ];
  const otherKeys = await generateKeyPair('RS256');
  invalid.push(await new SignJWT(userClaims).setProtectedHeader({ alg: 'RS256' }).sign(otherKeys.privateKey));
  for (const token of invalid) await assert.rejects(broker(caller, token), rejected(401));
});

test('rejects callers other than APIM, including user callers', async () => {
  const broker = createBroker(config, async () => keys.publicKey);
  for (const token of ['', user, await sign({ oid: 'other-apim' }, config.brokerAudience),
    await sign({ oid: config.apimPrincipalId }, `api://${config.brokerAudience}`),
    await sign({ oid: config.apimPrincipalId, scp: 'Genie.Access' }, config.brokerAudience)]) {
    await assert.rejects(broker(token, user), rejected(401));
  }
});

test('fails closed and hides upstream errors', async () => {
  for (const status of [400, 401, 403, 429, 500]) {
    const broker = createBroker(config, async () => keys.publicKey, async () => new Response('secret upstream detail', { status }));
    await assert.rejects(broker(caller, user), rejected(status < 429 ? 403 : 502));
  }
  for (const body of [{}, { access_token: 'token', token_type: 'Bearer', expires_in: -1 }]) {
    const broker = createBroker(config, async () => keys.publicKey, async () => Response.json(body));
    await assert.rejects(broker(caller, user), rejected(502));
  }
});

test('configuration cannot redirect the exchange to an arbitrary host', () => {
  const env = { ENTRA_TENANT_ID: config.tenantId, ENTRA_API_CLIENT_ID: config.audience,
    BROKER_AUDIENCE: config.brokerAudience, APIM_PRINCIPAL_ID: config.apimPrincipalId,
    ALLOWED_CLIENT_IDS: 'connector-client' };
  for (const url of ['http://adb-123.10.azuredatabricks.net', 'https://evil.example', `${config.workspaceUrl}/other`, `${config.workspaceUrl}?redirect=evil`]) {
    assert.throws(() => loadConfig({ ...env, DATABRICKS_WORKSPACE_URL: url }));
  }
  assert.equal(loadConfig({ ...env, DATABRICKS_WORKSPACE_URL: config.workspaceUrl }).workspaceUrl, config.workspaceUrl);
});