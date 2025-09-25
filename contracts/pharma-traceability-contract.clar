;; Pharmaceutical Traceability Contract
;; End-to-end pharmaceutical supply chain tracking with anti-counterfeiting and regulatory compliance

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u9001))
(define-constant ERR-NOT-FOUND (err u9002))
(define-constant ERR-ALREADY-EXISTS (err u9003))
(define-constant ERR-EXPIRED (err u9004))
(define-constant ERR-INVALID-STATUS (err u9005))
(define-constant ERR-INVALID-PARTICIPANT (err u9006))
(define-constant ERR-COUNTERFEIT-DETECTED (err u9007))
(define-constant ERR-RECALLED (err u9008))

;; Entity Types
(define-constant ENTITY-MANUFACTURER u1)
(define-constant ENTITY-DISTRIBUTOR u2)
(define-constant ENTITY-PHARMACY u3)
(define-constant ENTITY-HOSPITAL u4)
(define-constant ENTITY-REGULATOR u5)

;; Drug Status
(define-constant STATUS-MANUFACTURED u1)
(define-constant STATUS-QUALITY-TESTED u2)
(define-constant STATUS-SHIPPED u3)
(define-constant STATUS-DISTRIBUTED u4)
(define-constant STATUS-DISPENSED u5)
(define-constant STATUS-RECALLED u6)
(define-constant STATUS-EXPIRED u7)

;; Data Variables
(define-data-var next-drug-id uint u1)
(define-data-var next-batch-id uint u1)
(define-data-var next-transfer-id uint u1)
(define-data-var next-entity-id uint u1)
(define-data-var regulatory-authority principal tx-sender)
(define-data-var total-drugs-tracked uint u0)
(define-data-var total-counterfeits-detected uint u0)

;; Pharmaceutical Entities (Manufacturers, Distributors, Pharmacies, etc.)
(define-map entities
    { entity-id: uint }
    {
        owner: principal,
        entity-type: uint,
        name: (string-ascii 256),
        license-number: (string-ascii 128),
        registration-date: uint,
        is-verified: bool,
        compliance-score: uint,
        total-handled: uint
    }
)

;; Drug Registry
(define-map drugs
    { drug-id: uint }
    {
        manufacturer-id: uint,
        name: (string-ascii 256),
        ndc-code: (string-ascii 64), ;; National Drug Code
        active-ingredients: (string-ascii 512),
        dosage: (string-ascii 128),
        registration-date: uint,
        regulatory-approval: bool,
        total-batches: uint
    }
)

;; Drug Batches
(define-map drug-batches
    { batch-id: uint }
    {
        drug-id: uint,
        manufacturer-id: uint,
        batch-number: (string-ascii 64),
        manufacturing-date: uint,
        expiration-date: uint,
        quantity: uint,
        current-status: uint,
        current-custodian: uint,
        quality-verified: bool,
        is-recalled: bool,
        temperature-controlled: bool
    }
)

;; Custody Transfer Records
(define-map transfers
    { transfer-id: uint }
    {
        batch-id: uint,
        from-entity: uint,
        to-entity: uint,
        transfer-date: uint,
        location: (string-ascii 256),
        temperature-log: (string-ascii 128),
        verification-hash: (string-ascii 128),
        notes: (string-ascii 512)
    }
)

;; Authentication Records
(define-map authentications
    { batch-id: uint, verifier: principal }
    {
        verification-date: uint,
        is-authentic: bool,
        verification-method: (string-ascii 64),
        risk-score: uint
    }
)

;; Recall Records
(define-map recalls
    { batch-id: uint }
    {
        recall-date: uint,
        reason: (string-ascii 512),
        severity-level: uint,
        initiated-by: uint,
        affected-quantity: uint
    }
)

;; Compliance Checks
(define-map compliance-checks
    { entity-id: uint, check-id: uint }
    {
        check-date: uint,
        inspector: principal,
        compliance-status: bool,
        violations: (string-ascii 512),
        score: uint
    }
)

;; Quality Test Results
(define-map quality-tests
    { batch-id: uint, test-id: uint }
    {
        test-date: uint,
        test-type: (string-ascii 128),
        result: bool,
        lab-entity: uint,
        certificate-hash: (string-ascii 128)
    }
)

(define-data-var next-check-id uint u1)
(define-data-var next-test-id uint u1)

;; Public Functions

;; Register a pharmaceutical entity
(define-public (register-entity (entity-type uint) (name (string-ascii 256)) (license-number (string-ascii 128)))
    (let
        (
            (entity-id (var-get next-entity-id))
        )
        (asserts! (<= entity-type u5) ERR-INVALID-PARTICIPANT)
        (asserts! (> (len name) u0) ERR-NOT-FOUND)
        (asserts! (> (len license-number) u0) ERR-NOT-FOUND)
        
        ;; Register entity
        (map-set entities
            { entity-id: entity-id }
            {
                owner: tx-sender,
                entity-type: entity-type,
                name: name,
                license-number: license-number,
                registration-date: block-height,
                is-verified: false,
                compliance-score: u100,
                total-handled: u0
            }
        )
        
        ;; Increment counter
        (var-set next-entity-id (+ entity-id u1))
        
        (ok entity-id)
    )
)

;; Register a new pharmaceutical drug
(define-public (register-drug (manufacturer-id uint) (name (string-ascii 256)) (ndc-code (string-ascii 64)) (active-ingredients (string-ascii 512)) (dosage (string-ascii 128)))
    (let
        (
            (drug-id (var-get next-drug-id))
            (manufacturer (unwrap! (map-get? entities { entity-id: manufacturer-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get owner manufacturer)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get entity-type manufacturer) ENTITY-MANUFACTURER) ERR-INVALID-PARTICIPANT)
        (asserts! (get is-verified manufacturer) ERR-NOT-AUTHORIZED)
        
        ;; Register drug
        (map-set drugs
            { drug-id: drug-id }
            {
                manufacturer-id: manufacturer-id,
                name: name,
                ndc-code: ndc-code,
                active-ingredients: active-ingredients,
                dosage: dosage,
                registration-date: block-height,
                regulatory-approval: false,
                total-batches: u0
            }
        )
        
        ;; Increment counter
        (var-set next-drug-id (+ drug-id u1))
        
        (ok drug-id)
    )
)

;; Create a new drug batch
(define-public (create-batch (drug-id uint) (batch-number (string-ascii 64)) (quantity uint) (expiration-date uint) (temperature-controlled bool))
    (let
        (
            (batch-id (var-get next-batch-id))
            (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-NOT-FOUND))
            (manufacturer (unwrap! (map-get? entities { entity-id: (get manufacturer-id drug-data) }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (get owner manufacturer)) ERR-NOT-AUTHORIZED)
        (asserts! (get regulatory-approval drug-data) ERR-NOT-AUTHORIZED)
        (asserts! (> quantity u0) ERR-NOT-FOUND)
        (asserts! (> expiration-date block-height) ERR-EXPIRED)
        
        ;; Create batch
        (map-set drug-batches
            { batch-id: batch-id }
            {
                drug-id: drug-id,
                manufacturer-id: (get manufacturer-id drug-data),
                batch-number: batch-number,
                manufacturing-date: block-height,
                expiration-date: expiration-date,
                quantity: quantity,
                current-status: STATUS-MANUFACTURED,
                current-custodian: (get manufacturer-id drug-data),
                quality-verified: false,
                is-recalled: false,
                temperature-controlled: temperature-controlled
            }
        )
        
        ;; Update drug stats
        (map-set drugs
            { drug-id: drug-id }
            (merge drug-data { total-batches: (+ (get total-batches drug-data) u1) })
        )
        
        ;; Update global stats
        (var-set next-batch-id (+ batch-id u1))
        (var-set total-drugs-tracked (+ (var-get total-drugs-tracked) quantity))
        
        (ok batch-id)
    )
)

;; Transfer custody of a drug batch
(define-public (transfer-custody (batch-id uint) (to-entity-id uint) (location (string-ascii 256)) (temperature-log (string-ascii 128)) (verification-hash (string-ascii 128)))
    (let
        (
            (batch-data (unwrap! (map-get? drug-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (from-entity (unwrap! (map-get? entities { entity-id: (get current-custodian batch-data) }) ERR-NOT-FOUND))
            (to-entity (unwrap! (map-get? entities { entity-id: to-entity-id }) ERR-NOT-FOUND))
            (transfer-id (var-get next-transfer-id))
        )
        (asserts! (is-eq tx-sender (get owner from-entity)) ERR-NOT-AUTHORIZED)
        (asserts! (get is-verified to-entity) ERR-INVALID-PARTICIPANT)
        (asserts! (not (get is-recalled batch-data)) ERR-RECALLED)
        (asserts! (<= block-height (get expiration-date batch-data)) ERR-EXPIRED)
        
        ;; Create transfer record
        (map-set transfers
            { transfer-id: transfer-id }
            {
                batch-id: batch-id,
                from-entity: (get current-custodian batch-data),
                to-entity: to-entity-id,
                transfer-date: block-height,
                location: location,
                temperature-log: temperature-log,
                verification-hash: verification-hash,
                notes: ""
            }
        )
        
        ;; Update batch custody
        (map-set drug-batches
            { batch-id: batch-id }
            (merge batch-data {
                current-custodian: to-entity-id,
                current-status: (if (is-eq (get entity-type to-entity) ENTITY-DISTRIBUTOR) STATUS-DISTRIBUTED
                                (if (is-eq (get entity-type to-entity) ENTITY-PHARMACY) STATUS-DISPENSED
                                STATUS-SHIPPED))
            })
        )
        
        ;; Update entity stats
        (map-set entities
            { entity-id: to-entity-id }
            (merge to-entity { total-handled: (+ (get total-handled to-entity) u1) })
        )
        
        ;; Increment counter
        (var-set next-transfer-id (+ transfer-id u1))
        
        (ok transfer-id)
    )
)

;; Verify drug authenticity
(define-public (verify-drug (batch-id uint) (verification-method (string-ascii 64)))
    (let
        (
            (batch-data (unwrap! (map-get? drug-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (risk-score (if (get quality-verified batch-data) u10
                        (if (> block-height (get expiration-date batch-data)) u90 u30)))
        )
        (asserts! (not (get is-recalled batch-data)) ERR-RECALLED)
        
        ;; Record verification
        (map-set authentications
            { batch-id: batch-id, verifier: tx-sender }
            {
                verification-date: block-height,
                is-authentic: (and (get quality-verified batch-data)
                                 (<= block-height (get expiration-date batch-data))
                                 (not (get is-recalled batch-data))),
                verification-method: verification-method,
                risk-score: risk-score
            }
        )
        
        (ok { authentic: (< risk-score u50), risk-score: risk-score })
    )
)

;; Record quality test results
(define-public (record-quality-test (batch-id uint) (test-type (string-ascii 128)) (result bool) (lab-entity-id uint) (certificate-hash (string-ascii 128)))
    (let
        (
            (batch-data (unwrap! (map-get? drug-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (lab-entity (unwrap! (map-get? entities { entity-id: lab-entity-id }) ERR-NOT-FOUND))
            (test-id (var-get next-test-id))
        )
        (asserts! (is-eq tx-sender (get owner lab-entity)) ERR-NOT-AUTHORIZED)
        (asserts! (get is-verified lab-entity) ERR-INVALID-PARTICIPANT)
        
        ;; Record test
        (map-set quality-tests
            { batch-id: batch-id, test-id: test-id }
            {
                test-date: block-height,
                test-type: test-type,
                result: result,
                lab-entity: lab-entity-id,
                certificate-hash: certificate-hash
            }
        )
        
        ;; Update batch quality status if test passed
        (if result
            (map-set drug-batches
                { batch-id: batch-id }
                (merge batch-data {
                    quality-verified: true,
                    current-status: STATUS-QUALITY-TESTED
                }))
            false
        )
        
        ;; Increment counter
        (var-set next-test-id (+ test-id u1))
        
        (ok test-id)
    )
)

;; Initiate drug recall
(define-public (initiate-recall (batch-id uint) (reason (string-ascii 512)) (severity-level uint))
    (let
        (
            (batch-data (unwrap! (map-get? drug-batches { batch-id: batch-id }) ERR-NOT-FOUND))
            (manufacturer (unwrap! (map-get? entities { entity-id: (get manufacturer-id batch-data) }) ERR-NOT-FOUND))
        )
        (asserts! (or (is-eq tx-sender (var-get regulatory-authority))
                      (is-eq tx-sender (get owner manufacturer))) ERR-NOT-AUTHORIZED)
        (asserts! (<= severity-level u5) ERR-NOT-FOUND)
        
        ;; Record recall
        (map-set recalls
            { batch-id: batch-id }
            {
                recall-date: block-height,
                reason: reason,
                severity-level: severity-level,
                initiated-by: (if (is-eq tx-sender (var-get regulatory-authority)) u0 (get manufacturer-id batch-data)),
                affected-quantity: (get quantity batch-data)
            }
        )
        
        ;; Update batch status
        (map-set drug-batches
            { batch-id: batch-id }
            (merge batch-data {
                is-recalled: true,
                current-status: STATUS-RECALLED
            })
        )
        
        (ok true)
    )
)

;; Verify entity (regulatory authority only)
(define-public (verify-entity (entity-id uint))
    (let
        (
            (entity-data (unwrap! (map-get? entities { entity-id: entity-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get regulatory-authority)) ERR-NOT-AUTHORIZED)
        
        ;; Verify entity
        (map-set entities
            { entity-id: entity-id }
            (merge entity-data { is-verified: true })
        )
        
        (ok true)
    )
)

;; Approve drug for market (regulatory authority only)
(define-public (approve-drug (drug-id uint))
    (let
        (
            (drug-data (unwrap! (map-get? drugs { drug-id: drug-id }) ERR-NOT-FOUND))
        )
        (asserts! (is-eq tx-sender (var-get regulatory-authority)) ERR-NOT-AUTHORIZED)
        
        ;; Approve drug
        (map-set drugs
            { drug-id: drug-id }
            (merge drug-data { regulatory-approval: true })
        )
        
        (ok true)
    )
)

;; Read-only functions

;; Get entity information
(define-read-only (get-entity (entity-id uint))
    (map-get? entities { entity-id: entity-id })
)

;; Get drug information
(define-read-only (get-drug (drug-id uint))
    (map-get? drugs { drug-id: drug-id })
)

;; Get batch information
(define-read-only (get-batch (batch-id uint))
    (map-get? drug-batches { batch-id: batch-id })
)

;; Get transfer information
(define-read-only (get-transfer (transfer-id uint))
    (map-get? transfers { transfer-id: transfer-id })
)

;; Get authentication record
(define-read-only (get-authentication (batch-id uint) (verifier principal))
    (map-get? authentications { batch-id: batch-id, verifier: verifier })
)

;; Get recall information
(define-read-only (get-recall (batch-id uint))
    (map-get? recalls { batch-id: batch-id })
)

;; Get quality test results
(define-read-only (get-quality-test (batch-id uint) (test-id uint))
    (map-get? quality-tests { batch-id: batch-id, test-id: test-id })
)

;; Check if batch is authentic and safe
(define-read-only (is-batch-safe (batch-id uint))
    (match (map-get? drug-batches { batch-id: batch-id })
        batch-data (and (get quality-verified batch-data)
                       (<= block-height (get expiration-date batch-data))
                       (not (get is-recalled batch-data)))
        false
    )
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-entities: (- (var-get next-entity-id) u1),
        total-drugs: (- (var-get next-drug-id) u1),
        total-batches: (- (var-get next-batch-id) u1),
        total-transfers: (- (var-get next-transfer-id) u1),
        total-drugs-tracked: (var-get total-drugs-tracked),
        counterfeits-detected: (var-get total-counterfeits-detected)
    }
)

;; Get batch supply chain history
(define-read-only (get-batch-chain (batch-id uint))
    (map-get? drug-batches { batch-id: batch-id })
)
