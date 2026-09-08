import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

const { fieldOverrides } = JSON.parse(
  readFileSync(new URL('../firestore.indexes.json', import.meta.url), 'utf8'),
);

const privateFields = [
  'cpf',
  'cpfLast2',
  'address.postalCode',
  'address.street',
  'address.number',
  'address.complement',
  'address.neighborhood',
  'address.city',
  'address.state',
  'address.country',
];

test('fieldOverrides uses the official Firebase format', () => {
  for (const override of fieldOverrides) {
    assert.equal(typeof override.collectionGroup, 'string');
    assert.equal(typeof override.fieldPath, 'string');
    assert.ok(Array.isArray(override.indexes));
    assert.equal('fieldPaths' in override, false, 'fieldPaths is not a key');
    assert.equal('disableIndexing' in override, false);
  }
});

test('every private field of userPrivate has indexing disabled', () => {
  const overridden = new Set(
    fieldOverrides
      .filter((override) => override.collectionGroup === 'userPrivate')
      .map((override) => override.fieldPath),
  );
  for (const field of privateFields) {
    assert.ok(overridden.has(field), `${field} missing from fieldOverrides`);
  }
});
