import std/[strutils, sets]
import sigil
import sigil/codex/ctypes
import sigil/codex/visitor

type
  ExecEnv*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    input*: seq[A]
    ctx*: ParserCtx[C, G, A, L]
    labelStack*: seq[string]
    furthestFailureIdx*: int
    expectedLabels*: seq[string]

  VerseExecutor*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = 
    VerseVisitor[C, G, A, L, ExecEnv[C, G, A, L], bool]

# --- Pretty Printing ---

func prettyAtom[A](a: A): string = 
  when A is char: 
    escape($a, "", "")
  else: 
    "0x" & toHex(a.uint8)

func prettySet[A](s: set[A]): string =
  var ranges: seq[string]
  var start = 0.uint8
  var inRange = false
  for i in 0..255:
    let c = i.uint8
    if c.A in s:
      if not inRange:
        start = c
        inRange = true
    else:
      if inRange:
        let stop = (i - 1).uint8
        if start == stop: ranges.add(prettyAtom(start.A))
        elif stop == start + 1:
          ranges.add(prettyAtom(start.A))
          ranges.add(prettyAtom(stop.A))
        else: ranges.add(prettyAtom(start.A) & "-" & prettyAtom(stop.A))
        inRange = false
  if inRange:
    let stop = 255.uint8
    if start == stop: ranges.add(prettyAtom(start.A))
    else: ranges.add(prettyAtom(start.A) & "-" & prettyAtom(stop.A))
  
  when A is char: return "[" & ranges.join("") & "]"
  else: return "[" & ranges.join(", ") & "]"

func prettySeq[A](s: seq[A]): string =
  when A is char:
    var buf = ""
    for c in s: buf.add(c)
    escape(buf, "", "")
  else:
    var parts: seq[string]
    for i, x in s:
      if i >= 8:
        parts.add("...")
        break
      parts.add(toHex(x.uint8))
    "[" & parts.join(" ") & "]"

# --- Internal Helper for Error Tracking ---

proc recordFailure[C, G, A, L](e: var ExecEnv[C, G, A, L], fallback: string) =
  let label = if e.labelStack.len > 0: e.labelStack[^1] else: fallback
  if e.ctx.cursorPos > e.furthestFailureIdx:
    e.furthestFailureIdx = e.ctx.cursorPos
    e.expectedLabels = @[label]
  elif e.ctx.cursorPos == e.furthestFailureIdx:
    if label notin e.expectedLabels:
      e.expectedLabels.add(label)

# --- Helper for advance tracking ---

template trackAdvance[C, G, A, L](ctx: var ParserCtx[C, G, A, L], atom: A) =
  when L:
    when A is char:
      if atom == '\r':
        inc ctx.line
        ctx.column = 1
        ctx.lastCr = true
      elif atom == '\n':
        if not ctx.lastCr:
          inc ctx.line
          ctx.column = 1
        ctx.lastCr = false
      else:
        inc ctx.column
        ctx.lastCr = false
    else:
      inc ctx.column

# --- Callback Implementations ---

proc execSeq[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  for i in 0..<node.spineLen:
    let child = v.codex[SpineIdx(int(node.spineStart) + i)]
    if not v.dispatch(e, child): return false
  return true

proc execChoice[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  let saved = e.ctx
  if v.dispatch(e, node.tryVerse): return true
  e.ctx = saved 
  return v.dispatch(e, node.elseVerse)

proc execLoop[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  while true:
    let saved = e.ctx
    if not v.dispatch(e, node.bodyVerse):
      e.ctx = saved
      break
  return true

proc execCall[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  return v.dispatch(e, v.codex[node.ruleIdx].entry)

proc execSiphon[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  let startPos = e.ctx.cursorPos
  if v.dispatch(e, node.siphonBody):
    e.ctx.channels[node.channelIdx].add e.input[startPos ..< e.ctx.cursorPos]
    return true
  return false

proc execTransmute[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  if not v.dispatch(e, node.transmuteBody): return false
  return v.codex[node.transmuteIdx](e.ctx, e.ctx.channels[node.siphonChannel])

proc execAbsorb[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  if not v.dispatch(e, node.absorbBody): return false
  return v.codex[node.absorbIdx](e.ctx)

proc execScry[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  if not v.dispatch(e, node.scryBody): return false
  return v.codex[node.scryIdx](e.ctx)

proc execLookahead[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  let saved = e.ctx
  let matched = v.dispatch(e, node.lookaheadVerse)
  e.ctx = saved
  return if node.invert: not matched else: matched

proc execCheckMatch[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  if e.ctx.cursorPos >= e.input.len and node.checkType != ckSeqAtom:
    e.recordFailure("End of Input")
    return false
  
  case node.checkType
  of ckAtom:
    if e.input[e.ctx.cursorPos] == node.valAtom:
      e.ctx.trackAdvance(e.input[e.ctx.cursorPos])
      inc e.ctx.cursorPos
      return true
    else:
      e.recordFailure(prettyAtom(node.valAtom))
      return false
  of ckAny:
    e.ctx.trackAdvance(e.input[e.ctx.cursorPos])
    inc e.ctx.cursorPos
    return true
  of ckSet:
    let s = v.codex.setPool[node.setPoolIdx.int]
    if e.input[e.ctx.cursorPos] in s:
      e.ctx.trackAdvance(e.input[e.ctx.cursorPos])
      inc e.ctx.cursorPos
      return true
    else:
      e.recordFailure(prettySet(s))
      return false
  of ckSeqAtom:
    let s = v.codex.atomPool[node.atomPoolIdx.int]
    if e.ctx.cursorPos + s.len <= e.input.len:
      for i in 0..<s.len:
        if e.input[e.ctx.cursorPos+i] != s[i]: 
          e.recordFailure(prettySeq(s))
          return false
      for atom in s: e.ctx.trackAdvance(atom)
      e.ctx.cursorPos += s.len
      return true
    else:
      e.recordFailure(prettySeq(s))
      return false

proc execCheckNoMatch[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  if e.ctx.cursorPos >= e.input.len:
    e.recordFailure("End of Input")
    return false

  case node.checkType
  of ckAtom:
    if e.input[e.ctx.cursorPos] != node.valAtom:
      e.ctx.trackAdvance(e.input[e.ctx.cursorPos])
      inc e.ctx.cursorPos
      return true
    else:
      e.recordFailure("Not " & prettyAtom(node.valAtom))
      return false
  of ckSet:
    let s = v.codex.setPool[node.setPoolIdx.int]
    if e.input[e.ctx.cursorPos] notin s:
      e.ctx.trackAdvance(e.input[e.ctx.cursorPos])
      inc e.ctx.cursorPos
      return true
    else:
      e.recordFailure("Not " & prettySet(s))
      return false
  else:
    # Fallback to `not execCheckMatch`
    let
      saved = e.ctx
      matched = v.dispatch(e, vIdx)
    e.ctx = saved 
    return not matched

proc execErrorLabel[C, G, A, L](v: VerseExecutor[C,G,A,L], e: var ExecEnv[C,G,A,L], vIdx: VerseIdx, node: Verse[G,A]): bool =
  e.labelStack.add(v.codex[node.labelStrIdx])
  result = v.dispatch(e, node.labelledVerseIdx)
  discard e.labelStack.pop()

# Creates an executor
proc newExecutor*[C, G, A, L](c: Codex[C, G, A, L]): VerseExecutor[C, G, A, L] =
  result = VerseExecutor[C, G, A, L](
    codex: c,
    visitVSeqCb: execSeq,
    visitVChoiceCb: execChoice,
    visitVLoopCb: execLoop,
    visitVCallCb: execCall,
    visitVSiphonCb: execSiphon,
    visitVTransmuteCb: execTransmute,
    visitVAbsorbCb: execAbsorb,
    visitVScryCb: execScry,
    visitVLookaheadCb: execLookahead,
    visitVCheckMatchCb: execCheckMatch,
    visitVCheckNoMatchCb: execCheckNoMatch,
    visitVErrorLabelCb: execErrorLabel
  )

export visitor