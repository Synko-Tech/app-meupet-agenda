import { MercadoPagoConfig, Payment, Preference } from 'mercadopago';

/**
 * Thin Mercado Pago wrapper (SDK v3.3). The consumer surface is described
 * by MpClient so FakeMpClient implementations can be injected in tests;
 * production wiring happens in createMpClient.
 *
 * Mercado Pago SDK v3 sends snake_case request bodies and returns
 * snake_case responses; this wrapper converts to camelCase at the boundary.
 */

export interface MpPreferenceInput {
  title: string;
  unitPrice: number;
  payerName: string;
  externalReference: string;
  notificationUrl: string;
  /**
   * Optional idempotency key for the preference request itself (sent to
   * Mercado Pago as X-Idempotency-Key). Our own replay protection lives in
   * mpCheckoutIdempotency; this is defense in depth at the gateway.
   */
  idempotencyKey?: string;
}

export interface MpPreferenceResult {
  id: string;
  initPoint: string;
}

export interface MpPaymentInfo {
  id: string;
  status: string;
  paymentMethodId: string | undefined;
  externalReference: string | undefined;
}

export interface MpClient {
  createPreference(input: MpPreferenceInput): Promise<MpPreferenceResult>;
  getPayment(paymentId: string): Promise<MpPaymentInfo | null>;
}

export const MP_ACCESS_TOKEN_ENV = 'MERCADOPAGO_ACCESS_TOKEN';
export const MP_WEBHOOK_URL_ENV = 'MERCADOPAGO_WEBHOOK_URL';
export const MP_WEBHOOK_SECRET_ENV = 'MERCADOPAGO_WEBHOOK_SECRET';

/** MERCADOPAGO_ACCESS_TOKEN (set via functions/.env). */
export function getMpAccessToken(): string {
  return process.env[MP_ACCESS_TOKEN_ENV] ?? '';
}

/**
 * MERCADOPAGO_WEBHOOK_SECRET: secret configured in the Mercado Pago
 * notifications panel; used to verify the x-signature of v2 webhooks.
 * When unset, signature verification is skipped (local development).
 */
export function getMpWebhookSecret(): string {
  return process.env[MP_WEBHOOK_SECRET_ENV] ?? '';
}

/**
 * MERCADOPAGO_WEBHOOK_URL: public HTTPS URL of the webhook function
 * (e.g. https://southamerica-east1-<project>.cloudfunctions.net/mercadoPagoWebhook).
 * In emulators: http://127.0.0.1:5001/<project>/southamerica-east1/mercadoPagoWebhook.
 */
export function getMpWebhookUrl(): string {
  return process.env[MP_WEBHOOK_URL_ENV] ?? '';
}

export function createMpClient(accessToken: string): MpClient {
  const config = new MercadoPagoConfig({ accessToken });
  const preference = new Preference(config);
  const payment = new Payment(config);

  return {
    async createPreference(input: MpPreferenceInput): Promise<MpPreferenceResult> {
      const requestOptions =
        input.idempotencyKey === undefined
          ? undefined
          : { idempotencyKey: input.idempotencyKey };
      const response = await preference.create({
        body: {
          items: [
            {
              id: input.externalReference,
              title: input.title,
              quantity: 1,
              unit_price: input.unitPrice,
            },
          ],
          payer: { name: input.payerName },
          external_reference: input.externalReference,
          notification_url: input.notificationUrl,
          auto_return: 'approved',
        },
        ...(requestOptions === undefined ? {} : { requestOptions }),
      });
      return {
        id: String(response.id ?? ''),
        initPoint: response.init_point ?? '',
      };
    },

    async getPayment(paymentId: string): Promise<MpPaymentInfo | null> {
      const response = await payment.get({ id: paymentId });
      if (
        response === undefined ||
        response === null ||
        response.id === undefined ||
        response.id === null ||
        String(response.id) === ''
      ) {
        return null;
      }
      return {
        id: String(response.id ?? ''),
        status: response.status ?? '',
        paymentMethodId: response.payment_method_id,
        externalReference: response.external_reference,
      };
    },
  };
}