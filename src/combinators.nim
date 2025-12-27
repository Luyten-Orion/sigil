import sigil
import sigil/codex
import std/strutils

type
  CodexRef[C: Ctx, G: Ordinal, A: Atom, L: static bool] = ref Codex[C, G, A, L]

  RuleBuilder*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    root*: VerseIdx     # Rule entrypoint
    codex*: CodexRef[C, G, A, L] # Shared state

  # Handle that exists for referring to another rule.
  Rule*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    builder*: RuleBuilder[C, G, A, L]
    id*: RuleIdx

# Helpers
proc `new`[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[CodexRef[C, G, A, L]]
): T = T()

proc `init`[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]],
  root: VerseIdx,
  codex: CodexRef[C, G, A, L]
): T = T(root: root, codex: codex)

func getOrAdd[T](
  pool: var seq[T],
  val: T
): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high

func add[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  b: var RuleBuilder[C, G, A, L], v: Verse[G, A]
): VerseIdx = b.codex.add(v)

# For stitching together codexes (since each rule builder has its own codex)
proc stitch[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  dest, src: CodexRef[C, G, A, L], 
  entry: VerseIdx
): VerseIdx =
  if dest == src: return entry

  let origVerse = src[entry]
  var verse = origVerse

  case origVerse.kind
  of vkSeq:
    var newChildren = newSeqOfCap[VerseIdx](origVerse.spineLen)
    for i in 0..<origVerse.spineLen:
      let childIdx = src[SpineIdx(int(origVerse.spineStart) + i)]
      newChildren.add(dest.stitch(src, childIdx))
    if newChildren.len > 0:
      let start = dest.add(newChildren[0])
      for i in 1..<newChildren.len:
        discard dest.add(newChildren[i])
      verse.spineStart = start
    else:
      verse.spineStart = SpineIdx(dest.spine.len)

  of vkChoice:
    verse.tryVerse = dest.stitch(src, origVerse.tryVerse)
    verse.elseVerse = dest.stitch(src, origVerse.elseVerse)

  of vkLoop:
    verse.bodyVerse = dest.stitch(src, origVerse.bodyVerse)

  of vkSiphon:
    verse.siphonBody = dest.stitch(src, origVerse.siphonBody)

  of vkTransmute:
    verse.transmuteBody = dest.stitch(src, origVerse.transmuteBody)
    verse.siphonChannel = origVerse.siphonChannel
    let idx = dest.transmutePool.getOrAdd(src[origVerse.transmuteIdx])
    verse.transmuteIdx = TransmuteIdx(idx)

  of vkAbsorb:
    verse.absorbBody = dest.stitch(src, origVerse.absorbBody)
    let idx = dest.absorbPool.getOrAdd(src[origVerse.absorbIdx])
    verse.absorbIdx = AbsorbIdx(idx)

  of vkScry:
    verse.scryBody = dest.stitch(src, origVerse.scryBody)
    let idx = dest.scryPool.getOrAdd(src[origVerse.scryIdx])
    verse.scryIdx = ScryIdx(idx)

  of vkErrorLabel:
    verse.labelledVerseIdx = dest.stitch(src, origVerse.labelledVerseIdx)
    let idx = dest.strPool.getOrAdd(src[origVerse.labelStrIdx])
    verse.labelStrIdx = StrPoolIdx(idx)

  of vkLookahead:
    verse.lookaheadVerse = dest.stitch(src, origVerse.lookaheadVerse)
  
  of vkCall:
    let srcDef = src[origVerse.ruleIdx]
    var foundIdx = -1
    for i, r in dest.rulePool:
      if r.name == srcDef.name:
        foundIdx = i
        break
    if foundIdx == -1:
      foundIdx = dest.rulePool.len
      dest.rulePool.add RuleDef(
        name: srcDef.name, 
        entry: VerseIdx(-1)
      )
      if srcDef.entry.int != -1:
        let newEntry = dest.stitch(src, srcDef.entry)
        dest.rulePool[foundIdx].entry = newEntry
      
    verse.ruleIdx = RuleIdx(foundIdx)

  of vkCheckMatch, vkCheckNoMatch:
    case origVerse.checkType
    of ckSeqAtom:
      let idx = dest.atomPool.getOrAdd(src[origVerse.atomPoolIdx])
      verse.atomPoolIdx = AtomPoolIdx(idx)
    of ckSet:
      let idx = dest.setPool.getOrAdd(src[origVerse.setPoolIdx])
      verse.setPoolIdx = SetPoolIdx(idx)
    else: discard

  dest.add(verse)

# Primitives
func match*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]],
  val: A | set[A]
): T =
  let
    codex = CodexRef[C, G, A, L].new()
    root = codex.add(Verse[G, A].checkMatch(codex[], val))
  T.init(root, codex)

func match*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]],
  vals: openArray[A]
): T =
  let
    codex = CodexRef[C, G, A, L].new()
    root = codex.add(Verse[G, A].checkMatch(codex[], @vals))
  T.init(root, codex)

func any*[C: Ctx, G: Ordinal, A: Atom, L: static bool](T: typedesc[RuleBuilder[C, G, A, L]]): T =
  let
    codex = CodexRef[C, G, A, L].new()
    root = codex.add(Verse[G, A].checkMatchAny())
  T.init(root, codex)

func noMatch*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]],
  val: A | set[A]
): T =
  let
    codex = CodexRef[C, G, A, L].new()
    root = codex.add(Verse[G, A].checkNoMatch(codex[], val))
  T.init(root, codex)

func notAny*[C: Ctx, G: Ordinal, A: Atom, L: static bool](T: typedesc[RuleBuilder[C, G, A, L]]): T =
  let
    codex = CodexRef[C, G, A, L].new()
    root = codex.add(Verse[G, A].checkNoMatchAny())
  T.init(root, codex)

# Rules
func define*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]], 
  name: string
): Rule[C, G, A, L] =
  # Reserves the rule in the codex
  let
    codex = CodexRef[C, G, A, L].new()
    def = RuleDef(name: name, entry: VerseIdx(-1))
  
  result.id = codex.add(def)
  result.builder = T.init(VerseIdx(-1), codex)

func implement*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  r: Rule[C, G, A, L], body: RuleBuilder[C, G, A, L]
) =
  # Replaces the body of the rule.
  let bodyRoot = r.builder.codex.stitch(body.codex, body.root)
  r.builder.codex.rulePool[r.id.int].entry = bodyRoot

func define*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  T: typedesc[RuleBuilder[C, G, A, L]], 
  name: string, 
  body: RuleBuilder[C, G, A, L]
): Rule[C, G, A, L] =
  result = T.define(name)
  result.implement(body)

func call*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  r: Rule[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = r.builder
  let def = result.codex[r.id]
  result.root = result.add(Verse[G, A].call(result.codex[], def))

# Combinators
func `and`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  a, b: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = a
  let bRoot = result.codex.stitch(b.codex, b.root)
  let aVerse = result.codex[a.root]

  if aVerse.kind == vkSeq:
    discard result.codex.add(bRoot) 
    result.codex.verses[a.root.int].spineLen.inc
  else:
    let start = result.codex.add(a.root) 
    discard result.codex.add(bRoot)      

    result.root = result.add(Verse[G, A].seq(start, 2))

func chain*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  ps: varargs[RuleBuilder[C, G, A, L]]
): RuleBuilder[C, G, A, L] =
  assert ps.len > 1, "`join` requires at least 2 arguments"
  result = ps[0]
  for p in ps[1..^1]:
    result = result and p

func `or`*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  a, b: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = a
  let bRoot = result.codex.stitch(b.codex, b.root)
  result.root = result.add(Verse[G, A].choice(a.root, bRoot))

func fork*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  ps: varargs[RuleBuilder[C, G, A, L]]
): RuleBuilder[C, G, A, L] =
  assert ps.len > 1, "`fork` requires at least 2 arguments"
  result = ps[0]
  for p in ps[1..^1]:
    result = result or p

func many0*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].loop(p.root))

func many1*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] = p and many0(p)

func optional*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  let emptyRoot = result.add(Verse[G, A].seq(SpineIdx(result.codex.spine.len), 0))
  result.root = result.add(Verse[G, A].choice(p.root, emptyRoot))

# Capturing! Wow!
func siphon*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L],
  channel: G
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].siphon(
    result.codex[], p.root, channel
  ))

# Callbacks! Woah!
func transmute*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L], 
  channel: G,
  cb: TransmuteProc[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].transmute(
    result.codex[], p.root, channel, result.codex.add(cb)
  ))

func absorb*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L], 
  cb: AbsorbProc[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].absorb(
    result.codex[], p.root, result.codex.addAbs(cb)
  ))

func scry*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L], 
  cb: ScryProc[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].scry(
    result.codex[], p.root, result.codex.addScr(cb)
  ))

# Error handling
func errorLabel*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L],
  msg: string
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].errorLabel(p.codex[], p.root, msg))

# Lookaheads
func peek*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].lookahead(p.root, false))

func reject*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  p: RuleBuilder[C, G, A, L]
): RuleBuilder[C, G, A, L] =
  result = p
  result.root = result.add(Verse[G, A].lookahead(p.root, true))

# Fi. The End.
func finalise*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  r: RuleBuilder[C, G, A, L]
): Codex[C, G, A, L] = r.codex[]
