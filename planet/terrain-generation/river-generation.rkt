#lang typed/racket

(require vraid/flow
         vraid/sorted-tree
         "../grid-base.rkt"
         "../terrain.rkt")

(provide planet/rivers)

(define-type corner-node (Pair Integer Float))

(: ref (All (A) ((Vectorof A) -> (Integer -> A))))
(define ((ref v) n)
  (vector-ref v n))

(: set-directions/floodfill! (planet-terrain -> Void))
(define (set-directions/floodfill! planet)
  (let: ([tree : (sorted-tree corner-node) (make-sorted-tree
                                            (λ ([a : corner-node]
                                                [b : corner-node])
                                              (<= (cdr a) (cdr b))))])
    (let* ([start (argmin (curry tile-elevation planet)
                          (range (tile-count planet)))]
           [tile-visited : (Vectorof Boolean) (make-vector (tile-count planet) #f)]
           [tile-visited? (ref tile-visited)]
           [tile-visit! (λ ([n : Integer])
                          (vector-set! tile-visited n #t))]
           [corner-visited : (Vectorof Boolean) (make-vector (corner-count planet) #f)]
           [corner-visited? (ref corner-visited)]
           [corner-visit! (λ ([n : Integer])
                            (vector-set! corner-visited n #t))]
           [coast : (Vectorof Boolean) (make-vector (tile-count planet) #f)]
           [coast? (ref coast)]
           [set-coast! (λ ([n : Integer])
                         (vector-set! coast n #t))]
           [check-tile-elevation (λ ([n : Integer]
                                     [elevation : Float])
                                   (when (and (not (tile-visited? n))
                                              (< (tile-elevation planet n)
                                                 elevation))
                                     ((tile-terrain-data-elevation-set! (planet-terrain-tile planet)) n elevation)))]
           [check-corner-elevation (λ ([n : Integer]
                                       [elevation : Float])
                                     (when (< (corner-elevation planet n)
                                              elevation)
                                       ((corner-terrain-data-elevation-set! (planet-terrain-corner planet)) n (* 1.001 elevation))))]
           [visit/add! (λ ([n : Integer])
                         (let ([elevation (corner-elevation planet n)])
                           (for ([k (grid-corner-corner-list planet n)])
                             (unless (corner-visited? k)
                               (corner-visit! k)
                               (let ([prev-elevation (corner-elevation planet k)])
                                 (check-corner-elevation k elevation)
                                 ((corner-terrain-data-river-direction-set! (planet-terrain-corner planet)) k (grid-corner-corner-position planet k n))
                                 (let ([new-elevation (corner-elevation planet k)])
                                   (sorted-tree-add! tree (cons k prev-elevation))
                                   (for ([t (grid-corner-tile-list planet k)])
                                     (check-tile-elevation t new-elevation))))))))])
      (letrec ([recuvisit : (Integer -> Void)
                          (λ (n)
                            (when (tile-water? planet n)
                              (unless (tile-visited? n)
                                (tile-visit! n)
                                (begin
                                  (for ([k (grid-tile-corner-list planet n)])
                                    (unless (corner-visited? k)
                                      (when (corner-coast? planet k)
                                        ((corner-terrain-data-elevation-set! (planet-terrain-corner planet)) k (planet-sea-level planet))
                                        (sorted-tree-add! tree (cons k (corner-elevation planet k))))
                                      (corner-visit! k)))
                                  (for ([k (grid-tile-tile-list planet n)])
                                    (recuvisit k))))))]
               [make-next : (-> False)
                          (thunk
                           (and-let* ([val (sorted-tree-take-first! tree)]
                                      [n (car val)])
                                     (begin
                                       (visit/add! n)
                                       (make-next))))])
        (recuvisit start)
        (make-next)
        (void)))))

(: river-trees (planet-terrain -> river-list))
(define (river-trees planet)
  (: corner-node (Integer -> river))
  (define (corner-node n)
    (river n (map corner-node
                  (corner-river-sources planet n))))
  (foldl (λ ([n : Integer]
             [ls : river-list])
           (if (corner-coast? planet n)
               (cons (corner-node n) ls)
               ls))
         '()
         (range (corner-count planet))))

(: planet/rivers (planet-terrain -> planet-terrain))
(define (planet/rivers p)
  (let* ([tiles ((build-tile-terrain-data (tile-count p))
                 #:elevation (curry tile-elevation p)
                 #:water-level (curry tile-water-level p))]
         [corners ((build-corner-terrain-data (corner-count p))
                   #:elevation (curry corner-elevation p)
                   #:river-direction (curry corner-river-direction p))]
         [p (planet-terrain/kw
             #:planet-geometry p
             #:sea-level (planet-sea-level p)
             #:tile tiles
             #:corner corners
             #:rivers '())])
    (set-directions/floodfill! p)
    (struct-copy planet-terrain p
                 [rivers (river-trees p)])))
