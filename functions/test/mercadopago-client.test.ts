/**
 * Unit tests for the real Mercado Pago wrapper (createMpClient).
 *
 * The SDK talks HTTP via the native global fetch, so we stub fetch and
 * assert the exact outgoing request (URL, JSON body, idempotency header)
 * plus the camelCase mapping of the responses. No Mercado Pago API (and
 * no Firebase emulator) is touched.
 *
 * Compiled via tsconfig.test.json into lib-test/ (see functions/README).
 */

import 'mocha';
import assert from 'node:assert/strict';

import { createMpClient } from '../src/payments/mercadopago-client';
import type { MpPreferenceInput } from '../src/payments/mercadopago-client';

type FetchCall = { url: string; init: RequestInit };

function installFetchStub(
  respond: (call: FetchCall) => { status: number; body: Record<string, unknown> },
): { calls: FetchCall[]; restore: () => void } {
  const calls: FetchCall[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL, init?: RequestInit) => {
    const record: FetchCall = { url: String(url), init: init ?? {} };
    calls.push(record);
    const fixture = respond(record);
    return {
      ok: fixture.status >= 200 && fixture.status < 300,
      status: fixture.status,
      headers: { get: () => null, forEach: () => undefined },
      json: async () => fixture.body,
    } as unknown as Response;
  }) as typeof fetch;
  return {
    calls,
    restore: () => {
      globalThis.fetch = original;
    },
  };
}

const basePreferenceInput: MpPreferenceInput = {
  title: 'Pacote Banho 5x',
  unitPrice: 149.9,
  payerName: 'Alice Teste',
  externalReference: 'pay-abc-123',
  notificationUrl: 'https://example.com/mercadoPagoWebhook',
};

describe('createMpClient (SDK wrapper)', () => {
  it('createPreference monta o body esperado e mapeia a resposta', async () => {
    const stub = installFetchStub(() => ({
      status: 201,
      body: { id: 'pref-99', init_point: 'https://mercadopago.com/checkout/pref-99' },
    }));
    try {
      const result = await createMpClient('TEST-TOKEN').createPreference(basePreferenceInput);

      assert.equal(result.id, 'pref-99');
      assert.equal(result.initPoint, 'https://mercadopago.com/checkout/pref-99');

      assert.equal(stub.calls.length, 1);
      const call = stub.calls[0];
      assert.ok(/\/checkout\/preferences\/?$/.test(call.url));

      const body = JSON.parse(String(call.init.body)) as Record<string, unknown>;
      const items = body.items as Array<Record<string, unknown>>;
      assert.equal(items.length, 1);
      assert.equal(items[0].id, 'pay-abc-123');
      assert.equal(items[0].title, 'Pacote Banho 5x');
      assert.equal(items[0].quantity, 1);
      assert.equal(items[0].unit_price, 149.9);
      assert.deepEqual(body.payer, { name: 'Alice Teste' });
      assert.equal(body.external_reference, 'pay-abc-123');
      assert.equal(body.notification_url, 'https://example.com/mercadoPagoWebhook');
      assert.equal(body.auto_return, 'approved');
    } finally {
      stub.restore();
    }
  });

  it('createPreference envia X-Idempotency-Key quando idempotencyKey é passado', async () => {
    const stub = installFetchStub(() => ({
      status: 201,
      body: { id: 'pref-1', init_point: 'https://mercadopago.com/checkout/pref-1' },
    }));
    try {
      await createMpClient('TEST-TOKEN').createPreference({
        ...basePreferenceInput,
        idempotencyKey: 'key-42',
      });

      const headers = stub.calls[0].init.headers as Record<string, string>;
      assert.equal(headers['X-Idempotency-Key'], 'key-42');
    } finally {
      stub.restore();
    }
  });

  it('getPayment consulta o endpoint certo e mapeia para MpPaymentInfo', async () => {
    const stub = installFetchStub(() => ({
      status: 200,
      body: {
        id: 123456,
        status: 'approved',
        payment_method_id: 'visa',
        external_reference: 'pay-abc-123',
      },
    }));
    try {
      const info = await createMpClient('TEST-TOKEN').getPayment('123456');

      assert.ok(stub.calls[0].url.endsWith('/v1/payments/123456'));
      assert.equal(info?.id, '123456');
      assert.equal(info?.status, 'approved');
      assert.equal(info?.paymentMethodId, 'visa');
      assert.equal(info?.externalReference, 'pay-abc-123');
    } finally {
      stub.restore();
    }
  });

  it('getPayment retorna nulo quando a resposta não traz o corpo esperado', async () => {
    const stub = installFetchStub(() => ({ status: 200, body: {} }));
    try {
      const info = await createMpClient('TEST-TOKEN').getPayment('999');
      assert.equal(info, null);
    } finally {
      stub.restore();
    }
  });

  it('erro de rede do Mercado Pago propaga para o chamador', async () => {
    const stub = installFetchStub(() => ({ status: 500, body: {} }));
    try {
      await assert.rejects(
        createMpClient('TEST-TOKEN').createPreference(basePreferenceInput),
        (err: unknown) => err instanceof Error,
      );
    } finally {
      stub.restore();
    }
  });
});