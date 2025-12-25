import sigil
import sigil/codex/ctypes

type
  CodexRef[C: Ctx] = ref Codex[C]

  RuleBuilder*[C: Ctx] = object
    root*: VerseIdx     # Rule entrypoint
    codex*: CodexRef[C] # Shared state (hence the ref)

  # Handle that exists for referring to another rule.
  Rule*[C: Ctx] = object
    builder*: RuleBuilder[C]
    id*: RuleIdx

# Helpers
proc `new`[C: Ctx](T: typedesc[CodexRef[C]]): T = T()

proc `init`[C: Ctx](
  T: typedesc[RuleBuilder[C]],
  root: VerseIdx,
  codex: CodexRef[C]
): T = T(root: root, codex: codex)

func add[C: Ctx](b: var RuleBuilder[C], v: Verse): VerseIdx =
  result = b.codex.add(v)

func getOrAdd[T](
  pool: var seq[T],
  val: T
): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high

# TODO: This will die on large rules, need to make it not recursive
proc stitch[C: Ctx](dest, src: CodexRef[C], entry: VerseIdx): VerseIdx =
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

  of vkLoop, vkCapture:
    verse.bodyVerse = dest.stitch(src, origVerse.bodyVerse)

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
    of ckStr:
      let idx = dest.strPool.getOrAdd(src[origVerse.strPoolIdx])
      verse.strPoolIdx = StrPoolIdx(idx)
    of ckSet:
      let idx = dest.setPool.getOrAdd(src[origVerse.setPoolIdx])
      verse.setPoolIdx = SetPoolIdx(idx)
    else: discard

  of vkAction:
    let idx = dest.actionPool.getOrAdd(src[origVerse.actionIdx])
    verse.actionIdx = ActionIdx(idx)

  dest.add(verse)

# Primitives
func match*[C: Ctx, M: char | set[char] | string](
  T: typedesc[RuleBuilder[C]],
  val: M
): T =
  let
    codex = CodexRef[C].new()
    root = codex.add(Verse.checkMatch(codex[], val))

  T.init(root, codex)

func any*[C: Ctx](T: typedesc[RuleBuilder[C]]): T =
  let
    codex = CodexRef[C].new()
    root = codex.add(Verse.checkMatchAny())

  T.init(root, codex)

func noMatch*[C: Ctx, M: char | set[char]](
  T: typedesc[RuleBuilder[C]],
  val: M
): T =
  let
    codex = CodexRef[C].new()
    root = codex.add(Verse.checkNoMatch(codex[], val))

  T.init(root, codex)


# Rules


func define*[C: Ctx](
  T: typedesc[RuleBuilder[C]], 
  name: string
): Rule[C] =
  # Reserves the rule in the codex
  let
    codex = CodexRef[C].new()
    def = RuleDef(name: name, entry: VerseIdx(-1))
  
  result.id = codex.add(def)
  result.builder = T.init(VerseIdx(-1), codex)

func implement*[C: Ctx](r: Rule[C], body: RuleBuilder[C]) =
  # Replaces the body of the rule.
  let bodyRoot = r.builder.codex.stitch(body.codex, body.root)
  r.builder.codex.rulePool[r.id.int].entry = bodyRoot

func define*[C: Ctx](
  T: typedesc[RuleBuilder[C]], 
  name: string, 
  body: RuleBuilder[C]
): Rule[C] =
  result = define(T, name)
  implement(result, body)

func call*[C: Ctx](r: Rule[C]): RuleBuilder[C] =
  result = r.builder
  let def = result.codex[r.id]
  result.root = result.add(Verse.call(result.codex[], def))

# Combinators go brr
func `and`*[C: Ctx](a, b: RuleBuilder[C]): RuleBuilder[C] =
  result = a
  let bRoot = result.codex.stitch(b.codex, b.root)
  let aVerse = result.codex[a.root]

  if aVerse.kind == vkSeq:
    discard result.codex.add(bRoot) 
    result.codex.verses[a.root.int].spineLen.inc
  else:
    let start = result.codex.add(a.root) # Returns current index
    discard result.codex.add(bRoot)      # Returns next index (contiguous)

    result.root = result.add(Verse.seq(start, 2))

func `or`*[C: Ctx](a, b: RuleBuilder[C]): RuleBuilder[C] =
  result = a
  let bRoot = result.codex.stitch(b.codex, b.root)
  result.root = result.add(Verse.choice(a.root, bRoot))

func many0*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p
  result.root = result.add(Verse.loop(p.root))

func many1*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p and many0(p)

func optional*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p
  let emptyRoot = result.add(Verse.seq(SpineIdx(result.codex.spine.len), 0))
  result.root = result.add(Verse.choice(p.root, emptyRoot))

# Actions go brrr
func action*[C: Ctx](p: RuleBuilder[C], act: ActionProc[C]): RuleBuilder[C] =
  result = p
  let actVerse = result.add(Verse.action(result.codex[], act))
  
  let start = result.codex.add(p.root)
  discard result.codex.add(actVerse)
  
  result.root = result.add(Verse.seq(start, 2))

# Gotta capture shit
func capture*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p
  result.root = result.add(Verse.capture(p.root))

# Error handling!
func errorLabel*[C: Ctx](p: RuleBuilder[C], msg: string): RuleBuilder[C] =
  result = p
  result.root = result.add(Verse.errorLabel(p.codex[], p.root, msg))

# Lookaheads!
func peek*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p
  result.root = result.add(Verse.lookahead(p.root, false))

func reject*[C: Ctx](p: RuleBuilder[C]): RuleBuilder[C] =
  result = p
  result.root = result.add(Verse.lookahead(p.root, true))

# Fi.
func finalise*[C: Ctx](r: RuleBuilder[C]): Codex[C] = r.codex[]