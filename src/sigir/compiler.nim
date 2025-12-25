import std/[tables]
import sigil
# Combinators only used for the `Rule` type.
import sigil/combinators
import sigil/codex/ctypes
import sigil/sigir/stypes

type
  UnresolvedCall = object
    idx: int
    rIdx: RuleIdx

  CompileCtx[C: Ctx] = object
    codex: Codex[C]
    glyph: Glyph[C]
    ruleMap: Table[RuleIdx, int]
    unresolvedCalls: seq[UnresolvedCall]

# Helpers
func emit[C: Ctx](ctx: var CompileCtx[C], op: OpCode, val = 0): int =
  result = ctx.glyph.insts.len
  case op
  of opJump, opChoice, opCommit, opCall, opPeek, opReject:
    ctx.glyph.insts.add Instruction(op: op, valTarget: val)
  else:
    ctx.glyph.insts.add Instruction(op: op)

func emit[C: Ctx](ctx: var CompileCtx[C], op: OpCode, c: char) =
  case op
  of opChar, opExceptChar:
    ctx.glyph.insts.add Instruction(op: op, valChar: c)
  else:
    assert false, "Unreachable"

func getOrAdd[T](
  pool: var seq[T],
  val: T
): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high

# Compilation go brr
proc compileVerse[C: Ctx](ctx: var CompileCtx[C], idx: VerseIdx) =
  template patch(idx: int) =
    ctx.glyph.insts[idx].valTarget = ctx.glyph.insts.len

  let v = ctx.codex[idx]

  case v.kind
  of vkSeq:
    for i in 0..<v.spineLen:
      ctx.compileVerse(ctx.codex[SpineIdx(int(v.spineStart) + i)])

  of vkChoice:
    # Try -> Jump(Else)
    let tryJump = ctx.emit(opChoice, 0)
    ctx.compileVerse(v.tryVerse)
    # Try Success -> Jump(End)
    let exitJump = ctx.emit(opCommit, 0)
    # Else
    patch(tryJump)
    ctx.compileVerse(v.elseVerse)
    # End (Set exit jump)
    patch(exitJump)

  of vkLoop:
    # Commit here
    let startIdx = ctx.emit(opChoice, 0)
    ctx.compileVerse(v.bodyVerse)
    # Loop back on success
    discard ctx.emit(opCommit, startIdx)
    # Patch exit
    patch(startIdx)

  of vkCapture:
    discard ctx.emit(opCapPushPos)
    ctx.compileVerse(v.bodyVerse)
    discard ctx.emit(opCapPopPos)

  of vkErrorLabel:
    let idx = ctx.glyph.strPool.getOrAdd(ctx.codex[v.labelStrIdx])
    ctx.glyph.insts.add Instruction(op: opPushErrLabel, valStrIdx: idx)
    ctx.compileVerse(v.labelledVerseIdx)
    discard ctx.emit(opPopErrLabel)
  
  of vkLookahead:
    let op = if v.invert: opReject else: opPeek
    let jmp = ctx.emit(op, 0)
    ctx.compileVerse(v.lookaheadVerse)
    # Commit
    discard ctx.emit(opCommit, 0)
    # Lookahead must skip to after the block
    patch(jmp)

  of vkCall:
    let idx = ctx.emit(opCall, 0)
    ctx.unresolvedCalls.add(UnresolvedCall(idx: idx, rIdx: v.ruleIdx))

  of vkAction:
    let idx = ctx.glyph.actionPool.getOrAdd(ctx.codex[v.actionIdx])
    ctx.glyph.insts.add Instruction(op: opAction, valActionIdx: idx)

  # Terminals
  of vkCheckMatch, vkCheckNoMatch:
    let isMatch = v.kind == vkCheckMatch
    
    case v.checkType
    of ckChar: 
      ctx.emit(if isMatch: opChar else: opExceptChar, v.valChar)
    of ckAny:  
      discard ctx.emit(opAny)
    of ckStr:
      let idx = ctx.glyph.strPool.getOrAdd(ctx.codex[v.strPoolIdx])
      ctx.glyph.insts.add Instruction(op: opStr, valStrIdx: idx)
    of ckSet:
      let
        idx = ctx.glyph.setPool.getOrAdd(ctx.codex[v.setPoolIdx])
        inst = case isMatch
          of true: Instruction(op: opSet, valSetIdx: idx)
          of false: Instruction(op: opExceptSet, valSetIdx: idx)
      ctx.glyph.insts.add inst


# Entrypoint
proc compile*[C: Ctx](entry: Rule[C]): Glyph[C] =
  var ctx = CompileCtx[C](
    codex: entry.builder.codex[],
    ruleMap: initTable[RuleIdx, int](),
  )

  # Acts as the entrypoint
  ctx.ruleMap[entry.id] = 0
  ctx.compileVerse(ctx.codex[entry.id].entry)
  discard ctx.emit(opReturn)

  # Compile all rules in the codex
  for i, def in ctx.codex.rulePool:
    let rIdx = RuleIdx(i)
    if rIdx == entry.id: continue
    # Forward decl
    if def.entry.int == -1: continue

    ctx.ruleMap[rIdx] = ctx.glyph.insts.len
    ctx.compileVerse(def.entry)
    discard ctx.emit(opReturn)

  # Resolve unresolved calls
  for pc in ctx.unresolvedCalls:
    if pc.rIdx notin ctx.ruleMap:
      raise newException(ValueError, "Linker: Missing rule implementation for " & $pc.rIdx)
    ctx.glyph.insts[pc.idx].valTarget = ctx.ruleMap[pc.rIdx]

  result = ctx.glyph