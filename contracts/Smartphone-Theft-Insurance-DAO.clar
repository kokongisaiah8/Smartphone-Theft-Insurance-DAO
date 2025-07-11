(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-INVALID-IMEI (err u102))
(define-constant ERR-ALREADY-INSURED (err u103))
(define-constant ERR-NOT-INSURED (err u104))
(define-constant ERR-CLAIM-EXISTS (err u105))
(define-constant ERR-NO-CLAIM (err u106))
(define-constant ERR-INVALID-VOTE (err u107))

(define-data-var insurance-pool uint u0)
(define-data-var monthly-premium uint u10000000) ;; 10 STX
(define-data-var claim-payout uint u1000000000) ;; 1000 STX
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

(define-data-var validator-stake-required uint u50000000)
(define-data-var validation-reward uint u5000000)
(define-data-var required-validator-signatures uint u3)

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