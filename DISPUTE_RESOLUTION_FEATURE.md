# Automated Claim Dispute Resolution System

## Feature Overview

This feature introduces a decentralized arbitration mechanism that allows policyholders to challenge rejected theft claims through an evidence-based dispute process with time-bound resolution by staked arbitrators.

## Value Proposition

- **Fairness**: Provides policyholders recourse when claims are unfairly rejected
- **Transparency**: On-chain evidence tracking and arbitration decisions
- **Incentive Alignment**: Arbitrators stake tokens and earn rewards for fair resolutions
- **Time Efficiency**: Automated 2880-block dispute window ensures timely resolutions
- **Cost Effective**: Arbitration fees fund the dispute process sustainably

## New Error Constants

- `ERR-NO-DISPUTE (u121)`: No dispute found for the specified user
- `ERR-DISPUTE-EXISTS (u122)`: Dispute already filed or arbitrator already assigned
- `ERR-DISPUTE-EXPIRED (u123)`: Dispute window has closed
- `ERR-NOT-ARBITRATOR (u124)`: Caller is not registered as arbitrator
- `ERR-INVALID-EVIDENCE (u125)`: Evidence hash is invalid

## Configuration Variables

- `dispute-window-blocks`: Time limit for dispute resolution (2880 blocks ≈ 20 days)
- `arbitration-fee`: Fee paid by disputing user (2 STX)
- `arbitrator-reward`: Reward for arbitrators who resolve disputes (1 STX)

## Data Structures

### claim-disputes
Stores dispute information for each policyholder
- `dispute-reason`: Written explanation (up to 200 characters)
- `evidence-hash`: IPFS/SHA256 hash of supporting evidence
- `filed-at`: Block height when dispute was filed
- `arbitrator`: Assigned arbitrator's principal
- `resolution`: Final decision (approve/reject)
- `resolved-at`: Block height of resolution

### arbitrators
Tracks registered arbitrators and their performance
- `stake`: Amount staked (uses validator-stake-required)
- `cases-resolved`: Total disputes resolved
- `accuracy-score`: Performance metric (0-100)
- `is-active`: Whether accepting new cases

### arbitration-votes
Records arbitration decisions with reasoning
- `decision`: Approve or reject dispute
- `reasoning-hash`: Hash of arbitrator's written reasoning
- `voted-at`: Block height of decision

## Public Functions

### register-arbitrator()
Allows users to become arbitrators by staking tokens
- Stakes validator-stake-required amount
- Initializes with 100 accuracy score
- Sets active status to true

### file-dispute(reason, evidence-hash)
Policyholders can dispute rejected claims
- Requires processed (rejected) claim
- Pays arbitration fee
- Stores dispute details with evidence hash
- Opens 2880-block resolution window

### accept-arbitration(dispute-owner)
Arbitrators claim disputes to resolve
- Must be registered and active
- Dispute must not have assigned arbitrator
- Links arbitrator to dispute

### resolve-dispute(dispute-owner, approve, reasoning-hash)
Arbitrators issue binding decisions
- Must be assigned arbitrator
- Within dispute window timeframe
- Records decision with reasoning hash
- If approved: transfers claim payout to dispute owner
- Arbitrator receives reward regardless of decision
- Updates arbitrator's cases-resolved count

### withdraw-arbitrator-stake()
Arbitrators can exit and reclaim stake
- Transfers full stake back
- Removes arbitrator registration

### deactivate-arbitrator()
Temporarily stop accepting new cases
- Sets is-active to false
- Maintains registration and stake

### reactivate-arbitrator()
Resume accepting arbitration cases
- Sets is-active to true

## Read-Only Functions

### get-dispute-info(owner)
Returns complete dispute record for a principal

### get-arbitrator-info(arbitrator)
Returns arbitrator profile and statistics

### get-arbitration-decision(dispute-owner, arbitrator)
Returns specific arbitration decision details

### check-dispute-status(owner)
Returns comprehensive dispute status including:
- Whether dispute is active
- Blocks remaining in dispute window
- Arbitrator assignment status
- Resolution status

## Usage Flow

1. **User's claim is rejected** → Claim processed with failed validation
2. **User files dispute** → Calls `file-dispute()` with reason and evidence
3. **Arbitrator accepts case** → Calls `accept-arbitration()` to take assignment
4. **Arbitrator reviews evidence** → Off-chain review of dispute materials
5. **Arbitrator resolves** → Calls `resolve-dispute()` with decision
6. **Automatic execution** → Approved disputes trigger immediate payout

## Integration Points

- Reuses `validator-stake-required` for arbitrator stakes
- Integrates with existing `theft-claims` map
- Updates `insurance-pool` for fees and payouts
- Compatible with existing claim validation system

## Security Features

- Time-bound dispute window prevents indefinite challenges
- Staking requirement ensures arbitrator accountability
- Evidence hashing enables off-chain verification
- Single arbitrator per dispute prevents double-resolution
- One dispute per claim prevents spam
