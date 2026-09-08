import { createHmac } from 'node:crypto';

/**
 * Id da claim de unicidade do CPF (`cpfClaims/{id}`): HMAC-SHA256 em hex
 * do CPF canonico usando o secret `CPF_HMAC_SECRET`. O CPF nunca e
 * armazenado em claro.
 */
export function cpfClaimId(cpf: string, secret: string): string {
  return createHmac('sha256', secret).update(cpf).digest('hex');
}
