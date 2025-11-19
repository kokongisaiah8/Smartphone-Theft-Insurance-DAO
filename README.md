# ðŸ“± Smartphone Theft Insurance DAO

A comprehensive decentralized insurance platform for protecting smartphone users against theft, powered by Stacks blockchain with advanced Smart Notifications system.

## ðŸŽ¯ Core Features

### Insurance Coverage
- **Device Registration**: Register smartphones with IMEI validation
- **Premium Management**: Flexible payment system with grace periods
- **Claims Processing**: Community-driven claim verification
- **Policy Status Tracking**: Real-time policy status monitoring
- **Automated Payouts**: Instant claim payouts upon approval

### ðŸ”” Smart Notifications & Alerts (NEW)
- **Real-time Notifications**: Get instant updates on policy events
- **Customizable Preferences**: Configure email, push, and SMS preferences
- **Priority-Based Alerts**: Four priority levels (Low, Medium, High, Critical)
- **Subscription Management**: Subscribe to specific notification types
- **Payment Reminders**: Automated payment due date alerts
- **Claim Updates**: Real-time claim status notifications
- **Policy Alerts**: Expiration and renewal reminders
- **System Notifications**: Maintenance and system updates

## ðŸ’¡ How it Works

### Device Registration & Insurance
1. **Register Device**: Users register smartphones with 15-digit IMEI
2. **Premium Payment**: Monthly premium of 10 STX maintains coverage
3. **Policy Status**: Active policies with grace period support
4. **Notification Setup**: Configure alert preferences during registration

### Claims & Verification
1. **File Claim**: Submit theft claims with automatic validation
2. **Community Voting**: 5-vote threshold for claim approval
3. **Automated Payout**: 1000 STX payout for approved claims
4. **Status Alerts**: Real-time notifications throughout process

### Smart Notifications
1. **Setup Preferences**: Configure notification channels and frequency
2. **Subscribe to Alerts**: Choose notification types and priorities
3. **Receive Updates**: Get real-time alerts via blockchain
4. **Manage Notifications**: Mark as read, track delivery status

## ðŸ›  Usage Examples

### Basic Insurance Operations

#### Register Device
```clarity
(contract-call? .smartphone-theft-insurance-dao register-device "123456789012345")
```

#### Setup Notifications
```clarity
;; Configure notification preferences
(contract-call? .smartphone-theft-insurance-dao setup-notification-preferences 
    true    ;; email enabled
    true    ;; push enabled  
    false   ;; sms disabled
    u1      ;; immediate frequency
    "en"    ;; English language
)

;; Subscribe to payment reminders
(contract-call? .smartphone-theft-insurance-dao subscribe-to-notification 
    "payment-due" 
    u3  ;; high priority
)
```

#### Pay Premium
```clarity
(contract-call? .smartphone-theft-insurance-dao pay-premium)
```

#### File & Vote on Claims
```clarity
;; File a theft claim
(contract-call? .smartphone-theft-insurance-dao file-claim)

;; Vote on someone's claim
(contract-call? .smartphone-theft-insurance-dao vote-on-claim 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Notification Management

#### Check Notifications
```clarity
;; Get unread count
(contract-call? .smartphone-theft-insurance-dao get-unread-notification-count tx-sender)

;; Get notification details
(contract-call? .smartphone-theft-insurance-dao get-user-notification tx-sender u1)

;; Mark notification as read
(contract-call? .smartphone-theft-insurance-dao mark-notification-as-read u1)
```

#### Create Alerts (Admin Functions)
```clarity
;; Create payment reminder
(contract-call? .smartphone-theft-insurance-dao create-payment-due-alert user-address)

;; Create claim update alert
(contract-call? .smartphone-theft-insurance-dao create-claim-status-alert user-address "approved")
```

## ðŸ” Read-Only Functions

### Insurance Queries
- `get-device-info`: Check device registration status
- `get-claim-info`: View claim details and voting status  
- `get-insurance-pool`: Check total insurance pool balance
- `get-policy-status`: Check policy status and payment status
- `check-policy-status`: Comprehensive policy status check

### Notification Queries
- `get-user-notification-preferences`: View user notification settings
- `get-notification-subscription`: Check subscription status for notification type
- `get-user-notification`: Get specific notification details
- `get-user-notification-summary`: Get notification count summary
- `get-unread-notification-count`: Get count of unread notifications
- `check-notification-eligibility`: Check if user can receive specific notifications

## ðŸš¨ Notification Types

| Type | Description | Priority | Use Case |
|------|-------------|----------|----------|
| `payment-due` | Payment reminders | High | 5 days before due date |
| `claim-update` | Claim status changes | High | Approval/rejection updates |
| `policy-expiry` | Policy expiration | Critical | Policy renewal reminders |
| `risk-change` | Risk profile updates | Medium | Risk score changes |
| `system-alert` | System notifications | Medium | Maintenance announcements |

## âš™ï¸ Priority Levels

- **Low (1)**: General information, non-urgent
- **Medium (2)**: Important updates, moderate urgency
- **High (3)**: Critical events requiring attention
- **Critical (4)**: Emergency alerts, immediate action needed

## ðŸ”§ Development

### Requirements
- [Clarinet](https://github.com/hirosystems/clarinet) - Smart contract development
- [Node.js](https://nodejs.org/) - For testing and development tools
- [Stacks Wallet](https://wallet.hiro.so/) - For interacting with contracts
- STX tokens - For premium payments and transactions

### Setup
```bash
# Clone repository
git clone https://github.com/kokongisaiah8/Smartphone-Theft-Insurance-DAO.git

# Install dependencies
npm install

# Run contract validation
clarinet check

# Run tests
npm test
```

## ðŸ“Š Contract Statistics

- **Total Functions**: 25+ (15 public, 10+ read-only)
- **Notification Types**: 5 distinct categories
- **Priority Levels**: 4 levels (Low to Critical)
- **Error Codes**: 15+ comprehensive error handling
- **Data Maps**: 12 efficient storage structures
- **Security**: No external dependencies, independent feature design

## ðŸ›¡ï¸ Security Features

- **User-Controlled Preferences**: Users manage their own notification settings
- **Subscription-Based**: Only subscribed users receive notifications
- **Audit Trail**: Complete delivery and read tracking
- **Input Validation**: Comprehensive error checking
- **Gas Optimization**: Efficient storage and processing

## ðŸ“ˆ Gas Optimization

- Efficient map structures for minimal storage costs
- Batched operations where possible
- Optional metadata for flexible notification content
- Read-only functions for off-chain queries
- Minimal on-chain computation for notifications

## ðŸ¤ Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add comprehensive tests
5. Submit a pull request

## ðŸ“„ License

MIT License - see LICENSE file for details

## ðŸ”— Links

- [Stacks Blockchain](https://stacks.co/)
- [Clarity Language](https://clarity-lang.org/)
- [Clarinet Documentation](https://docs.hiro.so/clarinet/)
- [Smart Contract Source](./contracts/smartphone-theft-insurance-dao.clar)

