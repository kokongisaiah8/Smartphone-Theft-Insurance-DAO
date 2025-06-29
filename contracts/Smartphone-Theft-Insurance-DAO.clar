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
