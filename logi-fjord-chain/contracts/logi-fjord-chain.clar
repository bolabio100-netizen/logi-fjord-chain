;; LogiFjord Chain - Enterprise Shipping Verification Platform
;; Autonomous compliance oracles and predictive risk assessment for supply chain management

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-invalid-condition (err u105))
(define-constant err-compliance-failed (err u106))
(define-constant err-insufficient-funds (err u107))

;; Shipment status enumeration
(define-constant STATUS-REGISTERED u1)
(define-constant STATUS-IN-TRANSIT u2)
(define-constant STATUS-CUSTOMS u3)
(define-constant STATUS-DELIVERED u4)
(define-constant STATUS-DISPUTED u5)

;; Compliance levels
(define-constant COMPLIANCE-PENDING u0)
(define-constant COMPLIANCE-VERIFIED u1)
(define-constant COMPLIANCE-FAILED u2)

;; Data Variables
(define-data-var shipment-nonce uint u0)
(define-data-var total-shipments uint u0)
(define-data-var platform-fee-percentage uint u2) ;; 2% platform fee

;; Data Maps
(define-map shipments
    { shipment-id: uint }
    {
        shipper: principal,
        receiver: principal,
        carrier: principal,
        origin: (string-ascii 100),
        destination: (string-ascii 100),
        cargo-value: uint,
        insurance-amount: uint,
        status: uint,
        compliance-status: uint,
        registered-at: uint,
        delivered-at: uint,
        cargo-hash: (buff 32),
        is-active: bool
    }
)

(define-map shipment-tracking
    { shipment-id: uint, checkpoint-id: uint }
    {
        location: (string-ascii 100),
        gps-coordinates: (string-ascii 50),
        timestamp: uint,
        temperature: int,
        humidity: uint,
        handler-id: (string-ascii 50),
        rfid-signature: (buff 32),
        verified: bool
    }
)

(define-map shipment-checkpoints
    { shipment-id: uint }
    { checkpoint-count: uint }
)

(define-map compliance-records
    { shipment-id: uint }
    {
        regulatory-check: bool,
        cold-chain-integrity: bool,
        counterfeit-scan: bool,
        carbon-footprint: uint,
        conflict-minerals: bool,
        quality-deviation: bool,
        last-audit: uint
    }
)

(define-map payment-escrow
    { shipment-id: uint }
    {
        amount: uint,
        deposited: bool,
        released: bool,
        shipper-paid: bool,
        carrier-paid: bool
    }
)

(define-map authorized-carriers
    { carrier: principal }
    { authorized: bool, reputation-score: uint }
)

(define-map authorized-oracles
    { oracle: principal }
    { authorized: bool, oracle-type: (string-ascii 50) }
)

;; Read-only functions
(define-read-only (get-shipment (shipment-id uint))
    (map-get? shipments { shipment-id: shipment-id })
)

(define-read-only (get-tracking-data (shipment-id uint) (checkpoint-id uint))
    (map-get? shipment-tracking { shipment-id: shipment-id, checkpoint-id: checkpoint-id })
)

(define-read-only (get-checkpoint-count (shipment-id uint))
    (default-to { checkpoint-count: u0 }
        (map-get? shipment-checkpoints { shipment-id: shipment-id }))
)

(define-read-only (get-compliance-record (shipment-id uint))
    (map-get? compliance-records { shipment-id: shipment-id })
)

(define-read-only (get-payment-status (shipment-id uint))
    (map-get? payment-escrow { shipment-id: shipment-id })
)

(define-read-only (is-carrier-authorized (carrier principal))
    (default-to false
        (get authorized (map-get? authorized-carriers { carrier: carrier })))
)

(define-read-only (get-carrier-reputation (carrier principal))
    (default-to u0
        (get reputation-score (map-get? authorized-carriers { carrier: carrier })))
)

(define-read-only (get-total-shipments)
    (ok (var-get total-shipments))
)

;; Authorization functions
(define-public (authorize-carrier (carrier principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-carriers
            { carrier: carrier }
            { authorized: true, reputation-score: u100 }))
    )
)

(define-public (authorize-oracle (oracle principal) (oracle-type (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-oracles
            { oracle: oracle }
            { authorized: true, oracle-type: oracle-type }))
    )
)

(define-public (revoke-carrier (carrier principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok (map-set authorized-carriers
            { carrier: carrier }
            { authorized: false, reputation-score: u0 }))
    )
)

;; Core shipment functions
(define-public (register-shipment
    (receiver principal)
    (carrier principal)
    (origin (string-ascii 100))
    (destination (string-ascii 100))
    (cargo-value uint)
    (insurance-amount uint)
    (cargo-hash (buff 32)))
    (let
        (
            (shipment-id (+ (var-get shipment-nonce) u1))
        )
        (asserts! (is-carrier-authorized carrier) err-unauthorized)
        (asserts! (> cargo-value u0) err-invalid-condition)
        
        ;; Create shipment record
        (map-set shipments
            { shipment-id: shipment-id }
            {
                shipper: tx-sender,
                receiver: receiver,
                carrier: carrier,
                origin: origin,
                destination: destination,
                cargo-value: cargo-value,
                insurance-amount: insurance-amount,
                status: STATUS-REGISTERED,
                compliance-status: COMPLIANCE-PENDING,
                registered-at: block-height,
                delivered-at: u0,
                cargo-hash: cargo-hash,
                is-active: true
            }
        )
        
        ;; Initialize compliance record
        (map-set compliance-records
            { shipment-id: shipment-id }
            {
                regulatory-check: false,
                cold-chain-integrity: true,
                counterfeit-scan: false,
                carbon-footprint: u0,
                conflict-minerals: false,
                quality-deviation: false,
                last-audit: block-height
            }
        )
        
        ;; Initialize checkpoint counter
        (map-set shipment-checkpoints
            { shipment-id: shipment-id }
            { checkpoint-count: u0 }
        )
        
        ;; Initialize payment escrow
        (map-set payment-escrow
            { shipment-id: shipment-id }
            {
                amount: u0,
                deposited: false,
                released: false,
                shipper-paid: false,
                carrier-paid: false
            }
        )
        
        ;; Update counters
        (var-set shipment-nonce shipment-id)
        (var-set total-shipments (+ (var-get total-shipments) u1))
        
        (ok shipment-id)
    )
)

(define-public (add-tracking-checkpoint
    (shipment-id uint)
    (location (string-ascii 100))
    (gps-coordinates (string-ascii 50))
    (temperature int)
    (humidity uint)
    (handler-id (string-ascii 50))
    (rfid-signature (buff 32)))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
            (checkpoint-data (get-checkpoint-count shipment-id))
            (current-count (get checkpoint-count checkpoint-data))
            (new-checkpoint-id (+ current-count u1))
        )
        (asserts! (or 
            (is-eq tx-sender (get carrier shipment))
            (is-eq tx-sender contract-owner))
            err-unauthorized)
        (asserts! (get is-active shipment) err-invalid-status)
        
        ;; Add tracking checkpoint
        (map-set shipment-tracking
            { shipment-id: shipment-id, checkpoint-id: new-checkpoint-id }
            {
                location: location,
                gps-coordinates: gps-coordinates,
                timestamp: block-height,
                temperature: temperature,
                humidity: humidity,
                handler-id: handler-id,
                rfid-signature: rfid-signature,
                verified: true
            }
        )
        
        ;; Update checkpoint count
        (map-set shipment-checkpoints
            { shipment-id: shipment-id }
            { checkpoint-count: new-checkpoint-id }
        )
        
        (ok new-checkpoint-id)
    )
)

(define-public (update-shipment-status (shipment-id uint) (new-status uint))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
        )
        (asserts! (or 
            (is-eq tx-sender (get carrier shipment))
            (is-eq tx-sender contract-owner))
            err-unauthorized)
        (asserts! (get is-active shipment) err-invalid-status)
        (asserts! (<= new-status STATUS-DISPUTED) err-invalid-status)
        
        (ok (map-set shipments
            { shipment-id: shipment-id }
            (merge shipment { 
                status: new-status,
                delivered-at: (if (is-eq new-status STATUS-DELIVERED) 
                    block-height 
                    (get delivered-at shipment))
            })
        ))
    )
)

;; Compliance oracle functions
(define-public (update-compliance-check
    (shipment-id uint)
    (regulatory-check bool)
    (cold-chain-integrity bool)
    (counterfeit-scan bool)
    (conflict-minerals bool))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
            (compliance (unwrap! (get-compliance-record shipment-id) err-not-found))
        )
        (asserts! (default-to false 
            (get authorized (map-get? authorized-oracles { oracle: tx-sender })))
            err-unauthorized)
        
        (map-set compliance-records
            { shipment-id: shipment-id }
            (merge compliance {
                regulatory-check: regulatory-check,
                cold-chain-integrity: cold-chain-integrity,
                counterfeit-scan: counterfeit-scan,
                conflict-minerals: conflict-minerals,
                last-audit: block-height
            })
        )
        
        ;; Update shipment compliance status
        (let
            (
                (all-passed (and regulatory-check 
                    (and cold-chain-integrity 
                        (and counterfeit-scan (not conflict-minerals)))))
            )
            (map-set shipments
                { shipment-id: shipment-id }
                (merge shipment {
                    compliance-status: (if all-passed COMPLIANCE-VERIFIED COMPLIANCE-FAILED)
                })
            )
            (ok all-passed)
        )
    )
)

(define-public (update-carbon-footprint (shipment-id uint) (carbon-amount uint))
    (let
        (
            (compliance (unwrap! (get-compliance-record shipment-id) err-not-found))
        )
        (asserts! (default-to false 
            (get authorized (map-get? authorized-oracles { oracle: tx-sender })))
            err-unauthorized)
        
        (ok (map-set compliance-records
            { shipment-id: shipment-id }
            (merge compliance { carbon-footprint: carbon-amount })
        ))
    )
)

;; Payment and settlement functions
(define-public (deposit-payment (shipment-id uint) (amount uint))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
            (escrow (unwrap! (get-payment-status shipment-id) err-not-found))
        )
        (asserts! (is-eq tx-sender (get shipper shipment)) err-unauthorized)
        (asserts! (not (get deposited escrow)) err-already-exists)
        (asserts! (>= amount (get cargo-value shipment)) err-insufficient-funds)
        
        ;; Transfer STX to contract
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (ok (map-set payment-escrow
            { shipment-id: shipment-id }
            (merge escrow { amount: amount, deposited: true })
        ))
    )
)

(define-public (release-payment (shipment-id uint))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
            (escrow (unwrap! (get-payment-status shipment-id) err-not-found))
            (platform-fee (/ (* (get amount escrow) (var-get platform-fee-percentage)) u100))
            (carrier-payment (/ (get amount escrow) u2))
            (receiver-payment (- (- (get amount escrow) platform-fee) carrier-payment))
        )
        (asserts! (is-eq (get status shipment) STATUS-DELIVERED) err-invalid-status)
        (asserts! (is-eq (get compliance-status shipment) COMPLIANCE-VERIFIED) err-compliance-failed)
        (asserts! (get deposited escrow) err-not-found)
        (asserts! (not (get released escrow)) err-already-exists)
        
        ;; Transfer to receiver
        (try! (as-contract (stx-transfer? receiver-payment tx-sender (get receiver shipment))))
        
        ;; Transfer to carrier
        (try! (as-contract (stx-transfer? carrier-payment tx-sender (get carrier shipment))))
        
        ;; Transfer platform fee to contract owner
        (try! (as-contract (stx-transfer? platform-fee tx-sender contract-owner)))
        
        (ok (map-set payment-escrow
            { shipment-id: shipment-id }
            (merge escrow { 
                released: true,
                shipper-paid: true,
                carrier-paid: true
            })
        ))
    )
)

;; Administrative functions
(define-public (update-carrier-reputation (carrier principal) (new-score uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-score u100) err-invalid-condition)
        
        (ok (map-set authorized-carriers
            { carrier: carrier }
            (merge 
                (default-to { authorized: true, reputation-score: u100 }
                    (map-get? authorized-carriers { carrier: carrier }))
                { reputation-score: new-score }
            )
        ))
    )
)

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u10) err-invalid-condition) ;; Max 10% fee
        (ok (var-set platform-fee-percentage new-fee))
    )
)

(define-public (deactivate-shipment (shipment-id uint))
    (let
        (
            (shipment (unwrap! (get-shipment shipment-id) err-not-found))
        )
        (asserts! (or 
            (is-eq tx-sender (get shipper shipment))
            (is-eq tx-sender contract-owner))
            err-unauthorized)
        
        (ok (map-set shipments
            { shipment-id: shipment-id }
            (merge shipment { is-active: false })
        ))
    )
)