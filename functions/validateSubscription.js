/**
 * validateSubscription Cloud Function
 *
 * Receives transaction data from the iOS client after a successful
 * StoreKit 2 purchase and writes it to Firestore for record-keeping.
 *
 * This is a non-blocking sync — the app flow does not depend on this
 * succeeding. StoreKit 2's on-device JWS verification is the primary
 * source of truth.
 */

const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

exports.validateSubscription = onRequest(
  {
    timeoutSeconds: 15,
    memory: '256MiB',
    cors: true
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const {
      userId,
      productId,
      originalTransactionId,
      transactionId,
      purchaseDate,
      expirationDate,
      environment,
      isUpgraded
    } = req.body;

    if (!userId || !originalTransactionId) {
      res.status(400).json({ error: 'Missing required fields' });
      return;
    }

    try {
      const db = admin.firestore();

      // Write subscription data to the user document
      await db.collection('users').doc(userId).set({
        subscription: {
          productId,
          originalTransactionId,
          transactionId,
          purchaseDate,
          expirationDate,
          environment,
          isUpgraded: isUpgraded || false,
          isActive: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }
      }, { merge: true });

      // Also write to a subscriptions collection for easier querying
      await db.collection('subscriptions').doc(originalTransactionId).set({
        userId,
        productId,
        originalTransactionId,
        transactionId,
        purchaseDate,
        expirationDate,
        environment,
        isUpgraded: isUpgraded || false,
        status: 'active',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      console.log(`Subscription synced for user ${userId}: ${productId}`);

      res.status(200).json({
        success: true,
        subscription: { productId, expirationDate, isActive: true }
      });

    } catch (error) {
      console.error('Subscription sync error:', error);
      res.status(500).json({
        error: 'Sync failed',
        message: error.message
      });
    }
  }
);
