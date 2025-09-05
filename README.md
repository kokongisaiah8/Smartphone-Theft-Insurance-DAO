# 📱 Smartphone Theft Insurance DAO

A decentralized insurance platform for protecting smartphone users against theft, powered by Stacks blockchain.

## 🎯 Features

- Register your device with IMEI number
- Pay monthly premiums in STX
- File theft claims
- Community-driven claim verification
- Automatic payouts upon claim approval

## 💡 How it Works

1. **Device Registration**
   - Users register their smartphones using IMEI numbers
   - Pay initial premium (10 STX)

2. **Premium Payments**
   - Monthly premium: 10 STX
   - Maintains insurance coverage

3. **Claims Process**
   - File claim when theft occurs
   - Community members vote on claims
   - 5 votes needed for approval
   - Successful claims receive 1000 STX payout

## 🛠 Usage

### Register Device
```clarity
(contract-call? .smartphone-theft-insurance-dao register-device "123456789012345")
```

### Pay Monthly Premium
```clarity
(contract-call? .smartphone-theft-insurance-dao pay-premium)
```

### File Claim
```clarity
(contract-call? .smartphone-theft-insurance-dao file-claim)
```

### Vote on Claim
```clarity
(contract-call? .smartphone-theft-insurance-dao vote-on-claim 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## 🔍 View Functions

- `get-device-info`: Check registration status
- `get-claim-info`: View claim details
- `get-insurance-pool`: Check total insurance pool balance

## ⚠️ Requirements

- Clarinet
- Stacks Wallet
- STX tokens for premium payments
```
