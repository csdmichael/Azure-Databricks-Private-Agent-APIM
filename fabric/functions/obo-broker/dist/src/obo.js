import { ConfidentialClientApplication } from '@azure/msal-node';
import { downstreamScope } from './config.js';
import { BrokerError } from './errors.js';
export function createOboClient(config) {
    return new ConfidentialClientApplication({
        auth: {
            clientId: config.apiClientId,
            clientSecret: config.apiClientSecret,
            authority: `https://login.microsoftonline.com/${config.resourceTenantId}`,
        },
        system: { networkClient: undefined },
    });
}
export function createTokenExchanger(config, client = createOboClient(config)) {
    return async (userAssertion, target, userExpiresAt) => {
        let result;
        try {
            result = await Promise.race([
                client.acquireTokenOnBehalfOf({
                    oboAssertion: userAssertion,
                    scopes: [downstreamScope(config, target)],
                    skipCache: true,
                }),
                new Promise((_, reject) => setTimeout(() => reject(new Error('OBO timeout')), config.tokenExchangeTimeoutMs)),
            ]);
        }
        catch {
            throw new BrokerError(403, 'exchange_rejected');
        }
        if (!result?.accessToken || /[\r\n]/.test(result.accessToken) || result.accessToken.length > 32768) {
            throw new BrokerError(502, 'invalid_exchange_response');
        }
        const downstreamExpiry = result.expiresOn ? Math.floor(result.expiresOn.getTime() / 1000) : userExpiresAt;
        const expiresIn = Math.min(downstreamExpiry, userExpiresAt) - Math.ceil(Date.now() / 1000);
        if (expiresIn <= 0)
            throw new BrokerError(502, 'invalid_exchange_response');
        return { accessToken: result.accessToken, expiresIn };
    };
}
//# sourceMappingURL=obo.js.map