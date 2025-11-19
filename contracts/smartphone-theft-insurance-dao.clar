(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-insufficient-funds (err u105))
(define-constant err-policy-expired (err u106))
(define-constant err-claim-exists (err u107))
(define-constant err-already-voted (err u108))
(define-constant err-voting-ended (err u109))
(define-constant err-claim-not-approved (err u110))

(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var pool-balance uint u0)
(define-data-var base-premium uint u1000000)
(define-data-var coverage-amount uint u10000000)
(define-data-var voting-period uint u1440)

(define-map policies
    uint
    {
        owner: principal,
        device-id: (string-ascii 64),
        premium: uint,
        coverage: uint,
        start-block: uint,
        end-block: uint,
        active: bool,
        claim-count: uint,
        tenure-months: uint
    }
)

(define-map user-policies principal (list 50 uint))

(define-map claims
    uint
    {
        policy-id: uint,
        claimant: principal,
        amount: uint,
        evidence: (string-ascii 256),
        submitted-at: uint,
        votes-for: uint,
        votes-against: uint,
        status: (string-ascii 20),
        voting-ends: uint
    }
)

(define-map claim-votes
    {claim-id: uint, voter: principal}
    bool
)

(define-map discount-tiers
    uint
    {
        min-tenure: uint,
        max-claims: uint,
        discount-percentage: uint
    }
)

(define-private (calculate-discounted-premium (tenure uint) (claim-count uint))
    (let
        (
            (base (var-get base-premium))
            (tier-1-discount (if (and (>= tenure u6) (<= claim-count u0)) u10 u0))
            (tier-2-discount (if (and (>= tenure u12) (<= claim-count u0)) u20 u0))
            (tier-3-discount (if (and (>= tenure u24) (<= claim-count u0)) u30 u0))
            (tier-4-discount (if (and (>= tenure u36) (<= claim-count u1)) u40 u0))
            (max-discount (fold max-uint (list tier-1-discount tier-2-discount tier-3-discount tier-4-discount) u0))
        )
        (- base (/ (* base max-discount) u100))
    )
)

(define-private (max-uint (a uint) (b uint))
    (if (> a b) a b)
)

(define-public (initialize-discount-tiers)
    (begin
        (map-set discount-tiers u1 {min-tenure: u6, max-claims: u0, discount-percentage: u10})
        (map-set discount-tiers u2 {min-tenure: u12, max-claims: u0, discount-percentage: u20})
        (map-set discount-tiers u3 {min-tenure: u24, max-claims: u0, discount-percentage: u30})
        (map-set discount-tiers u4 {min-tenure: u36, max-claims: u1, discount-percentage: u40})
        (ok true)
    )
)

(define-public (purchase-policy (device-id (string-ascii 64)))
    (let
        (
            (policy-id (+ (var-get policy-counter) u1))
            (premium (var-get base-premium))
            (coverage (var-get coverage-amount))
            (duration u52560)
        )
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        (var-set pool-balance (+ (var-get pool-balance) premium))
        (var-set policy-counter policy-id)
        (map-set policies policy-id
            {
                owner: tx-sender,
                device-id: device-id,
                premium: premium,
                coverage: coverage,
                start-block: stacks-block-height,
                end-block: (+ stacks-block-height duration),
                active: true,
                claim-count: u0,
                tenure-months: u0
            }
        )
        (map-set user-policies tx-sender
            (unwrap! (as-max-len? (append (default-to (list) (map-get? user-policies tx-sender)) policy-id) u50) err-invalid-amount)
        )
        (ok policy-id)
    )
)

(define-public (renew-policy (policy-id uint))
    (let
        (
            (policy (unwrap! (map-get? policies policy-id) err-not-found))
            (new-tenure (+ (get tenure-months policy) u12))
            (discounted-premium (calculate-discounted-premium new-tenure (get claim-count policy)))
            (duration u52560)
        )
        (asserts! (is-eq (get owner policy) tx-sender) err-unauthorized)
        (try! (stx-transfer? discounted-premium tx-sender (as-contract tx-sender)))
        (var-set pool-balance (+ (var-get pool-balance) discounted-premium))
        (map-set policies policy-id
            (merge policy
                {
                    premium: discounted-premium,
                    start-block: stacks-block-height,
                    end-block: (+ stacks-block-height duration),
                    active: true,
                    tenure-months: new-tenure
                }
            )
        )
        (ok discounted-premium)
    )
)

(define-public (submit-claim (policy-id uint) (amount uint) (evidence (string-ascii 256)))
    (let
        (
            (policy (unwrap! (map-get? policies policy-id) err-not-found))
            (claim-id (+ (var-get claim-counter) u1))
        )
        (asserts! (is-eq (get owner policy) tx-sender) err-unauthorized)
        (asserts! (get active policy) err-policy-expired)
        (asserts! (<= stacks-block-height (get end-block policy)) err-policy-expired)
        (asserts! (<= amount (get coverage policy)) err-invalid-amount)
        (var-set claim-counter claim-id)
        (map-set claims claim-id
            {
                policy-id: policy-id,
                claimant: tx-sender,
                amount: amount,
                evidence: evidence,
                submitted-at: stacks-block-height,
                votes-for: u0,
                votes-against: u0,
                status: "pending",
                voting-ends: (+ stacks-block-height (var-get voting-period))
            }
        )
        (ok claim-id)
    )
)

(define-public (vote-on-claim (claim-id uint) (approve bool))
    (let
        (
            (claim (unwrap! (map-get? claims claim-id) err-not-found))
        )
        (asserts! (is-none (map-get? claim-votes {claim-id: claim-id, voter: tx-sender})) err-already-voted)
        (asserts! (<= stacks-block-height (get voting-ends claim)) err-voting-ended)
        (map-set claim-votes {claim-id: claim-id, voter: tx-sender} approve)
        (map-set claims claim-id
            (merge claim
                {
                    votes-for: (if approve (+ (get votes-for claim) u1) (get votes-for claim)),
                    votes-against: (if approve (get votes-against claim) (+ (get votes-against claim) u1))
                }
            )
        )
        (ok true)
    )
)

(define-public (finalize-claim (claim-id uint))
    (let
        (
            (claim (unwrap! (map-get? claims claim-id) err-not-found))
            (policy (unwrap! (map-get? policies (get policy-id claim)) err-not-found))
            (approved (> (get votes-for claim) (get votes-against claim)))
        )
        (asserts! (> stacks-block-height (get voting-ends claim)) err-voting-ended)
        (if approved
            (begin
                (try! (as-contract (stx-transfer? (get amount claim) tx-sender (get claimant claim))))
                (var-set pool-balance (- (var-get pool-balance) (get amount claim)))
                (map-set policies (get policy-id claim)
                    (merge policy {claim-count: (+ (get claim-count policy) u1)})
                )
                (map-set claims claim-id (merge claim {status: "approved"}))
                (ok true)
            )
            (begin
                (map-set claims claim-id (merge claim {status: "rejected"}))
                (ok false)
            )
        )
    )
)

(define-read-only (get-policy (policy-id uint))
    (ok (map-get? policies policy-id))
)

(define-read-only (get-claim (claim-id uint))
    (ok (map-get? claims claim-id))
)

(define-read-only (get-user-policies (user principal))
    (ok (map-get? user-policies user))
)

(define-read-only (get-pool-balance)
    (ok (var-get pool-balance))
)

(define-read-only (get-discount-tier (tier-id uint))
    (ok (map-get? discount-tiers tier-id))
)

(define-read-only (calculate-renewal-premium (policy-id uint))
    (let
        (
            (policy (unwrap! (map-get? policies policy-id) err-not-found))
            (new-tenure (+ (get tenure-months policy) u12))
        )
        (ok (calculate-discounted-premium new-tenure (get claim-count policy)))
    )
)

(define-public (contribute-to-pool (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set pool-balance (+ (var-get pool-balance) amount))
        (ok true)
    )
)

(define-public (update-base-premium (new-premium uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set base-premium new-premium)
        (ok true)
    )
)

(define-public (update-coverage-amount (new-coverage uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set coverage-amount new-coverage)
        (ok true)
    )
)