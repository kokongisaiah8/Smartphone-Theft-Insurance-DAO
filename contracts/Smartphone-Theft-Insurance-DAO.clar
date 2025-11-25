(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-INVALID-IMEI (err u102))
(define-constant ERR-ALREADY-INSURED (err u103))
(define-constant ERR-NOT-INSURED (err u104))
(define-constant ERR-CLAIM-EXISTS (err u105))
(define-constant ERR-NO-CLAIM (err u106))
(define-constant ERR-INVALID-VOTE (err u107))

(define-data-var insurance-pool uint u0)
(define-data-var monthly-premium uint u10000000)
(define-data-var claim-payout uint u1000000000)
(define-data-var vote-threshold uint u5)

(define-map insured-devices 
    principal 
    {imei: (string-ascii 15), last-payment: uint}
)

(define-map theft-claims 
    principal 
    {imei: (string-ascii 15), timestamp: uint, votes: uint, processed: bool}
)

(define-map claim-votes 
    {claim-owner: principal, voter: principal} 
    bool
)

(define-public (register-device (imei (string-ascii 15)))
    (let ((existing-device (get imei (map-get? insured-devices tx-sender))))
        (asserts! (is-none existing-device) ERR-ALREADY-INSURED)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (ok (map-set insured-devices 
            tx-sender 
            {imei: imei, last-payment: stacks-block-height}))))

(define-public (pay-premium)
    (let ((device (map-get? insured-devices tx-sender)))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (ok (map-set insured-devices 
            tx-sender 
            {imei: (get imei (unwrap-panic device)), last-payment: stacks-block-height}))))

(define-public (file-claim)
    (let ((device (map-get? insured-devices tx-sender))
          (existing-claim (map-get? theft-claims tx-sender)))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (asserts! (is-none existing-claim) ERR-CLAIM-EXISTS)
        (ok (map-set theft-claims 
            tx-sender 
            {imei: (get imei (unwrap-panic device)), 
             timestamp: stacks-block-height,
             votes: u0,
             processed: false}))))

(define-public (vote-on-claim (claim-owner principal))
    (let ((claim (map-get? theft-claims claim-owner))
          (previous-vote (map-get? claim-votes {claim-owner: claim-owner, voter: tx-sender})))
        (asserts! (is-some claim) ERR-NO-CLAIM)
        (asserts! (not (get processed (unwrap-panic claim))) ERR-INVALID-VOTE)
        (asserts! (is-none previous-vote) ERR-INVALID-VOTE)
        (map-set claim-votes {claim-owner: claim-owner, voter: tx-sender} true)
        (let ((updated-votes (+ (get votes (unwrap-panic claim)) u1)))
            (map-set theft-claims claim-owner 
                (merge (unwrap-panic claim) {votes: updated-votes}))
            (if (>= updated-votes (var-get vote-threshold))
                (process-claim claim-owner)
                (ok true)))))

(define-private (process-claim (claim-owner principal))
    (let ((claim (unwrap-panic (map-get? theft-claims claim-owner))))
        (try! (as-contract (stx-transfer? (var-get claim-payout) tx-sender claim-owner)))
        (var-set insurance-pool (- (var-get insurance-pool) (var-get claim-payout)))
        (map-set theft-claims claim-owner (merge claim {processed: true}))
        (ok true)))

(define-read-only (get-device-info (owner principal))
    (ok (map-get? insured-devices owner)))

(define-read-only (get-claim-info (owner principal))
    (ok (map-get? theft-claims owner)))

(define-read-only (get-insurance-pool)
    (ok (var-get insurance-pool)))

(define-constant ERR-POLICY-EXPIRED (err u108))
(define-constant ERR-GRACE-PERIOD-EXPIRED (err u109))

(define-data-var grace-period-blocks uint u1440)
(define-data-var late-fee-percentage uint u20)

(define-map policy-status
    principal
    {active: bool, grace-period-start: (optional uint)}
)

(define-public (check-policy-status (user principal))
    (let ((device (map-get? insured-devices user))
          (current-status (default-to {active: false, grace-period-start: none} 
                                    (map-get? policy-status user))))
        (match device
            device-info
            (let ((blocks-since-payment (- stacks-block-height (get last-payment device-info)))
                  (payment-due-blocks u4320))
                (if (<= blocks-since-payment payment-due-blocks)
                    (begin
                        (map-set policy-status user {active: true, grace-period-start: none})
                        (ok {status: "active", blocks-overdue: u0}))
                    (if (<= blocks-since-payment (+ payment-due-blocks (var-get grace-period-blocks)))
                        (begin
                            (map-set policy-status user 
                                {active: false, 
                                 grace-period-start: (some (+ (get last-payment device-info) payment-due-blocks))})
                            (ok {status: "grace-period", blocks-overdue: (- blocks-since-payment payment-due-blocks)}))
                        (begin
                            (map-set policy-status user {active: false, grace-period-start: none})
                            (ok {status: "expired", blocks-overdue: (- blocks-since-payment payment-due-blocks)})))))
            (ok {status: "not-insured", blocks-overdue: u0}))))

(define-public (pay-overdue-premium)
    (let ((device (map-get? insured-devices tx-sender))
          (status-check (unwrap-panic (check-policy-status tx-sender))))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (asserts! (not (is-eq (get status status-check) "expired")) ERR-GRACE-PERIOD-EXPIRED)
        (let ((base-premium (var-get monthly-premium))
              (late-fee (/ (* base-premium (var-get late-fee-percentage)) u100))
              (total-payment (+ base-premium late-fee)))
            (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
            (var-set insurance-pool (+ (var-get insurance-pool) total-payment))
            (map-set insured-devices 
                tx-sender 
                {imei: (get imei (unwrap-panic device)), last-payment: stacks-block-height})
            (map-set policy-status tx-sender {active: true, grace-period-start: none})
            (ok total-payment))))

(define-public (reinstate-expired-policy (imei (string-ascii 15)))
    (let ((status-check (unwrap-panic (check-policy-status tx-sender))))
        (asserts! (is-eq (get status status-check) "expired") ERR-NOT-AUTHORIZED)
        (let ((reinstatement-fee (* (var-get monthly-premium) u2)))
            (try! (stx-transfer? reinstatement-fee tx-sender (as-contract tx-sender)))
            (var-set insurance-pool (+ (var-get insurance-pool) reinstatement-fee))
            (map-set insured-devices 
                tx-sender 
                {imei: imei, last-payment: stacks-block-height})
            (map-set policy-status tx-sender {active: true, grace-period-start: none})
            (ok reinstatement-fee))))

(define-read-only (get-policy-status (user principal))
    (let ((device (map-get? insured-devices user))
          (current-status (default-to {active: false, grace-period-start: none} 
                                    (map-get? policy-status user))))
        (match device
            device-info
            (let ((blocks-since-payment (- stacks-block-height (get last-payment device-info)))
                  (payment-due-blocks u4320))
                (if (<= blocks-since-payment payment-due-blocks)
                    {status: "active", blocks-overdue: u0}
                    (if (<= blocks-since-payment (+ payment-due-blocks (var-get grace-period-blocks)))
                        {status: "grace-period", blocks-overdue: (- blocks-since-payment payment-due-blocks)}
                        {status: "expired", blocks-overdue: (- blocks-since-payment payment-due-blocks)})))
            {status: "not-insured", blocks-overdue: u0})))

(define-constant ERR-NOT-VALIDATOR (err u110))
(define-constant ERR-VALIDATOR-EXISTS (err u111))
(define-constant ERR-INSUFFICIENT-STAKE (err u112))
(define-constant ERR-DEVICE-NOT-FOUND (err u113))
(define-constant ERR-MAX-DEVICES-REACHED (err u114))
(define-constant ERR-DEVICE-ALREADY-EXISTS (err u115))

(define-data-var validator-stake-required uint u50000000)
(define-data-var validation-reward uint u5000000)
(define-data-var required-validator-signatures uint u3)
(define-data-var max-devices-per-user uint u5)

(define-map user-devices
    principal
    {device-count: uint, total-premium: uint}
)

(define-map device-registry
    {owner: principal, device-id: uint}
    {imei: (string-ascii 15), last-payment: uint, device-type: (string-ascii 20)}
)

(define-map user-device-counter
    principal
    uint
)

(define-map validators
    principal
    {stake: uint, total-validations: uint, reputation-score: uint}
)

(define-map claim-validations
    {claim-owner: principal, validator: principal}
    {approved: bool, timestamp: uint}
)

(define-map claim-validation-summary
    principal
    {approvals: uint, rejections: uint, total-validators: uint}
)

(define-public (register-validator)
    (let ((existing-validator (map-get? validators tx-sender)))
        (asserts! (is-none existing-validator) ERR-VALIDATOR-EXISTS)
        (try! (stx-transfer? (var-get validator-stake-required) tx-sender (as-contract tx-sender)))
        (map-set validators tx-sender 
            {stake: (var-get validator-stake-required), 
             total-validations: u0, 
             reputation-score: u100})
        (ok true)))

(define-public (validate-claim (claim-owner principal) (approve bool))
    (let ((validator-info (map-get? validators tx-sender))
          (claim (map-get? theft-claims claim-owner))
          (existing-validation (map-get? claim-validations {claim-owner: claim-owner, validator: tx-sender})))
        (asserts! (is-some validator-info) ERR-NOT-VALIDATOR)
        (asserts! (is-some claim) ERR-NO-CLAIM)
        (asserts! (not (get processed (unwrap-panic claim))) ERR-INVALID-VOTE)
        (asserts! (is-none existing-validation) ERR-INVALID-VOTE)
        (map-set claim-validations 
            {claim-owner: claim-owner, validator: tx-sender}
            {approved: approve, timestamp: stacks-block-height})
        (let ((current-summary (default-to {approvals: u0, rejections: u0, total-validators: u0}
                                         (map-get? claim-validation-summary claim-owner)))
              (new-approvals (if approve (+ (get approvals current-summary) u1) (get approvals current-summary)))
              (new-rejections (if approve (get rejections current-summary) (+ (get rejections current-summary) u1)))
              (new-total (+ (get total-validators current-summary) u1)))
            (map-set claim-validation-summary claim-owner
                {approvals: new-approvals, rejections: new-rejections, total-validators: new-total})
            (map-set validators tx-sender
                (merge (unwrap-panic validator-info) 
                       {total-validations: (+ (get total-validations (unwrap-panic validator-info)) u1)}))
            (try! (as-contract (stx-transfer? (var-get validation-reward) tx-sender tx-sender)))
            (if (>= new-approvals (var-get required-validator-signatures))
                (process-validated-claim claim-owner)
                (ok true)))))

(define-private (process-validated-claim (claim-owner principal))
    (let ((claim (unwrap-panic (map-get? theft-claims claim-owner))))
        (try! (as-contract (stx-transfer? (var-get claim-payout) tx-sender claim-owner)))
        (var-set insurance-pool (- (var-get insurance-pool) (var-get claim-payout)))
        (map-set theft-claims claim-owner (merge claim {processed: true}))
        (ok true)))

(define-public (withdraw-validator-stake)
    (let ((validator-info (map-get? validators tx-sender)))
        (asserts! (is-some validator-info) ERR-NOT-VALIDATOR)
        (try! (as-contract (stx-transfer? (get stake (unwrap-panic validator-info)) tx-sender tx-sender)))
        (map-delete validators tx-sender)
        (ok (get stake (unwrap-panic validator-info)))))

(define-read-only (get-validator-info (validator principal))
    (ok (map-get? validators validator)))

(define-read-only (get-claim-validation-summary (claim-owner principal))
    (ok (map-get? claim-validation-summary claim-owner)))

(define-public (register-multiple-device (imei (string-ascii 15)) (device-type (string-ascii 20)))
    (let ((user-info (default-to {device-count: u0, total-premium: u0} (map-get? user-devices tx-sender)))
          (device-counter (default-to u0 (map-get? user-device-counter tx-sender)))
          (next-device-id (+ device-counter u1)))
        (asserts! (< (get device-count user-info) (var-get max-devices-per-user)) ERR-MAX-DEVICES-REACHED)
        (asserts! (is-none (map-get? device-registry {owner: tx-sender, device-id: next-device-id})) ERR-DEVICE-ALREADY-EXISTS)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (map-set device-registry 
            {owner: tx-sender, device-id: next-device-id}
            {imei: imei, last-payment: stacks-block-height, device-type: device-type})
        (map-set user-devices tx-sender
            {device-count: (+ (get device-count user-info) u1),
             total-premium: (+ (get total-premium user-info) (var-get monthly-premium))})
        (map-set user-device-counter tx-sender next-device-id)
        (ok next-device-id)))

(define-public (pay-bulk-premiums)
    (let ((user-info (map-get? user-devices tx-sender)))
        (asserts! (is-some user-info) ERR-NOT-INSURED)
        (let ((device-count (get device-count (unwrap-panic user-info)))
              (total-payment (* device-count (var-get monthly-premium))))
            (try! (stx-transfer? total-payment tx-sender (as-contract tx-sender)))
            (var-set insurance-pool (+ (var-get insurance-pool) total-payment))
            (map-set user-devices tx-sender
                (merge (unwrap-panic user-info) {total-premium: (+ (get total-premium (unwrap-panic user-info)) total-payment)}))
            (ok total-payment))))

(define-public (file-device-claim (device-id uint))
    (let ((device (map-get? device-registry {owner: tx-sender, device-id: device-id}))
          (existing-claim (map-get? theft-claims tx-sender)))
        (asserts! (is-some device) ERR-DEVICE-NOT-FOUND)
        (asserts! (is-none existing-claim) ERR-CLAIM-EXISTS)
        (ok (map-set theft-claims 
            tx-sender 
            {imei: (get imei (unwrap-panic device)), 
             timestamp: stacks-block-height,
             votes: u0,
             processed: false}))))

(define-public (remove-device (device-id uint))
    (let ((device (map-get? device-registry {owner: tx-sender, device-id: device-id}))
          (user-info (map-get? user-devices tx-sender)))
        (asserts! (is-some device) ERR-DEVICE-NOT-FOUND)
        (asserts! (is-some user-info) ERR-NOT-INSURED)
        (map-delete device-registry {owner: tx-sender, device-id: device-id})
        (map-set user-devices tx-sender
            {device-count: (- (get device-count (unwrap-panic user-info)) u1),
             total-premium: (- (get total-premium (unwrap-panic user-info)) (var-get monthly-premium))})
        (ok true)))

(define-read-only (get-user-devices (user principal))
    (ok (map-get? user-devices user)))

(define-read-only (get-device-details (user principal) (device-id uint))
    (ok (map-get? device-registry {owner: user, device-id: device-id})))

(define-read-only (get-all-user-device-ids (user principal))
    (let ((user-info (map-get? user-devices user)))
        (match user-info
            info (ok (get device-count info))
            (ok u0))))

(define-constant ERR-INVALID-RISK-SCORE (err u116))

(define-data-var base-premium-multiplier uint u100)
(define-data-var risk-adjustment-factor uint u20)

(define-map user-risk-profile
    principal
    {risk-score: uint, 
     claims-filed: uint, 
     successful-claims: uint, 
     payment-delays: uint, 
     last-risk-update: uint,
     premium-discount: uint}
)

(define-map device-risk-factors
    (string-ascii 20)
    {theft-rate: uint, premium-multiplier: uint}
)

(define-public (initialize-risk-factors)
    (begin
        (map-set device-risk-factors "smartphone" {theft-rate: u85, premium-multiplier: u100})
        (map-set device-risk-factors "tablet" {theft-rate: u65, premium-multiplier: u80})
        (map-set device-risk-factors "laptop" {theft-rate: u45, premium-multiplier: u120})
        (map-set device-risk-factors "smartwatch" {theft-rate: u25, premium-multiplier: u60})
        (map-set device-risk-factors "gaming-console" {theft-rate: u75, premium-multiplier: u110})
        (ok true)))

(define-private (calculate-risk-score (user principal))
    (let ((profile (default-to {risk-score: u50, claims-filed: u0, successful-claims: u0, payment-delays: u0, last-risk-update: u0, premium-discount: u0}
                              (map-get? user-risk-profile user)))
          (claims-ratio (if (> (get claims-filed profile) u0)
                          (/ (* (get successful-claims profile) u100) (get claims-filed profile))
                          u0))
          (base-score u50)
          (claims-penalty (* (get claims-filed profile) u15))
          (payment-penalty (* (get payment-delays profile) u8))
          (good-behavior-bonus (if (and (> (- stacks-block-height (get last-risk-update profile)) u8640)
                                       (is-eq (get claims-filed profile) u0))
                                 u10
                                 u0)))
        (+ (- (- base-score claims-penalty) payment-penalty) good-behavior-bonus)))

(define-public (update-user-risk-profile (user principal))
    (let ((current-profile (default-to {risk-score: u50, claims-filed: u0, successful-claims: u0, payment-delays: u0, last-risk-update: u0, premium-discount: u0}
                                     (map-get? user-risk-profile user)))
          (new-risk-score (calculate-risk-score user))
          (discount-percentage (if (<= new-risk-score u30) u15
                                (if (<= new-risk-score u40) u10
                                 (if (<= new-risk-score u60) u0
                                  (if (<= new-risk-score u80) u0
                                   u20))))))
        (map-set user-risk-profile user
            (merge current-profile {risk-score: new-risk-score, 
                                   last-risk-update: stacks-block-height,
                                   premium-discount: discount-percentage}))
        (ok {risk-score: new-risk-score, discount: discount-percentage})))

(define-public (calculate-dynamic-premium (user principal) (device-type (string-ascii 20)))
    (let ((risk-factors (map-get? device-risk-factors device-type))
          (user-profile (map-get? user-risk-profile user))
          (base-premium (var-get monthly-premium)))
        (match risk-factors
            device-factor
            (match user-profile
                profile
                (let ((device-multiplier (get premium-multiplier device-factor))
                      (user-discount (get premium-discount profile))
                      (adjusted-premium (/ (* base-premium device-multiplier) u100))
                      (final-premium (- adjusted-premium (/ (* adjusted-premium user-discount) u100))))
                    (ok final-premium))
                (ok base-premium))
            (ok base-premium))))

(define-public (register-device-with-risk-assessment (imei (string-ascii 15)) (device-type (string-ascii 20)))
    (let ((existing-device (get imei (map-get? insured-devices tx-sender)))
          (dynamic-premium-result (unwrap-panic (calculate-dynamic-premium tx-sender device-type))))
        (asserts! (is-none existing-device) ERR-ALREADY-INSURED)
        (unwrap-panic (update-user-risk-profile tx-sender))
        (try! (stx-transfer? dynamic-premium-result tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) dynamic-premium-result))
        (ok (map-set insured-devices 
            tx-sender 
            {imei: imei, last-payment: stacks-block-height}))))

(define-public (record-claim-outcome (claim-owner principal) (successful bool))
    (let ((current-profile (default-to {risk-score: u50, claims-filed: u0, successful-claims: u0, payment-delays: u0, last-risk-update: u0, premium-discount: u0}
                                     (map-get? user-risk-profile claim-owner)))
          (new-successful-claims (if successful (+ (get successful-claims current-profile) u1) (get successful-claims current-profile))))
        (map-set user-risk-profile claim-owner
            (merge current-profile {claims-filed: (+ (get claims-filed current-profile) u1),
                                   successful-claims: new-successful-claims}))
        (unwrap-panic (update-user-risk-profile claim-owner))
        (ok true)))

(define-public (record-payment-delay (user principal))
    (let ((current-profile (default-to {risk-score: u50, claims-filed: u0, successful-claims: u0, payment-delays: u0, last-risk-update: u0, premium-discount: u0}
                                     (map-get? user-risk-profile user))))
        (map-set user-risk-profile user
            (merge current-profile {payment-delays: (+ (get payment-delays current-profile) u1)}))
        (unwrap-panic (update-user-risk-profile user))
        (ok true)))

(define-read-only (get-user-risk-profile (user principal))
    (ok (map-get? user-risk-profile user)))

(define-read-only (get-device-risk-factors (device-type (string-ascii 20)))
    (ok (map-get? device-risk-factors device-type)))

(define-read-only (get-premium-quote (user principal) (device-type (string-ascii 20)))
    (calculate-dynamic-premium user device-type))

(define-constant ERR-ALREADY-REFERRED (err u117))
(define-constant ERR-SELF-REFERRAL (err u118))
(define-constant ERR-REFERRER-NOT-FOUND (err u119))
(define-constant ERR-INSUFFICIENT-POOL (err u120))

(define-data-var referral-reward uint u5000000)
(define-data-var loyalty-reward-threshold uint u12)
(define-data-var loyalty-reward-amount uint u3000000)

(define-map user-referrals
    principal
    {referrer: (optional principal), 
     referral-count: uint, 
     total-rewards-earned: uint}
)

(define-map loyalty-tracker
    principal
    {consecutive-payments: uint, 
     total-payments: uint, 
     last-claim-block: uint, 
     lifetime-rewards: uint}
)

(define-map referral-ledger
    {referrer: principal, referee: principal}
    {timestamp: uint, reward-claimed: bool}
)

(define-public (register-with-referral (imei (string-ascii 15)) (referrer principal))
    (let ((existing-device (get imei (map-get? insured-devices tx-sender)))
          (existing-referral (map-get? user-referrals tx-sender))
          (referrer-info (map-get? insured-devices referrer)))
        (asserts! (is-none existing-device) ERR-ALREADY-INSURED)
        (asserts! (not (is-eq tx-sender referrer)) ERR-SELF-REFERRAL)
        (asserts! (is-some referrer-info) ERR-REFERRER-NOT-FOUND)
        (asserts! (is-none existing-referral) ERR-ALREADY-REFERRED)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (map-set insured-devices tx-sender {imei: imei, last-payment: stacks-block-height})
        (map-set user-referrals tx-sender 
            {referrer: (some referrer), referral-count: u0, total-rewards-earned: u0})
        (map-set referral-ledger {referrer: referrer, referee: tx-sender}
            {timestamp: stacks-block-height, reward-claimed: false})
        (let ((referrer-data (default-to {referrer: none, referral-count: u0, total-rewards-earned: u0}
                                       (map-get? user-referrals referrer))))
            (map-set user-referrals referrer
                {referrer: (get referrer referrer-data),
                 referral-count: (+ (get referral-count referrer-data) u1),
                 total-rewards-earned: (get total-rewards-earned referrer-data)})
            (ok true))))

(define-public (claim-referral-reward (referee principal))
    (let ((ledger-entry (map-get? referral-ledger {referrer: tx-sender, referee: referee}))
          (referrer-data (map-get? user-referrals tx-sender))
          (referee-device (map-get? insured-devices referee)))
        (asserts! (is-some ledger-entry) ERR-REFERRER-NOT-FOUND)
        (asserts! (not (get reward-claimed (unwrap-panic ledger-entry))) ERR-ALREADY-REFERRED)
        (asserts! (is-some referee-device) ERR-NOT-INSURED)
        (asserts! (>= (var-get insurance-pool) (var-get referral-reward)) ERR-INSUFFICIENT-POOL)
        (try! (as-contract (stx-transfer? (var-get referral-reward) tx-sender tx-sender)))
        (var-set insurance-pool (- (var-get insurance-pool) (var-get referral-reward)))
        (map-set referral-ledger {referrer: tx-sender, referee: referee}
            (merge (unwrap-panic ledger-entry) {reward-claimed: true}))
        (let ((updated-data (unwrap-panic referrer-data)))
            (map-set user-referrals tx-sender
                (merge updated-data {total-rewards-earned: (+ (get total-rewards-earned updated-data) (var-get referral-reward))}))
            (ok (var-get referral-reward)))))

(define-public (track-loyalty-payment)
    (let ((device (map-get? insured-devices tx-sender))
          (loyalty-data (default-to {consecutive-payments: u0, total-payments: u0, last-claim-block: u0, lifetime-rewards: u0}
                                   (map-get? loyalty-tracker tx-sender))))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (let ((payment-gap (- stacks-block-height (get last-claim-block loyalty-data)))
              (consecutive (if (<= payment-gap u4320) 
                             (+ (get consecutive-payments loyalty-data) u1)
                             u1)))
            (map-set loyalty-tracker tx-sender
                {consecutive-payments: consecutive,
                 total-payments: (+ (get total-payments loyalty-data) u1),
                 last-claim-block: stacks-block-height,
                 lifetime-rewards: (get lifetime-rewards loyalty-data)})
            (ok consecutive))))

(define-public (claim-loyalty-reward)
    (let ((loyalty-data (map-get? loyalty-tracker tx-sender)))
        (asserts! (is-some loyalty-data) ERR-NOT-INSURED)
        (let ((data (unwrap-panic loyalty-data)))
            (asserts! (>= (get consecutive-payments data) (var-get loyalty-reward-threshold)) ERR-NOT-AUTHORIZED)
            (asserts! (>= (var-get insurance-pool) (var-get loyalty-reward-amount)) ERR-INSUFFICIENT-POOL)
            (try! (as-contract (stx-transfer? (var-get loyalty-reward-amount) tx-sender tx-sender)))
            (var-set insurance-pool (- (var-get insurance-pool) (var-get loyalty-reward-amount)))
            (map-set loyalty-tracker tx-sender
                {consecutive-payments: u0,
                 total-payments: (get total-payments data),
                 last-claim-block: (get last-claim-block data),
                 lifetime-rewards: (+ (get lifetime-rewards data) (var-get loyalty-reward-amount))})
            (ok (var-get loyalty-reward-amount)))))

(define-public (pay-premium-with-loyalty-tracking)
    (let ((device (map-get? insured-devices tx-sender)))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (map-set insured-devices tx-sender
            {imei: (get imei (unwrap-panic device)), last-payment: stacks-block-height})
        (unwrap-panic (track-loyalty-payment))
        (ok true)))

(define-read-only (get-referral-stats (user principal))
    (ok (map-get? user-referrals user)))

(define-read-only (get-loyalty-stats (user principal))
    (ok (map-get? loyalty-tracker user)))

(define-read-only (get-referral-ledger-entry (referrer principal) (referee principal))
    (ok (map-get? referral-ledger {referrer: referrer, referee: referee})))

(define-read-only (calculate-total-user-rewards (user principal))
    (let ((referral-data (map-get? user-referrals user))
          (loyalty-data (map-get? loyalty-tracker user)))
        (ok {referral-rewards: (match referral-data 
                                 data (get total-rewards-earned data)
                                 u0),
             loyalty-rewards: (match loyalty-data
                               data (get lifetime-rewards data)
                               u0)})))

(define-constant ERR-NO-DISPUTE (err u121))
(define-constant ERR-DISPUTE-EXISTS (err u122))
(define-constant ERR-DISPUTE-EXPIRED (err u123))
(define-constant ERR-NOT-ARBITRATOR (err u124))
(define-constant ERR-INVALID-EVIDENCE (err u125))

(define-data-var dispute-window-blocks uint u2880)
(define-data-var arbitration-fee uint u2000000)
(define-data-var arbitrator-reward uint u1000000)

(define-map claim-disputes
    principal
    {dispute-reason: (string-ascii 200),
     evidence-hash: (string-ascii 64),
     filed-at: uint,
     arbitrator: (optional principal),
     resolution: (optional bool),
     resolved-at: (optional uint)}
)

(define-map arbitrators
    principal
    {stake: uint,
     cases-resolved: uint,
     accuracy-score: uint,
     is-active: bool}
)

(define-map arbitration-votes
    {dispute-owner: principal, arbitrator: principal}
    {decision: bool, reasoning-hash: (string-ascii 64), voted-at: uint}
)

(define-public (register-arbitrator)
    (let ((existing-arbitrator (map-get? arbitrators tx-sender)))
        (asserts! (is-none existing-arbitrator) ERR-VALIDATOR-EXISTS)
        (try! (stx-transfer? (var-get validator-stake-required) tx-sender (as-contract tx-sender)))
        (map-set arbitrators tx-sender
            {stake: (var-get validator-stake-required),
             cases-resolved: u0,
             accuracy-score: u100,
             is-active: true})
        (ok true)))

(define-public (file-dispute (reason (string-ascii 200)) (evidence-hash (string-ascii 64)))
    (let ((claim (map-get? theft-claims tx-sender))
          (existing-dispute (map-get? claim-disputes tx-sender)))
        (asserts! (is-some claim) ERR-NO-CLAIM)
        (asserts! (get processed (unwrap-panic claim)) ERR-INVALID-VOTE)
        (asserts! (is-none existing-dispute) ERR-DISPUTE-EXISTS)
        (try! (stx-transfer? (var-get arbitration-fee) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get arbitration-fee)))
        (map-set claim-disputes tx-sender
            {dispute-reason: reason,
             evidence-hash: evidence-hash,
             filed-at: stacks-block-height,
             arbitrator: none,
             resolution: none,
             resolved-at: none})
        (ok true)))

(define-public (accept-arbitration (dispute-owner principal))
    (let ((arbitrator-info (map-get? arbitrators tx-sender))
          (dispute (map-get? claim-disputes dispute-owner)))
        (asserts! (is-some arbitrator-info) ERR-NOT-ARBITRATOR)
        (asserts! (get is-active (unwrap-panic arbitrator-info)) ERR-NOT-ARBITRATOR)
        (asserts! (is-some dispute) ERR-NO-DISPUTE)
        (asserts! (is-none (get arbitrator (unwrap-panic dispute))) ERR-DISPUTE-EXISTS)
        (map-set claim-disputes dispute-owner
            (merge (unwrap-panic dispute) {arbitrator: (some tx-sender)}))
        (ok true)))

(define-public (resolve-dispute (dispute-owner principal) (approve bool) (reasoning-hash (string-ascii 64)))
    (let ((arbitrator-info (map-get? arbitrators tx-sender))
          (dispute (map-get? claim-disputes dispute-owner))
          (claim (map-get? theft-claims dispute-owner)))
        (asserts! (is-some arbitrator-info) ERR-NOT-ARBITRATOR)
        (asserts! (is-some dispute) ERR-NO-DISPUTE)
        (asserts! (is-some claim) ERR-NO-CLAIM)
        (asserts! (is-eq (get arbitrator (unwrap-panic dispute)) (some tx-sender)) ERR-NOT-ARBITRATOR)
        (asserts! (is-none (get resolution (unwrap-panic dispute))) ERR-DISPUTE-EXISTS)
        (let ((blocks-elapsed (- stacks-block-height (get filed-at (unwrap-panic dispute)))))
            (asserts! (<= blocks-elapsed (var-get dispute-window-blocks)) ERR-DISPUTE-EXPIRED)
            (map-set arbitration-votes
                {dispute-owner: dispute-owner, arbitrator: tx-sender}
                {decision: approve, reasoning-hash: reasoning-hash, voted-at: stacks-block-height})
            (map-set claim-disputes dispute-owner
                (merge (unwrap-panic dispute) 
                       {resolution: (some approve), resolved-at: (some stacks-block-height)}))
            (map-set arbitrators tx-sender
                (merge (unwrap-panic arbitrator-info)
                       {cases-resolved: (+ (get cases-resolved (unwrap-panic arbitrator-info)) u1)}))
            (if approve
                (begin
                    (try! (as-contract (stx-transfer? (var-get claim-payout) tx-sender dispute-owner)))
                    (var-set insurance-pool (- (var-get insurance-pool) (var-get claim-payout)))
                    (try! (as-contract (stx-transfer? (var-get arbitrator-reward) tx-sender tx-sender)))
                    (var-set insurance-pool (- (var-get insurance-pool) (var-get arbitrator-reward)))
                    (ok true))
                (begin
                    (try! (as-contract (stx-transfer? (var-get arbitrator-reward) tx-sender tx-sender)))
                    (var-set insurance-pool (- (var-get insurance-pool) (var-get arbitrator-reward)))
                    (ok false))))))

(define-public (withdraw-arbitrator-stake)
    (let ((arbitrator-info (map-get? arbitrators tx-sender)))
        (asserts! (is-some arbitrator-info) ERR-NOT-ARBITRATOR)
        (try! (as-contract (stx-transfer? (get stake (unwrap-panic arbitrator-info)) tx-sender tx-sender)))
        (map-delete arbitrators tx-sender)
        (ok (get stake (unwrap-panic arbitrator-info)))))

(define-public (deactivate-arbitrator)
    (let ((arbitrator-info (map-get? arbitrators tx-sender)))
        (asserts! (is-some arbitrator-info) ERR-NOT-ARBITRATOR)
        (map-set arbitrators tx-sender
            (merge (unwrap-panic arbitrator-info) {is-active: false}))
        (ok true)))

(define-public (reactivate-arbitrator)
    (let ((arbitrator-info (map-get? arbitrators tx-sender)))
        (asserts! (is-some arbitrator-info) ERR-NOT-ARBITRATOR)
        (map-set arbitrators tx-sender
            (merge (unwrap-panic arbitrator-info) {is-active: true}))
        (ok true)))

(define-read-only (get-dispute-info (owner principal))
    (ok (map-get? claim-disputes owner)))

(define-read-only (get-arbitrator-info (arbitrator principal))
    (ok (map-get? arbitrators arbitrator)))

(define-read-only (get-arbitration-decision (dispute-owner principal) (arbitrator principal))
    (ok (map-get? arbitration-votes {dispute-owner: dispute-owner, arbitrator: arbitrator})))

(define-read-only (check-dispute-status (owner principal))
    (let ((dispute (map-get? claim-disputes owner)))
        (match dispute
            dispute-data
            (let ((blocks-elapsed (- stacks-block-height (get filed-at dispute-data))))
                (ok {dispute-active: (is-none (get resolution dispute-data)),
                     time-remaining: (if (> (var-get dispute-window-blocks) blocks-elapsed)
                                       (- (var-get dispute-window-blocks) blocks-elapsed)
                                       u0),
                     has-arbitrator: (is-some (get arbitrator dispute-data)),
                     is-resolved: (is-some (get resolution dispute-data))}))
            (ok {dispute-active: false,
                 time-remaining: u0,
                 has-arbitrator: false,
                 is-resolved: false}))))