import sql from 'mssql';
import sqlParser from 'node-sql-parser';
import { BrokerError } from './errors.js';
const parser = new sqlParser.Parser();
const forbiddenSelectPattern = /\b(OPENROWSET|OPENQUERY|OPENDATASOURCE|BULK|INTO|EXEC(?:UTE)?|WAITFOR)\b/i;
export function assertReadOnlyStatement(statement, maxLength) {
    const normalized = statement.trim().replace(/;+\s*$/, '');
    if (!normalized || normalized.length > maxLength || /[\0\r]/.test(normalized)
        || forbiddenSelectPattern.test(normalized)) {
        throw new BrokerError(400, 'invalid_statement');
    }
    try {
        const ast = parser.astify(normalized, { database: 'TransactSQL' });
        const statements = Array.isArray(ast) ? ast : [ast];
        if (statements.length !== 1 || statements[0]?.type !== 'select')
            throw new Error('Not a single SELECT');
    }
    catch {
        throw new BrokerError(400, 'invalid_statement');
    }
    return normalized;
}
function typeName(column) {
    const type = column.type;
    return type?.declaration ?? type?.name ?? 'unknown';
}
export async function executeQuery(config, token, statement) {
    const pool = new sql.ConnectionPool({
        server: config.sqlEndpointHost,
        database: config.lakehouseName,
        port: 1433,
        connectionTimeout: config.sqlConnectTimeoutMs,
        requestTimeout: config.sqlRequestTimeoutMs,
        options: { encrypt: true, trustServerCertificate: false, enableArithAbort: true },
        authentication: { type: 'azure-active-directory-access-token', options: { token } },
        pool: { min: 0, max: 2, idleTimeoutMillis: 10000 },
    });
    try {
        await pool.connect();
        const request = pool.request();
        const result = await request.query(`SET ROWCOUNT ${config.maxRows + 1};\n${statement}`);
        const recordset = result.recordset ?? [];
        const rows = recordset.slice(0, config.maxRows);
        const columns = recordset.columns
            ? Object.entries(recordset.columns).map(([name, metadata]) => ({ name, type: typeName(metadata) }))
            : [];
        return { columns, rows, rowCount: rows.length, truncated: recordset.length > config.maxRows };
    }
    catch (error) {
        if (error instanceof BrokerError)
            throw error;
        throw new BrokerError(502, 'query_failed');
    }
    finally {
        await pool.close().catch(() => undefined);
    }
}
export function tableListStatement() {
    return "SELECT TABLE_SCHEMA AS [schema], TABLE_NAME AS [name], TABLE_TYPE AS [type] FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA NOT IN ('sys', 'INFORMATION_SCHEMA') ORDER BY TABLE_SCHEMA, TABLE_NAME";
}
//# sourceMappingURL=sql.js.map