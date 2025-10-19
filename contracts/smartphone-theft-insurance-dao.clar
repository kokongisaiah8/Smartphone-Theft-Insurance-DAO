;; ============================================================================
;; SMARTPHONE THEFT INSURANCE DAO
;; A comprehensive decentralized insurance platform for smartphone theft protection
;; Built on Stacks blockchain using Clarity v3
;; ============================================================================

;; Core error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-FUNDS (err u101))
(define-constant ERR-INVALID-IMEI (err u102))
(define-constant ERR-ALREADY-INSURED (err u103))
(define-constant ERR-NOT-INSURED (err u104))
(define-constant ERR-CLAIM-EXISTS (err u105))
(define-constant ERR-NO-CLAIM (err u106))
(define-constant ERR-INVALID-VOTE (err u107))
(define-constant ERR-POLICY-EXPIRED (err u108))
(define-constant ERR-GRACE-PERIOD-EXPIRED (err u109))

;; Core insurance data variables
(define-data-var insurance-pool uint u0)
(define-data-var monthly-premium uint u10000000) ;; 10 STX
(define-data-var claim-payout uint u1000000000) ;; 1000 STX
(define-data-var vote-threshold uint u5)
(define-data-var grace-period-blocks uint u1440) ;; ~1 day in blocks
(define-data-var late-fee-percentage uint u20) ;; 20%

;; Core insurance maps
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

(define-map policy-status
    principal
    {active: bool, grace-period-start: (optional uint)}
)

;; ============================================================================
;; CORE INSURANCE FUNCTIONS
;; ============================================================================

(define-public (register-device (imei (string-ascii 15)))
    (let ((existing-device (get imei (map-get? insured-devices tx-sender))))
        (asserts! (is-none existing-device) ERR-ALREADY-INSURED)
        (asserts! (>= (len imei) u15) ERR-INVALID-IMEI)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (map-set insured-devices 
            tx-sender 
            {imei: imei, last-payment: stacks-block-height})
        (map-set policy-status tx-sender {active: true, grace-period-start: none})
        (ok true)))

(define-public (pay-premium)
    (let ((device (map-get? insured-devices tx-sender)))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (try! (stx-transfer? (var-get monthly-premium) tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) (var-get monthly-premium)))
        (map-set insured-devices 
            tx-sender 
            {imei: (get imei (unwrap-panic device)), last-payment: stacks-block-height})
        (map-set policy-status tx-sender {active: true, grace-period-start: none})
        (ok true)))

(define-public (file-claim)
    (let ((device (map-get? insured-devices tx-sender))
          (existing-claim (map-get? theft-claims tx-sender))
          (status (unwrap-panic (check-policy-status tx-sender))))
        (asserts! (is-some device) ERR-NOT-INSURED)
        (asserts! (is-none existing-claim) ERR-CLAIM-EXISTS)
        (asserts! (or (is-eq (get status status) "active") 
                      (is-eq (get status status) "grace-period")) ERR-POLICY-EXPIRED)
        (map-set theft-claims 
            tx-sender 
            {imei: (get imei (unwrap-panic device)), 
             timestamp: stacks-block-height,
             votes: u0,
             processed: false})
        (ok true)))

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
        (asserts! (>= (var-get insurance-pool) (var-get claim-payout)) ERR-INSUFFICIENT-FUNDS)
        (try! (as-contract (stx-transfer? (var-get claim-payout) tx-sender claim-owner)))
        (var-set insurance-pool (- (var-get insurance-pool) (var-get claim-payout)))
        (map-set theft-claims claim-owner (merge claim {processed: true}))
        (ok true)))

(define-public (check-policy-status (user principal))
    (let ((device (map-get? insured-devices user))
          (current-status (default-to {active: false, grace-period-start: none} 
                                    (map-get? policy-status user))))
        (match device
            device-info
            (let ((blocks-since-payment (- stacks-block-height (get last-payment device-info)))
                  (payment-due-blocks u4320)) ;; ~30 days
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

;; ============================================================================
;; SMART NOTIFICATIONS & ALERT SYSTEM
;; Independent feature for managing user notifications and alerts
;; ============================================================================

;; Notification error constants
(define-constant ERR-INVALID-NOTIFICATION-TYPE (err u110))
(define-constant ERR-NOTIFICATION-NOT-FOUND (err u111))
(define-constant ERR-SUBSCRIPTION-EXISTS (err u112))
(define-constant ERR-SUBSCRIPTION-NOT-FOUND (err u113))
(define-constant ERR-INVALID-PRIORITY (err u114))
(define-constant ERR-MAX-NOTIFICATIONS-REACHED (err u115))

;; Notification type constants
(define-constant NOTIFICATION-TYPE-PAYMENT-DUE "payment-due")
(define-constant NOTIFICATION-TYPE-CLAIM-UPDATE "claim-update")
(define-constant NOTIFICATION-TYPE-POLICY-EXPIRY "policy-expiry")
(define-constant NOTIFICATION-TYPE-RISK-CHANGE "risk-change")
(define-constant NOTIFICATION-TYPE-SYSTEM-ALERT "system-alert")

;; Priority constants
(define-constant PRIORITY-LOW u1)
(define-constant PRIORITY-MEDIUM u2)
(define-constant PRIORITY-HIGH u3)
(define-constant PRIORITY-CRITICAL u4)

;; Notification system data variables
(define-data-var notification-counter uint u0)
(define-data-var max-notifications-per-user uint u50)
(define-data-var notification-retention-blocks uint u17280) ;; ~30 days

;; Notification system maps
(define-map user-notification-preferences
    principal
    {email-enabled: bool,
     push-enabled: bool,
     sms-enabled: bool,
     frequency: uint, ;; 1=immediate, 2=daily, 3=weekly
     language: (string-ascii 5)}
)

(define-map notification-subscriptions
    {user: principal, notification-type: (string-ascii 20)}
    {subscribed: bool,
     priority: uint,
     created-at: uint,
     delivery-count: uint}
)

(define-map user-notifications
    {user: principal, notification-id: uint}
    {message: (string-ascii 256),
     notification-type: (string-ascii 20),
     priority: uint,
     timestamp: uint,
     read: bool,
     metadata: (optional (string-ascii 128))}
)

(define-map user-notification-counters
    principal
    {total-notifications: uint,
     unread-notifications: uint,
     last-notification-id: uint}
)

(define-map notification-delivery-log
    {user: principal, notification-id: uint}
    {attempts: uint,
     last-attempt: uint,
     delivered: bool,
     method: (string-ascii 15)}
)

;; Notification management functions
(define-public (setup-notification-preferences 
    (email bool) 
    (push bool) 
    (sms bool) 
    (frequency uint) 
    (language (string-ascii 5)))
    (begin
        (asserts! (and (>= frequency u1) (<= frequency u3)) ERR-INVALID-PRIORITY)
        (map-set user-notification-preferences tx-sender
            {email-enabled: email,
             push-enabled: push,
             sms-enabled: sms,
             frequency: frequency,
             language: language})
        (ok true)))

(define-public (subscribe-to-notification (notification-type (string-ascii 20)) (priority uint))
    (let ((existing-sub (map-get? notification-subscriptions {user: tx-sender, notification-type: notification-type})))
        (asserts! (and (>= priority u1) (<= priority u4)) ERR-INVALID-PRIORITY)
        (asserts! (or (is-eq notification-type NOTIFICATION-TYPE-PAYMENT-DUE)
                      (is-eq notification-type NOTIFICATION-TYPE-CLAIM-UPDATE)
                      (is-eq notification-type NOTIFICATION-TYPE-POLICY-EXPIRY)
                      (is-eq notification-type NOTIFICATION-TYPE-RISK-CHANGE)
                      (is-eq notification-type NOTIFICATION-TYPE-SYSTEM-ALERT))
                  ERR-INVALID-NOTIFICATION-TYPE)
        (map-set notification-subscriptions 
            {user: tx-sender, notification-type: notification-type}
            {subscribed: true,
             priority: priority,
             created-at: stacks-block-height,
             delivery-count: u0})
        (ok true)))

(define-public (unsubscribe-from-notification (notification-type (string-ascii 20)))
    (let ((existing-sub (map-get? notification-subscriptions {user: tx-sender, notification-type: notification-type})))
        (asserts! (is-some existing-sub) ERR-SUBSCRIPTION-NOT-FOUND)
        (map-set notification-subscriptions 
            {user: tx-sender, notification-type: notification-type}
            (merge (unwrap-panic existing-sub) {subscribed: false}))
        (ok true)))

(define-public (create-notification 
    (recipient principal) 
    (message (string-ascii 256)) 
    (notification-type (string-ascii 20)) 
    (priority uint)
    (metadata (optional (string-ascii 128))))
    (let ((user-counter (default-to {total-notifications: u0, unread-notifications: u0, last-notification-id: u0}
                                  (map-get? user-notification-counters recipient)))
          (subscription (map-get? notification-subscriptions {user: recipient, notification-type: notification-type}))
          (new-notification-id (+ (get last-notification-id user-counter) u1)))
        (asserts! (and (>= priority u1) (<= priority u4)) ERR-INVALID-PRIORITY)
        (asserts! (< (get total-notifications user-counter) (var-get max-notifications-per-user)) ERR-MAX-NOTIFICATIONS-REACHED)
        ;; Check if user is subscribed to this notification type
        (if (and (is-some subscription) (get subscribed (unwrap-panic subscription)))
            (begin
                (map-set user-notifications
                    {user: recipient, notification-id: new-notification-id}
                    {message: message,
                     notification-type: notification-type,
                     priority: priority,
                     timestamp: stacks-block-height,
                     read: false,
                     metadata: metadata})
                (map-set user-notification-counters recipient
                    {total-notifications: (+ (get total-notifications user-counter) u1),
                     unread-notifications: (+ (get unread-notifications user-counter) u1),
                     last-notification-id: new-notification-id})
                (map-set notification-subscriptions 
                    {user: recipient, notification-type: notification-type}
                    (merge (unwrap-panic subscription) 
                           {delivery-count: (+ (get delivery-count (unwrap-panic subscription)) u1)}))
                (map-set notification-delivery-log
                    {user: recipient, notification-id: new-notification-id}
                    {attempts: u1,
                     last-attempt: stacks-block-height,
                     delivered: true,
                     method: "blockchain"})
                (ok new-notification-id))
            (ok u0))))

(define-public (mark-notification-as-read (notification-id uint))
    (let ((notification (map-get? user-notifications {user: tx-sender, notification-id: notification-id}))
          (user-counter (map-get? user-notification-counters tx-sender)))
        (asserts! (is-some notification) ERR-NOTIFICATION-NOT-FOUND)
        (asserts! (is-some user-counter) ERR-NOT-AUTHORIZED)
        (if (not (get read (unwrap-panic notification)))
            (begin
                (map-set user-notifications
                    {user: tx-sender, notification-id: notification-id}
                    (merge (unwrap-panic notification) {read: true}))
                (map-set user-notification-counters tx-sender
                    (merge (unwrap-panic user-counter) 
                           {unread-notifications: (- (get unread-notifications (unwrap-panic user-counter)) u1)}))
                (ok true))
            (ok true))))

(define-public (create-payment-due-alert (user principal))
    (let ((device-info (map-get? insured-devices user)))
        (if (is-some device-info)
            (let ((blocks-since-payment (- stacks-block-height (get last-payment (unwrap-panic device-info))))
                  (payment-due-blocks u4320) ;; ~30 days
                  (warning-blocks u720)) ;; 5 days before due
                (if (>= blocks-since-payment (- payment-due-blocks warning-blocks))
                    (create-notification user 
                        "Insurance premium payment is due within 5 days. Pay now to maintain coverage."
                        NOTIFICATION-TYPE-PAYMENT-DUE
                        PRIORITY-HIGH
                        (some "payment-due-5days"))
                    (ok u0)))
            (ok u0))))

(define-public (create-claim-status-alert (claim-owner principal) (status (string-ascii 20)))
    (let ((alert-message (if (is-eq status "approved")
                           "Excellent news! Your theft claim has been approved and will be processed soon."
                           (if (is-eq status "rejected")
                               "Your theft claim was not approved. Please review the decision details."
                               "Your theft claim status has been updated. Check your dashboard for details."))))
        (create-notification claim-owner
            alert-message
            NOTIFICATION-TYPE-CLAIM-UPDATE
            PRIORITY-HIGH
            (some status))))

(define-public (create-policy-expiry-alert (user principal))
    (create-notification user
        "Your insurance policy is expiring soon. Renew now to maintain continuous coverage."
        NOTIFICATION-TYPE-POLICY-EXPIRY
        PRIORITY-CRITICAL
        (some "policy-expiring")))

(define-public (create-system-maintenance-alert (user principal) (maintenance-info (string-ascii 128)))
    (create-notification user
        "Scheduled system maintenance will affect services. Please plan accordingly."
        NOTIFICATION-TYPE-SYSTEM-ALERT
        PRIORITY-MEDIUM
        (some maintenance-info)))

(define-public (batch-send-payment-reminders)
    ;; This function would iterate through users and send payment reminders
    ;; Simplified implementation for demonstration
    (ok u0))

;; Read-only functions for notifications
(define-read-only (get-user-notification-preferences (user principal))
    (ok (map-get? user-notification-preferences user)))

(define-read-only (get-notification-subscription (user principal) (notification-type (string-ascii 20)))
    (ok (map-get? notification-subscriptions {user: user, notification-type: notification-type})))

(define-read-only (get-user-notification (user principal) (notification-id uint))
    (ok (map-get? user-notifications {user: user, notification-id: notification-id})))

(define-read-only (get-user-notification-summary (user principal))
    (ok (map-get? user-notification-counters user)))

(define-read-only (get-unread-notification-count (user principal))
    (let ((counter (map-get? user-notification-counters user)))
        (match counter
            info (ok (get unread-notifications info))
            (ok u0))))

(define-read-only (check-notification-eligibility (user principal) (notification-type (string-ascii 20)))
    (let ((subscription (map-get? notification-subscriptions {user: user, notification-type: notification-type}))
          (preferences (map-get? user-notification-preferences user)))
        (ok {subscribed: (if (is-some subscription) (get subscribed (unwrap-panic subscription)) false),
             preferences-configured: (is-some preferences)})))

(define-read-only (get-notification-delivery-status (user principal) (notification-id uint))
    (ok (map-get? notification-delivery-log {user: user, notification-id: notification-id})))

;; ============================================================================
;; CORE READ-ONLY FUNCTIONS
;; ============================================================================

(define-read-only (get-device-info (owner principal))
    (ok (map-get? insured-devices owner)))

(define-read-only (get-claim-info (owner principal))
    (ok (map-get? theft-claims owner)))

(define-read-only (get-insurance-pool)
    (ok (var-get insurance-pool)))

(define-read-only (get-policy-status (user principal))
    (let ((device (map-get? insured-devices user)))
        (match device
            device-info
            (let ((blocks-since-payment (- stacks-block-height (get last-payment device-info)))
                  (payment-due-blocks u4320))
                (if (<= blocks-since-payment payment-due-blocks)
                    (ok {status: "active", blocks-overdue: u0})
                    (if (<= blocks-since-payment (+ payment-due-blocks (var-get grace-period-blocks)))
                        (ok {status: "grace-period", blocks-overdue: (- blocks-since-payment payment-due-blocks)})
                        (ok {status: "expired", blocks-overdue: (- blocks-since-payment payment-due-blocks)}))))
            (ok {status: "not-insured", blocks-overdue: u0}))))

(define-read-only (get-contract-info)
    (ok {
        total-pool: (var-get insurance-pool),
        monthly-premium: (var-get monthly-premium),
        claim-payout: (var-get claim-payout),
        vote-threshold: (var-get vote-threshold),
        grace-period-blocks: (var-get grace-period-blocks)
    }))
