import std/tables
import sigil
import sigil/sigir
import sigil/codex
import sigil/combinators

type
  UnresolvedCall = object
    idx: int
    rIdx: RuleIdx

  CompileCtx[C; G: Ordinal; A; L: static bool] = object
    codex: Codex[C, G, A, L]
    glyph: Glyph[C, G, A, L]
    ruleMap: Table[RuleIdx, int]
    unresolvedCalls: seq[UnresolvedCall]

# Helpers
func emit[C, G, A, L](ctx: var CompileCtx[C, G, A, L], op: OpCode, val: int = 0): int =
  result = ctx.glyph.insts.len
  var inst = Instruction[G, A](op: op)
  
  case op
  of opJump, opChoice, opCommit, opCall, opPeek, opReject:
    inst.valTarget = val
  of opTransmute:
    inst.valTransmuteIdx = val
  of opAbsorb:
    inst.valAbsorbIdx = val
  of opScry:
    inst.valScryIdx = val
  else: discard
  
  ctx.glyph.insts.add inst

func emit[C, G, A, L](ctx: var CompileCtx[C, G, A, L], op: OpCode, val: A) =
  case op
  of opAtom, opExceptAtom:
    ctx.glyph.insts.add Instruction[G, A](op: op, valAtom: val)
  else:
    assert true, "Unreachable"

func emitSiphon[C, G, A, L](ctx: var CompileCtx[C, G, A, L], channel: G) =
  ctx.glyph.insts.add Instruction[G, A](op: opSiphonPop, siphonChannel: channel)

func getOrAdd[T](pool: var seq[T], val: T): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high

# Compilation
proc compileVerse[C, G, A, L](ctx: var CompileCtx[C, G, A, L], idx: VerseIdx) =
  template patch(idx: int) =
    ctx.glyph.insts[idx].valTarget = ctx.glyph.insts.len

  let v = ctx.codex[idx]

  case v.kind
  of vkSeq:
    for i in 0..<v.spineLen:
      ctx.compileVerse(ctx.codex[SpineIdx(int(v.spineStart) + i)])

  of vkChoice:
    let tryJump = ctx.emit(opChoice)
    ctx.compileVerse(v.tryVerse)
    let exitJump = ctx.emit(opCommit)
    patch(tryJump)
    ctx.compileVerse(v.elseVerse)
    patch(exitJump)

  of vkLoop:
    let startIdx = ctx.emit(opChoice)
    ctx.compileVerse(v.bodyVerse)
    discard ctx.emit(opCommit, startIdx)
    patch(startIdx)

  of vkSiphon:
    discard ctx.emit(opCapPushPos)
    ctx.compileVerse(v.siphonBody)
    ctx.emitSiphon(v.channelIdx)

  of vkTransmute:
    ctx.compileVerse(v.transmuteBody)
    var inst = Instruction[G, A](
      op: opTransmute, 
      valTransmuteIdx: v.transmuteIdx.int,
      transmuteChannel: v.siphonChannel
    )
    ctx.glyph.insts.add inst

  of vkAbsorb:
    ctx.compileVerse(v.absorbBody)
    discard ctx.emit(opAbsorb, v.absorbIdx.int)

  of vkScry:
    ctx.compileVerse(v.scryBody)
    discard ctx.emit(opScry, v.scryIdx.int)

  of vkErrorLabel:
    let idx = ctx.glyph.strPool.getOrAdd(ctx.codex[v.labelStrIdx])
    var inst = Instruction[G, A](op: opPushErrLabel)
    inst.valStrIdx = idx
    ctx.glyph.insts.add inst
    
    ctx.compileVerse(v.labelledVerseIdx)
    discard ctx.emit(opPopErrLabel)
   
  of vkLookahead:
    let op = if v.invert: opReject else: opPeek
    let jmp = ctx.emit(op)
    ctx.compileVerse(v.lookaheadVerse)
    discard ctx.emit(opCommit)
    patch(jmp)

  of vkCall:
    let idx = ctx.emit(opCall, 0)
    ctx.unresolvedCalls.add(UnresolvedCall(idx: idx, rIdx: v.ruleIdx))

  of vkCheckMatch, vkCheckNoMatch:
    let isMatch = v.kind == vkCheckMatch
    
    case v.checkType
    of ckAtom: 
      ctx.emit(if isMatch: opAtom else: opExceptAtom, v.valAtom)
    of ckAny:
      if isMatch:
        discard ctx.emit(opAny)
      else:
        let jmp = ctx.emit(opReject)
        discard ctx.emit(opAny)
        discard ctx.emit(opCommit)
        patch(jmp)
    of ckSeqAtom:
      let idx = ctx.glyph.atomPool.getOrAdd(ctx.codex[v.atomPoolIdx])
      var inst = Instruction[G, A](op: opSeqAtom)
      inst.valPoolIdx = idx
      ctx.glyph.insts.add inst
    of ckSet:
      let idx = ctx.glyph.setPool.getOrAdd(ctx.codex[v.setPoolIdx])
      var inst = Instruction[G, A](op: if isMatch: opSet else: opExceptSet)
      inst.valSetIdx = idx
      ctx.glyph.insts.add inst

# Entrypoint
proc compile*[C, G, A, L](entry: Rule[C, G, A, L]): Glyph[C, G, A, L] =
  var ctx = CompileCtx[C, G, A, L](
    codex: entry.builder.finalise(),
    glyph: Glyph[C, G, A, L](),
    ruleMap: initTable[RuleIdx, int](),
  )

  # Pools are preserved 1:1 between codex and glyph
  ctx.glyph.strPool = ctx.codex.strPool
  ctx.glyph.atomPool = ctx.codex.atomPool
  ctx.glyph.setPool = ctx.codex.setPool
  ctx.glyph.transmutePool = ctx.codex.transmutePool
  ctx.glyph.absorbPool = ctx.codex.absorbPool
  ctx.glyph.scryPool = ctx.codex.scryPool

  ctx.ruleMap[entry.id] = 0
  ctx.compileVerse(ctx.codex[entry.id].entry)
  discard ctx.emit(opReturn)

  for i, def in ctx.codex.rulePool:
    let rIdx = RuleIdx(i)
    if rIdx == entry.id: continue
    if def.entry.int == -1: continue

    ctx.ruleMap[rIdx] = ctx.glyph.insts.len
    ctx.compileVerse(def.entry)
    discard ctx.emit(opReturn)

  for pc in ctx.unresolvedCalls:
    if pc.rIdx notin ctx.ruleMap:
      raise newException(ValueError, "Linker: Missing rule implementation")
    ctx.glyph.insts[pc.idx].valTarget = ctx.ruleMap[pc.rIdx]

  result = ctx.glyph
