;
; connector-vec.scm
;
; Representing connector-words as vectors.
;
; Copyright (c) 2018 Linas Vepstas
;
; ---------------------------------------------------------------------
; OVERVIEW
; --------
; This file provide the "matrix-object" API that allows words to be
; treated as vectors, with the word taken to live in a connector, and
; the vector basis ranging over all sections (that contain that word in
; a connector).
;
; A key idea in grammatical classification is that words can be treated
; as vectors, and thus, vector-style algorithms can be applied to them.
; There are many kinds of vectors that are possible:
; -- N-grams, where a word is associated with a vector of counts of
;    the neighboring N words.
; -- skip-grams, as above, but some words are skipped.
; Neither of the above are implemented anywhere in this directory, but
; they convey the idea of a word-vector.
;
; Another vector is a word-disjunct vector, where the word is associated
; with a vector of counts of how often a disjunct is associated with it.
; This is implemented in `pseudo-csets.scm`.  Its a good place to start.
; The word-disjunct vectors behave a whole lot like skip-grams, for many
; practical purposes.
;
; The vector *IN THIS FILE* is between a word living in a connector,
; and all sections that contain that connector. This allows one to look
; at how contexts cross over to other linked words.  It is looking at
; disjuncts from the connector point of view.
;
; Consider, for example, the word "level". It can appear in a connector
; both as
;
;    (Connector (WordNode "level") (LgConnDirNode "-"))
;
; and as
;
;    (Connector (WordNode "level") (LgConnDirNode "+"))
;
; One of these connectors appears in the section
;
;    (Section
;       (WordNode "playing")
;       (ConnectorSeq
;          (Connector
;             (WordNode "level")
;             (ConnectorDir "-"))
;          (Connector
;             (WordNode "field")
;             (ConnectorDir "+"))))
;
; and therefore, this section is paired with (WordNode "level")
;
; Left wild-cards
; ---------------
; In the above example, the corresponding left-wildcard for "level"
; would be (concpetually)
;
;    (Section
;       (WordNode "playing")
;       (ConnectorSeq
;          (Connector
;             (Variable "$wildcard")
;             (ConnectorDir "-"))
;          (Connector
;             (WordNode "field")
;             (ConnectorDir "+"))))
;
; I.e. with (Variable "$wildcard") replacing (WordNode "level")
; These wildcards are needed to store the left-marginals.  In practice,
; we don't want to pullute the namespace with ConnectorSeq's and
; Sections that have variables in them, so the actual representation is
; flattened.
;
; ---------------------------------------------------------------------
;
(use-modules (srfi srfi-1))
(use-modules (opencog))
(use-modules (opencog persist))
(use-modules (opencog matrix))

; ---------------------------------------------------------------------
; ---------------------------------------------------------------------
;
(define-public (make-connector-vec-api)
"
  make-connector-vec-api -- API for cross-section word-pairs.

  Due to the unusual nature of the structures that this is covering,
  this provides it's own pair-stars API.

  A more detailed description is at the top of this file.
"
	(let ((l-basis '())
			(r-basis '())
			(l-size 0)
			(r-size 0)

			; Temporary atomspace
			(mtx (make-mutex))
			(aspace (cog-new-atomspace (cog-atomspace)))
		)

		(define star-wild (Variable "$connector-word"))
		(define predno (Predicate "*-connector left stars-*"))

		(define any-left (AnyNode "cross-connector word"))
		(define any-right (AnyNode "cross-connector section"))

		(define (get-left-type) 'WordNode)
		(define (get-right-type) 'EvaluationLink)
		(define (get-pair-type) 'Section)

		; Get the observational count on Section SECT
		(define (get-count SECT) (cog-tv-count (cog-tv SECT)))

		; L-ATOM is a WordNode. R-ATOM is a wild-card.
		; Disassemble the R-ATOM, insert L-ATOM into the variable
		; location, and return the atom, if it exists.
		(define (get-pair L-ATOM R-ATOM)
			(define tmpl (cog-outgoing-set (gdr R-ATOM)))
			(define point (car tmpl))
			(define conseq (cdr tmpl))
			(define (not-var? ITEM) (not (equal? ITEM star-wild)))
			(define begin (take-while not-var? conseq))
			(define rest (drop-while not-var? conseq))
			(define dir (gdr (car rest)))
			(define end (cdr rest))
			(define ctcr (cog-link 'Connector L-ATOM dir))
			(if (null? ctcr) '()
				(let ((conseq (cog-link 'ConnectorSeq begin ctcr end)))
					(if (null? conseq) '()
						(cog-link 'Section point conseq)))))

		; Same as above, but actually create the thing.
		(define (make-pair L-ATOM R-ATOM)
			(define tmpl (cog-outgoing-set (gdr R-ATOM)))
			(define point (car tmpl))
			(define conseq (cdr tmpl))
			(define (not-var? ITEM) (not (equal? ITEM star-wild)))
			(define begin (take-while not-var? conseq))
			(define rest (drop-while not-var? conseq))
			(define dir (gdr (car rest)))
			(define end (cdr rest))
			(Section point (ConnectorSeq
				begin (Connector L-ATOM dir) end)))

		; Return the Word or WordClass of the Section
		; This is wrong.... There's not enough information to
		; know what this is ...
		(define (get-left-element PAIR) '())

		(define (get-right-element PAIR) '())

		; Get the count, if the pair exists.
		(define (get-pair-count L-ATOM R-ATOM)
			(define sect (get-pair L-ATOM R-ATOM))
			(if (null? sect) 0 (get-count sect)))

		; Use ListLinks for the wild-cards.
		(define (get-right-wildcard WORD)
			(ListLink WORD any-right))

		; The only reasonable left-wildcard that I can think of is
		; aready the wildcard. So this is a no-op.
		(define (get-left-wildcard R-ATOM) R-ATOM)

		(define (get-wild-wild)
			(ListLink any-left any-right))

		; Fetch (from the database) all sections,
		; as well as all the marginals.
		(define (fetch-sections)
			(define start-time (current-time))
			; marginals are located on any-left, any-right
			(fetch-incoming-set any-left)
			(fetch-incoming-set any-right)
			(load-atoms-of-type 'Section)
			(format #t "Elapsed time to load word sections: ~A seconds\n"
				(- (current-time) start-time)))
			(set! start-time (current-time))
			(fetch-incoming-set predno)
			(format #t "Elapsed time to load cross-marginals: ~A seconds\n"
				(- (current-time) start-time)))

		; -------------------------------------------------------
		; Stars API.
		(define (get-left-basis)
			(if (null? l-basis) (set! l-basis (cog-get-atoms 'WordNode)))
			l-basis)

		(define (get-right-basis)
			(if (null? r-basis) (set! r-basis (cog-incoming-set predno)))
			r-basis)

		(define (get-left-size)
			(if (eq? 0 l-size) (set! l-size (length (get-left-basis))))
			l-size)

		(define (get-right-size)
			(if (eq? 0 r-size) (set! r-size (length (get-right-basis))))
			r-size)

		; -------------------------------------------------------
		; Create all of the atoms that correspond to the left-stars
		; for the cross-connector. These are needed to hold marginal
		; counts; left-marginals cannot be computed without these.
		;
		; Conceptually, these are of the form:
		; (Section (Word "foo") (ConnectorSeq
		;     (Connector (Word "bar") (ConnectorDir "-))
		;     (Connector (Variable $X) (ConnectorDir "-))))
		; where (Variable $X) is the wildcard.  However, we want to
		; avoid using both ConnectorSeq and Section directly, because
		; these pollute the space of data. So, the above gets encoded
		; as
		; (Evaluation (Predicate "stars") (List (Word "foo")
		;     (Connector (Word "bar") (ConnectorDir "-))
		;     (Connector (Variable $X) (ConnectorDir "-))))
		; with the left-word "foo" heading up the list.
		; This can be easily dis-assembled to run actual queries against
		; the atomspace.
		(define (create-connector-left-stars)

			(define start-time (current-time))

			; Walk over a section, and insert a wild-card.
			(define (create-wilds-for-section SEC)
				; The root-point of the seed
				(define point (gar SEC))
				; The list of connectors
				(define cncts (cog-outgoing-set (gdr SEC)))
				(define num-cncts (length cncts))

				; Place the wild-card into the N'th location of the section.
				; Of course, this creates the section, if it does not yet
				; exist. Well, we don't want to crete actual sections; that
				; would screw up other code that expects sections to not
				; have wildcards in them.
				(define (insert-wild N)
					(define back (drop cncts N))
					(define dir (gdr (car back)))
					(Evaluation predno
						(List point
							(take cncts N) (Connector star-wild dir) (cdr back))))

				; Create all the wild-cards for this section.
				(map insert-wild (list-tabulate num-cncts values))
			)

			(for-each create-wilds-for-section (cog-get-atoms 'Section))
			(format #t "Elapsed time to compute left-stars: ~A secs\n"
				(- (current-time) start-time))
		)

		; -------------------------------------------------------
		; The right-stars of a WordNode are all of the Sections in
		; which that Word appears in some Connector. A BindLink is
		; used to get those sections. This is done in a private,
		; temporary atomspace, to avoid polluting the main atomspace
		; with junk. Its also done RAII style, so that ctrl-C does
		; not leave things in a fumbled state.
		;
		; Run a query, and return all Sections that contain WORD
		; in a Connector, some Connector, any Connector.
		(define (do-get-right-stars WORD)
			; The WORD must occur somewhere, anywhere in a conector.
			(define body (Section
				(Variable "$point")
				(ConnectorSeq
					(Glob "$begin")
					(Connector WORD (Variable "$dir"))
					(Glob "$end"))))

			; The types that are matched must be just-so.
			(define pattern
				(Bind (VariableList
					(TypedVariable (Variable "$point") (Type "WordNode"))
					(TypedVariable (Variable "$dir") (Type "ConnectorDir"))
					(TypedVariable (Glob "$begin") (Interval (Number 0) (Number -1)))
					(TypedVariable (Glob "$end") (Interval (Number 0) (Number -1))))
					body body))

			; execute returns a SetLink. We don't want that.
			(define setlnk (cog-execute! pattern))
			(cog-outgoing-set setlnk)
		)

		; Use RAII-style code, so that if the user hits ctrl-C
		; while we are in this, we will catch that and set the
		; atomspace back to normal.
		; XXX there is a small race here, between the setting
		; of the atomspace, and the invocation of the
		; throw-handler, but I don't care.
		;
		(define (raii-get-right-stars WORD)
			(define old-as (cog-set-atomspace! aspace))
			(with-throw-handler #t
				(lambda ()
					(let ((stars (do-get-right-stars WORD)))
						(cog-atomspace-clear aspace)
						(cog-set-atomspace! old-as)
						stars))
				(lambda (key . args)
					(cog-atomspace-clear aspace)
					(cog-set-atomspace! old-as)
					'())))

		; Return all sections that have WORD appearing in a connector.
		; This is a wrapper to seriealize access to a temp atomspace,
		; where the query is actually performed.
		(define (get-right-stars WORD)
			(lock-mutex mtx)
			(with-throw-handler #t
				(lambda ()
					(define stars (raii-get-right-stars WORD))
					(unlock-mutex mtx)
					stars)
				(lambda (key . args)
					(unlock-mutex mtx)
					'())))

		; Left-stars are much much simpler. These are just the list
		; of words appearing in the section.
		(define (get-left-stars SECT)
			(map gar (cog-outgoing-set (gdr SECT)))
		)

		;-------------------------------------------
		; Explain the non-default provided methods.
		(define (provides meth)
			(case meth
				((left-basis)       get-left-basis)
				((right-basis)      get-right-basis)
				((left-basis-size)  get-left-size)
				((right-basis-size) get-right-size)
				((left-stars)       get-left-stars)
				((right-stars)      get-right-stars)
		))

		; Methods on the object
		(lambda (message . args)
			(apply (case message
				((name)       (lambda () "Cross-section Words"))
				((id)         (lambda () "cross-section"))
				((left-type)        get-left-type)
				((right-type)       get-right-type)
				((pair-type)        get-pair-type)
				((pair-count)       get-pair-count)
				((get-pair)         get-pair)
				((get-count)        get-count)
				((make-pair)        make-pair)
				((left-element)     get-left-element)
				((right-element)    get-right-element)
				((left-wildcard)    get-left-wildcard)
				((right-wildcard)   get-right-wildcard)
				((wild-wild)        get-wild-wild)
				((fetch-pairs)      fetch-sections)

				((left-basis)       get-left-basis)
				((right-basis)      get-right-basis)
				((left-basis-size)  get-left-size)
				((right-basis-size) get-right-size)
				((left-stars)       get-left-stars)
				((right-stars)      get-right-stars)

				((make-left-stars)  create-connector-left-stars)

				((provides)         provides)
				((filters?)         (lambda () #f))
				(else (error "Bad method call on cross-section:" message)))
			args)))
)

; ---------------------------------------------------------------------
; Example usage:
;
; (define cva (make-connector-vec-api))
; (cva 'fetch-pairs)
; (define cvs (add-pair-stars cva))
; (cvs 'left-basis-size)
;
; (cvs 'right-stars (Word "wiped"))
; (cvs 'right-stars (Word "ride"))
