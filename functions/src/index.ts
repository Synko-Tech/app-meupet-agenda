import { initializeApp } from 'firebase-admin/app';
import { setGlobalOptions } from 'firebase-functions/v2';

initializeApp();

// Firestore for this project lives in southamerica-east1 (see README).
setGlobalOptions({ region: 'southamerica-east1', maxInstances: 10 });

// Feature callables are re-exported here as they land:
// - Task 10: createAppointment
// - Task 11: cancelAppointment
// - Task 12: packages
// - Task 13: payments
// - Task 14: admin panel
// Each module exports `onCall` handlers. Shared helpers live in src/shared
// and src/auth.

export { createAppointment } from './appointments/create-appointment';
export { cancelAppointment } from './appointments/cancel-appointment';
export { purchasePackage } from './packages/purchase-package';
export { activatePackage } from './packages/activate-package';
export { createMercadoPagoCheckout } from './payments/create-mp-checkout';
export { mercadoPagoWebhook } from './payments/mp-webhook';
export { createBusiness } from './businesses/create-business';
export { registerBusiness } from './businesses/register-business';
export { joinBusiness } from './businesses/join-business';
export { completeOwnProfile } from './profile/complete-own-profile';
export { updateOwnAddress } from './profile/update-own-address';
export { startMpConnection } from './payments/oauth/start-mp-connection';
export { mpOauthCallback } from './payments/oauth/mp-oauth-callback';
export { refreshMpConnection } from './payments/oauth/refresh-mp-connection';
export { disconnectMpConnection } from './payments/oauth/disconnect-mp-connection';
