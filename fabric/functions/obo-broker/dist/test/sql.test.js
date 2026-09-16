import assert from 'node:assert/strict';
import { test } from 'node:test';
import { BrokerError } from '../src/errors.js';
import { assertReadOnlyStatement, tableListStatement } from '../src/sql.js';
test('accepts one read-only T-SQL select including a CTE', () => {
    assert.equal(assertReadOnlyStatement('SELECT TOP 10 * FROM scm.parts;', 1000), 'SELECT TOP 10 * FROM scm.parts');
    assert.match(assertReadOnlyStatement('WITH ranked AS (SELECT id FROM scm.parts) SELECT * FROM ranked', 1000), /^WITH/);
    assert.match(tableListStatement(), /^SELECT/);
});
test('rejects writes, multiple statements, open rowsets and oversized input', () => {
    const invalid = [
        'DELETE FROM scm.parts',
        'SELECT 1; SELECT 2',
        "SELECT * INTO copied FROM scm.parts",
        "SELECT * FROM OPENROWSET('provider', 'secret', 'query')",
        '',
    ];
    for (const statement of invalid) {
        assert.throws(() => assertReadOnlyStatement(statement, 1000), (error) => error instanceof BrokerError && error.status === 400);
    }
    assert.throws(() => assertReadOnlyStatement('SELECT 1', 3));
});
//# sourceMappingURL=sql.test.js.map