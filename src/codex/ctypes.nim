import sigil

type
  # A collection of verses and the information needed to execute them
  Codex*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    verses*: seq[Verse[G, A]]
    # A collection of verse indexes to be executed in order
    # TODO: Maybe throw that idea away? May be overkill
    spine*: seq[VerseIdx]
    strPool*: seq[string]
    atomPool*: seq[seq[A]]
    setPool*: seq[set[A]]
    rulePool*: seq[RuleDef]
    actPool*: seq[ActProc[C, G, A, L]]

  VerseKind* = enum
    vkSeq                        # A block of steps
    vkChoice                     # A fork (Try/Else)
    vkLoop                       # A repetition
    vkCall                       # A subroutine call
    vkSiphon                     # Siphon matched atoms into a channel
    vkAct                     # Act on matched atoms in a channel after
    vkErrorLabel                 # An error label
    vkLookahead                  # Executes verse but then rewinds cursor
    vkCheckMatch, vkCheckNoMatch # A terminal match
    vkCommit                     # Commit to this branch, YOLO

  CheckKind* = enum
    ckAtom, ckSet, ckSeqAtom, ckAny

  # A single executable instruction
  Verse*[G: Ordinal, A: Atom] = object
    case kind*: VerseKind
    of vkSeq:
      spineStart*: SpineIdx
      spineLen*: int

    of vkChoice:
      tryVerse*: VerseIdx
      elseVerse*: VerseIdx

    of vkLoop: bodyVerse*: VerseIdx
    of vkCall: ruleIdx*: RuleIdx

    of vkSiphon:
      siphonBody*: VerseIdx
      channelIdx*: G

    of vkAct:
      actBody*: VerseIdx
      actIdx*: ActIdx
    
    of vkErrorLabel:
      labelledVerseIdx*: VerseIdx
      labelStrIdx*: StrPoolIdx

    of vkLookahead:
      lookaheadVerse*: VerseIdx
      invert*: bool # Toggle to fail on success

    of vkCheckMatch, vkCheckNoMatch:
      case checkType*: CheckKind
      of ckAtom: valAtom*: A
      of ckSeqAtom: atomPoolIdx*: AtomPoolIdx
      of ckSet: setPoolIdx*: SetPoolIdx
      of ckAny: discard
    
    of vkCommit:
      commitBody*: VerseIdx

  RuleDef* = object
    name*: string
    entry*: VerseIdx

  VerseIdx* = distinct int
  SpineIdx* = distinct int
  StrPoolIdx* = distinct int
  AtomPoolIdx* = distinct int
  SetPoolIdx* = distinct int
  ActIdx* = distinct int
  RuleIdx* = distinct int

# Neat utility
func getOrAdd[T](
  pool: var seq[T],
  val: T
): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high

# Basic helpers
func `==`*(a, b: VerseIdx): bool {.borrow.}
func `==`*(a, b: SpineIdx): bool {.borrow.}
func `==`*(a, b: StrPoolIdx): bool {.borrow.}
func `==`*(a, b: AtomPoolIdx): bool {.borrow.}
func `==`*(a, b: SetPoolIdx): bool {.borrow.}
func `==`*(a, b: RuleIdx): bool {.borrow.}
func `==`*(a, b: ActIdx): bool {.borrow.}
func `==`*(a, b: Verse): bool =
  if a.kind != b.kind: return false
  case a.kind
  of vkSeq:
    a.spineStart == b.spineStart and a.spineLen == b.spineLen
  of vkChoice:
    a.tryVerse == b.tryVerse and a.elseVerse == b.elseVerse
  of vkLoop:
    a.bodyVerse == b.bodyVerse
  of vkCall:
    a.ruleIdx == b.ruleIdx
  of vkSiphon:
    a.siphonBody == b.siphonBody and a.channelIdx == b.channelIdx
  of vkAct:
    a.actBody == b.actBody and a.actIdx == b.actIdx
  of vkErrorLabel:
    a.labelledVerseIdx == b.labelledVerseIdx and a.labelStrIdx == b.labelStrIdx
  of vkLookahead:
    a.lookaheadVerse == b.lookaheadVerse and a.invert == b.invert
  of vkCheckMatch, vkCheckNoMatch:
    if a.checkType != b.checkType: false
    else:
      case a.checkType
      of ckAtom:
        a.valAtom == b.valAtom
      of ckSeqAtom:
        a.atomPoolIdx == b.atomPoolIdx
      of ckSet:
        a.setPoolIdx == b.setPoolIdx
      of ckAny:
        true
  of vkCommit:
    a.commitBody == b.commitBody

func `$`*(a: VerseIdx): string = "v@" & $int(a)
func `$`*(a: SpineIdx): string = "s@" & $int(a)
func `$`*(a: StrPoolIdx): string = "pstr@" & $int(a)
func `$`*(a: AtomPoolIdx): string = "patom@" & $int(a)
func `$`*(a: SetPoolIdx): string = "pset@" & $int(a)
func `$`*(a: ActIdx): string = "a@" & $int(a)
func `$`*(a: RuleIdx): string = "r@" & $int(a)

func succ*(x: SpineIdx, y = 1): SpineIdx = SpineIdx(succ(x.int, y))

func `[]`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: Codex[C, G, A, L],
  idx: VerseIdx
): Verse[G, A] = c.verses[idx.int]
func `[]`*(c: Codex, idx: SpineIdx): VerseIdx = c.spine[idx.int]
func `[]`*(c: Codex, idx: StrPoolIdx): string = c.strPool[idx.int]
func `[]`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: Codex[C, G, A, L],
  idx: AtomPoolIdx
): seq[A] = c.atomPool[idx.int]
func `[]`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: Codex[C, G, A, L],
  idx: SetPoolIdx
): set[A] = c.setPool[idx.int]
func `[]`*(c: Codex, idx: RuleIdx): RuleDef = c.rulePool[idx.int]
func `[]`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: Codex[C, G, A, L],
  idx: ActIdx
): ActProc[C, G, A, L] = c.actPool[idx.int]

func add*(c: var Codex, v: Verse): VerseIdx =
  VerseIdx(c.verses.getOrAdd(v))
func add*(c: var Codex, v: VerseIdx): SpineIdx =
  c.spine.add(v)
  SpineIdx(c.spine.high)
func add*(c: var Codex, v: string): StrPoolIdx =
  StrPoolIdx(c.strPool.getOrAdd(v))
func add*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: var Codex[C, G, A, L],
  v: A | seq[A]
): AtomPoolIdx = AtomPoolIdx(c.atomPool.getOrAdd(v))
func add*(c: var Codex, v: set[char]): SetPoolIdx =
  SetPoolIdx(c.setPool.getOrAdd(v))
func add*(c: var Codex, v: RuleDef): RuleIdx =
  RuleIdx(c.rulePool.getOrAdd(v))
func addAct*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  c: var Codex[C, G, A, L],
  v: ActProc[C, G, A, L]
): ActIdx =
  ActIdx(c.actPool.getOrAdd(v))


# Verse helpers
func seq*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]],
  spineStart: SpineIdx,
  spineLen: int
): T = T(
  kind: vkSeq, spineStart: spineStart, spineLen: spineLen
)

func choice*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]],
  tryVerse: VerseIdx,
  elseVerse: VerseIdx
): T = T(kind: vkChoice, tryVerse: tryVerse, elseVerse: elseVerse)

func loop*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]],
  bodyVerse: VerseIdx
): T = T(kind: vkLoop, bodyVerse: bodyVerse)

func call*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  ruleDef: RuleDef
): T = T(kind: vkCall, ruleIdx: c.add(ruleDef))

func siphon*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  siphonBody: VerseIdx,
  channelIdx: G
): T = T(
  kind: vkSiphon, siphonBody: siphonBody, channelIdx: channelIdx
)

func act*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  actBody: VerseIdx,
  actIdx: ActIdx
): T = T(
  kind: vkAct,
  actBody: actBody,
  actIdx: actIdx
)

func errorLabel*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  body: VerseIdx,
  label: string
): T =
  T(kind: vkErrorLabel, labelledVerseIdx: body, labelStrIdx: c.add(label))

func lookahead*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]],
  body: VerseIdx,
  invert = false
): T = T(
  kind: vkLookahead, lookaheadVerse: body, invert: invert
)

# Codex for `Atom` is a no-op, just there for a nice API
func checkMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  _: var Codex[C, G, A, L],
  at: Atom
): T = T(kind: vkCheckMatch, checkType: ckAtom, valAtom: at)
func checkMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  s: openArray[A]
): T = T(
  kind: vkCheckMatch, checkType: ckSeqAtom, atomPoolIdx: c.add(@s)
)
func checkMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  s: set[A]
): T = T(
  kind: vkCheckMatch, checkType: ckSet, setPoolIdx: c.add(s)
)


# Codex for `Atom` is a no-op, just there for a nice API
func checkNoMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  _: var Codex[C, G, A, L],
  at: Atom
): T = T(kind: vkCheckNoMatch, checkType: ckAtom, valAtom: at)
func checkNoMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  s: set[A]
): T = T(kind: vkCheckNoMatch, checkType: ckSet, setPoolIdx: c.add(s))
func checkMatchAny*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]]
): T =
  T(kind: vkCheckMatch, checkType: ckAny)

func checkNoMatchAny*[G: Ordinal, A: Atom](
  T: typedesc[Verse[G, A]]): T =
  T(kind: vkCheckNoMatch, checkType: ckAny)

func commit*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[Verse[G, A]],
  c: var Codex[C, G, A, L],
  body: VerseIdx
): T = T(kind: vkCommit, commitBody: body)