export class BrokerError extends Error {
    status;
    code;
    constructor(status, code) {
        super(code);
        this.status = status;
        this.code = code;
    }
}
export function safeError(error) {
    return error instanceof BrokerError ? error : new BrokerError(503, 'broker_unavailable');
}
//# sourceMappingURL=errors.js.map