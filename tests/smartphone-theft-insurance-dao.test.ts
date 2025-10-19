import { Clarinet, Tx, Chain, Account, types } from '@hirosystems/clarinet-sdk';
import { expect } from 'vitest';

const CONTRACT_NAME = 'smartphone-theft-insurance-dao';

Clarinet.test({
  name: 'Can register device with valid IMEI',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    const validImei = '123456789012345';
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'register-device',
        [types.ascii(validImei)],
        user1.address
      )
    ]);
    
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify device registration
    let deviceInfo = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-device-info',
      [types.principal(user1.address)],
      deployer.address
    );
    
    const device = deviceInfo.result.expectOk().expectSome();
    expect(device).toHaveProperty('imei', validImei);
  }
});

Clarinet.test({
  name: 'Cannot register device with invalid IMEI length',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user1 = accounts.get('wallet_1')!;
    
    const shortImei = '123456789012'; // Only 12 digits instead of 15
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'register-device',
        [types.ascii(shortImei)],
        user1.address
      )
    ]);
    
    block.receipts[0].result.expectErr().expectUint(102); // ERR-INVALID-IMEI
  }
});

Clarinet.test({
  name: 'Can setup notification preferences',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'setup-notification-preferences',
        [
          types.bool(true),  // email
          types.bool(false), // push
          types.bool(true),  // sms
          types.uint(1),     // frequency (immediate)
          types.ascii('en')  // language
        ],
        user1.address
      )
    ]);
    
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify preferences
    let preferences = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-user-notification-preferences',
      [types.principal(user1.address)],
      user1.address
    );
    
    const prefs = preferences.result.expectOk().expectSome();
    expect(prefs).toHaveProperty('email-enabled', true);
    expect(prefs).toHaveProperty('sms-enabled', true);
    expect(prefs).toHaveProperty('language', 'en');
  }
});

Clarinet.test({
  name: 'Can subscribe to notifications',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [
          types.ascii('payment-due'),
          types.uint(3) // HIGH priority
        ],
        user1.address
      )
    ]);
    
    block.receipts[0].result.expectOk().expectBool(true);
    
    // Verify subscription
    let subscription = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-notification-subscription',
      [types.principal(user1.address), types.ascii('payment-due')],
      user1.address
    );
    
    const sub = subscription.result.expectOk().expectSome();
    expect(sub).toHaveProperty('subscribed', true);
    expect(sub).toHaveProperty('priority', 3);
  }
});

Clarinet.test({
  name: 'Can create and receive notifications',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    // First subscribe to notifications
    let subscribeBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [
          types.ascii('system-alert'),
          types.uint(2) // MEDIUM priority
        ],
        user1.address
      )
    ]);
    
    subscribeBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Create a notification
    let notificationBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'create-notification',
        [
          types.principal(user1.address),
          types.ascii('Test system notification message'),
          types.ascii('system-alert'),
          types.uint(2),
          types.some(types.ascii('test-metadata'))
        ],
        deployer.address
      )
    ]);
    
    notificationBlock.receipts[0].result.expectOk().expectUint(1);
    
    // Check notification summary
    let summary = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-user-notification-summary',
      [types.principal(user1.address)],
      user1.address
    );
    
    const summaryData = summary.result.expectOk().expectSome();
    expect(summaryData).toHaveProperty('total-notifications', 1);
    expect(summaryData).toHaveProperty('unread-notifications', 1);
  }
});

Clarinet.test({
  name: 'Can mark notification as read',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    // Setup subscription and create notification
    let setupBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [types.ascii('claim-update'), types.uint(3)],
        user1.address
      ),
      Tx.contractCall(
        CONTRACT_NAME,
        'create-notification',
        [
          types.principal(user1.address),
          types.ascii('Your claim has been updated'),
          types.ascii('claim-update'),
          types.uint(3),
          types.none()
        ],
        deployer.address
      )
    ]);
    
    setupBlock.receipts[0].result.expectOk().expectBool(true);
    setupBlock.receipts[1].result.expectOk().expectUint(1);
    
    // Mark notification as read
    let readBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'mark-notification-as-read',
        [types.uint(1)],
        user1.address
      )
    ]);
    
    readBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Check updated summary
    let summary = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-user-notification-summary',
      [types.principal(user1.address)],
      user1.address
    );
    
    const summaryData = summary.result.expectOk().expectSome();
    expect(summaryData).toHaveProperty('unread-notifications', 0);
  }
});

Clarinet.test({
  name: 'Complete insurance workflow with notifications',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    const user2 = accounts.get('wallet_2')!;
    const voter1 = accounts.get('wallet_3')!;
    const voter2 = accounts.get('wallet_4')!;
    
    const validImei = '987654321098765';
    
    // Setup notification preferences and subscriptions
    let setupBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'setup-notification-preferences',
        [types.bool(true), types.bool(true), types.bool(false), types.uint(1), types.ascii('en')],
        user1.address
      ),
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [types.ascii('claim-update'), types.uint(3)],
        user1.address
      )
    ]);
    
    setupBlock.receipts[0].result.expectOk().expectBool(true);
    setupBlock.receipts[1].result.expectOk().expectBool(true);
    
    // Register device
    let registerBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'register-device',
        [types.ascii(validImei)],
        user1.address
      )
    ]);
    
    registerBlock.receipts[0].result.expectOk().expectBool(true);
    
    // File a claim
    let claimBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'file-claim',
        [],
        user1.address
      )
    ]);
    
    claimBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Create claim update notification
    let notifyBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'create-claim-status-alert',
        [types.principal(user1.address), types.ascii('approved')],
        deployer.address
      )
    ]);
    
    notifyBlock.receipts[0].result.expectOk().expectUint(1);
    
    // Verify notification was created
    let notification = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-user-notification',
      [types.principal(user1.address), types.uint(1)],
      user1.address
    );
    
    const notificationData = notification.result.expectOk().expectSome();
    expect(notificationData).toHaveProperty('notification-type', 'claim-update');
    expect(notificationData).toHaveProperty('priority', 3);
  }
});

Clarinet.test({
  name: 'Can check policy status and create payment alerts',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    // Register device first
    let registerBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'register-device',
        [types.ascii('111222333444555')],
        user1.address
      )
    ]);
    
    registerBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Check initial policy status
    let statusCheck = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-policy-status',
      [types.principal(user1.address)],
      deployer.address
    );
    
    const status = statusCheck.result.expectOk();
    expect(status).toHaveProperty('status', 'active');
    expect(status).toHaveProperty('blocks-overdue', 0);
    
    // Subscribe to payment notifications
    let subscribeBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [types.ascii('payment-due'), types.uint(3)],
        user1.address
      )
    ]);
    
    subscribeBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Create payment due alert
    let alertBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'create-payment-due-alert',
        [types.principal(user1.address)],
        deployer.address
      )
    ]);
    
    // Should return 0 since payment is not due yet
    alertBlock.receipts[0].result.expectOk().expectUint(0);
  }
});

Clarinet.test({
  name: 'Cannot subscribe to invalid notification types',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const user1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [
          types.ascii('invalid-type'),
          types.uint(2)
        ],
        user1.address
      )
    ]);
    
    block.receipts[0].result.expectErr().expectUint(110); // ERR-INVALID-NOTIFICATION-TYPE
  }
});

Clarinet.test({
  name: 'Cannot create notification with invalid priority',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    let block = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'create-notification',
        [
          types.principal(user1.address),
          types.ascii('Test message'),
          types.ascii('system-alert'),
          types.uint(5), // Invalid priority (should be 1-4)
          types.none()
        ],
        deployer.address
      )
    ]);
    
    block.receipts[0].result.expectErr().expectUint(114); // ERR-INVALID-PRIORITY
  }
});

Clarinet.test({
  name: 'Can check unread notification count',
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const user1 = accounts.get('wallet_1')!;
    
    // Initially should have 0 unread notifications
    let initialCount = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-unread-notification-count',
      [types.principal(user1.address)],
      user1.address
    );
    
    initialCount.result.expectOk().expectUint(0);
    
    // Subscribe and create multiple notifications
    let setupBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'subscribe-to-notification',
        [types.ascii('system-alert'), types.uint(1)],
        user1.address
      ),
      Tx.contractCall(
        CONTRACT_NAME,
        'create-notification',
        [
          types.principal(user1.address),
          types.ascii('First notification'),
          types.ascii('system-alert'),
          types.uint(1),
          types.none()
        ],
        deployer.address
      ),
      Tx.contractCall(
        CONTRACT_NAME,
        'create-notification',
        [
          types.principal(user1.address),
          types.ascii('Second notification'),
          types.ascii('system-alert'),
          types.uint(2),
          types.none()
        ],
        deployer.address
      )
    ]);
    
    setupBlock.receipts[0].result.expectOk().expectBool(true);
    setupBlock.receipts[1].result.expectOk().expectUint(1);
    setupBlock.receipts[2].result.expectOk().expectUint(2);
    
    // Check unread count
    let unreadCount = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-unread-notification-count',
      [types.principal(user1.address)],
      user1.address
    );
    
    unreadCount.result.expectOk().expectUint(2);
    
    // Mark one as read
    let readBlock = chain.mineBlock([
      Tx.contractCall(
        CONTRACT_NAME,
        'mark-notification-as-read',
        [types.uint(1)],
        user1.address
      )
    ]);
    
    readBlock.receipts[0].result.expectOk().expectBool(true);
    
    // Check updated unread count
    let updatedCount = chain.callReadOnlyFn(
      CONTRACT_NAME,
      'get-unread-notification-count',
      [types.principal(user1.address)],
      user1.address
    );
    
    updatedCount.result.expectOk().expectUint(1);
  }
});
