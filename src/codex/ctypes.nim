import sigil

type
  # A collection of verses and the information needed to execute them
  Codex*[C: Ctx] = object
    verses*: seq[Verse]
    # A collection of verse indexes to be executed in order
    # TODO: Maybe throw that idea away? May be overkill
    spine*: seq[VerseIdx]
    strPool*: seq[string]
    setPool*: seq[set[char]]
    rulePool*: seq[RuleDef]
    actionPool*: seq[ActionProc[C]]

  VerseKind* = enum
    vkSeq                        # A block of steps
    vkChoice                     # A fork (Try/Else)
    vkLoop                       # A repetition
    vkCall                       # A subroutine call
    vkAction                     # User code execution
    vkCapture                    # Capture the text of a match
    vkErrorLabel                 # An error label
    vkLookahead                  # Executes verse but then rewinds cursor
    vkCheckMatch, vkCheckNoMatch # A terminal match

  CheckKind* = enum
    ckChar, ckSet, ckStr, ckAny

  # A single executable instruction
  Verse* = object
    case kind*: VerseKind
    of vkSeq:
      spineStart*: SpineIdx
      spineLen*: int

    of vkChoice:
      tryVerse*: VerseIdx
      elseVerse*: VerseIdx

    of vkLoop, vkCapture: bodyVerse*: VerseIdx
    of vkCall: ruleIdx*: RuleIdx

    of vkAction: actionIdx*: ActionIdx
    
    of vkErrorLabel:
      labelledVerseIdx*: VerseIdx
      labelStrIdx*: StrPoolIdx

    of vkLookahead:
      lookaheadVerse*: VerseIdx
      invert*: bool # Toggle to fail on success

    of vkCheckMatch, vkCheckNoMatch:
      case checkType*: CheckKind
      of ckChar: valChar*: char
      of ckStr: strPoolIdx*: StrPoolIdx
      of ckSet: setPoolIdx*: SetPoolIdx
      of ckAny: discard

  RuleDef* = object
    name*: string
    entry*: VerseIdx

  VerseIdx* = distinct int
  SpineIdx* = distinct int
  StrPoolIdx* = distinct int
  SetPoolIdx* = distinct int
  RuleIdx* = distinct int
  ActionIdx* = distinct int

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
func `==`*(a, b: SetPoolIdx): bool {.borrow.}
func `==`*(a, b: RuleIdx): bool {.borrow.}
func `==`*(a, b: ActionIdx): bool {.borrow.}
func `$`*(a: VerseIdx): string = "v@" & $int(a)
func `$`*(a: SpineIdx): string = "s@" & $int(a)
func `$`*(a: StrPoolIdx): string = "pstr@" & $int(a)
func `$`*(a: SetPoolIdx): string = "pset@" & $int(a)
func `$`*(a: RuleIdx): string = "r@" & $int(a)
func `$`*(a: ActionIdx): string = "a@" & $int(a)
func `[]`*(c: Codex, idx: VerseIdx): Verse = c.verses[idx.int]
func `[]`*(c: Codex, idx: SpineIdx): VerseIdx = c.spine[idx.int]
func `[]`*(c: Codex, idx: StrPoolIdx): string = c.strPool[idx.int]
func `[]`*(c: Codex, idx: SetPoolIdx): set[char] = c.setPool[idx.int]
func `[]`*(c: Codex, idx: RuleIdx): RuleDef = c.rulePool[idx.int]
func `[]`*[C: Ctx](c: Codex[C], idx: ActionIdx): ActionProc[C] =
  c.actionPool[idx.int]

func add*(c: var Codex, v: Verse): VerseIdx =
  VerseIdx(c.verses.getOrAdd(v))

func add*(c: var Codex, v: VerseIdx): SpineIdx =
  result = SpineIdx(c.spine.len)
  c.spine.add(v)

func add*(c: var Codex, v: string): StrPoolIdx =
  StrPoolIdx(c.strPool.getOrAdd(v))

func add*(c: var Codex, v: set[char]): SetPoolIdx =
  SetPoolIdx(c.setPool.getOrAdd(v))

func add*(c: var Codex, v: RuleDef): RuleIdx =
  RuleIdx(c.rulePool.getOrAdd(v))

func add*[C: Ctx](c: var Codex[C], v: ActionProc[C]): ActionIdx =
  ActionIdx(c.actionPool.getOrAdd(v))

# Verse helpers
func seq*(T: typedesc[Verse], spineStart: SpineIdx, spineLen: int): T = T(
  kind: vkSeq, spineStart: spineStart, spineLen: spineLen
)

func choice*(
  T: typedesc[Verse],
  tryVerse: VerseIdx,
  elseVerse: VerseIdx
): T = T(kind: vkChoice, tryVerse: tryVerse, elseVerse: elseVerse)

func loop*(T: typedesc[Verse], bodyVerse: VerseIdx): T = T(
  kind: vkLoop, bodyVerse: bodyVerse
)

func call*(T: typedesc[Verse], c: var Codex, ruleDef: RuleDef): T = T(
  kind: vkCall, ruleIdx: c.add(ruleDef)
)

func action*[C: Ctx](
  T: typedesc[Verse],
  c: var Codex[C],
  a: ActionProc[C]
): T = T(
  kind: vkAction, actionIdx: c.add(a)
)

func capture*(T: typedesc[Verse], body: VerseIdx): T = T(
  kind: vkCapture, bodyVerse: body
)

func errorLabel*(T: typedesc[Verse], c: var Codex, body: VerseIdx, label: string): T = T(
  kind: vkErrorLabel, labelledVerseIdx: body, labelStrIdx: c.add(label)
)

func lookahead*(T: typedesc[Verse], body: VerseIdx, invert = false): T = T(
  kind: vkLookahead, lookaheadVerse: body, invert: invert
)

func checkMatch*(T: typedesc[Verse], ch: char): T = T(
  kind: vkCheckMatch, checkType: ckChar, valChar: ch
)
# Codex for `char` is a no-op, just there for a nice API
func checkMatch*(T: typedesc[Verse], _: var Codex, ch: char): T = T(
  kind: vkCheckMatch, checkType: ckChar, valChar: ch
)
func checkMatch*(T: typedesc[Verse], c: var Codex, s: string): T = T(
  kind: vkCheckMatch, checkType: ckStr, strIdx: c.add(s)
)
func checkMatch*(T: typedesc[Verse], c: var Codex, s: set[char]): T = T(
  kind: vkCheckMatch, checkType: ckSet, setIdx: c.add(s)
)

func checkNoMatch*(T: typedesc[Verse], ch: char): T = T(
  kind: vkCheckNoMatch, checkType: ckChar, valChar: ch
)
func checkNoMatch*(T: typedesc[Verse], _: var Codex, ch: char): T = T(
  kind: vkCheckNoMatch, checkType: ckChar, valChar: ch
)
func checkNoMatch*(T: typedesc[Verse], c: var Codex, s: string): T = T(
  kind: vkCheckNoMatch, checkType: ckStr, strIdx: c.add(s)
)
func checkNoMatch*(T: typedesc[Verse], c: var Codex, s: set[char]): T = T(
  kind: vkCheckNoMatch, checkType: ckSet, setIdx: c.add(s)
)

func checkMatchAny*(T: typedesc[Verse]): T = T(
  kind: vkCheckMatch, checkType: ckAny
)