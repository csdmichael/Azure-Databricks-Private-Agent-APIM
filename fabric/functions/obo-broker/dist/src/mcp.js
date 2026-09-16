import { dataAgentMcpUrl } from './config.js';
import { BrokerError } from './errors.js';
function parseRpcResponse(response, body) {
    const contentType = response.headers.get('content-type') ?? '';
    try {
        if (contentType.includes('text/event-stream')) {
            const events = body.split(/\r?\n/).filter(line => line.startsWith('data:'))
                .map(line => JSON.parse(line.slice(5).trim()));
            if (!events.length)
                throw new Error('Missing SSE data');
            return events.at(-1);
        }
        return JSON.parse(body);
    }
    catch {
        throw new BrokerError(502, 'invalid_mcp_response');
    }
}
export function createDataAgentClient(config, request = fetch) {
    return async (token, question) => {
        const url = dataAgentMcpUrl(config);
        let sessionId = null;
        let requestId = 0;
        const call = async (method, params, notification = false) => {
            const body = { jsonrpc: '2.0', method };
            if (!notification)
                body.id = ++requestId;
            if (params)
                body.params = params;
            const headers = {
                Authorization: `Bearer ${token}`,
                Accept: 'application/json, text/event-stream',
                'Content-Type': 'application/json',
                'MCP-Protocol-Version': '2025-06-18',
            };
            if (sessionId)
                headers['Mcp-Session-Id'] = sessionId;
            let response;
            try {
                response = await request(url, {
                    method: 'POST', headers, body: JSON.stringify(body), redirect: 'error',
                    signal: AbortSignal.timeout(config.sqlRequestTimeoutMs),
                });
            }
            catch {
                throw new BrokerError(502, 'data_agent_unavailable');
            }
            sessionId = response.headers.get('mcp-session-id') ?? sessionId;
            const responseBody = await response.text();
            if (!response.ok)
                throw new BrokerError(response.status === 401 || response.status === 403 ? 403 : 502, 'data_agent_rejected');
            if (notification && !responseBody.trim())
                return {};
            const payload = parseRpcResponse(response, responseBody);
            if (payload.error || !payload.result)
                throw new BrokerError(502, 'data_agent_failed');
            return payload.result;
        };
        await call('initialize', {
            protocolVersion: '2025-06-18', capabilities: {},
            clientInfo: { name: 'fabric-obo-broker', version: '1.0.0' },
        });
        await call('notifications/initialized', undefined, true);
        const listed = await call('tools/list');
        const tools = Array.isArray(listed.tools) ? listed.tools : [];
        if (tools.length !== 1 || typeof tools[0].name !== 'string')
            throw new BrokerError(502, 'invalid_mcp_tools');
        const inputSchema = tools[0].inputSchema;
        const argumentName = Object.keys(inputSchema?.properties ?? {})[0];
        if (!argumentName)
            throw new BrokerError(502, 'invalid_mcp_tools');
        return call('tools/call', { name: tools[0].name, arguments: { [argumentName]: question } });
    };
}
//# sourceMappingURL=mcp.js.map