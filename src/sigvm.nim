import std/[
  strutils, sets
]
import sigil
import sigil/sigir/stypes

func prettyAtom[A](a: A): string = 
  when A is char: 
    escape($a, "", "")
  else: 
    "0x" & toHex(a)

func prettySet[A](s: set[A]): string =
  when A is char:
    var
      ranges: seq[string]
      start = '\0'
      inRange = false
    for c in '\0'..'\255':
      if c in s:
        if not inRange:
          start = c
          inRange = true
      else:
        if inRange:
          let stop = char(ord(c) - 1)
          if start == stop: ranges.add(prettyAtom(start))
          elif ord(stop) == ord(start) + 1:
             ranges.add(prettyAtom(start)); ranges.add(prettyAtom(stop))
          else: ranges.add(prettyAtom(start) & "-" & prettyAtom(stop))
          inRange = false
    if inRange:
      let stop = '\255'
      if start == stop: ranges.add(prettyAtom(start))
      else: ranges.add(prettyAtom(start) & "-" & prettyAtom(stop))
    return "[" & ranges.join("") & "]"
  else:
    var
      ranges: seq[string]
      start = 0.uint8
      inRange = false
    for i in 0..255:
      let c = i.uint8
      if c in s:
        if not inRange:
          start = c
          inRange = true
      else:
        if inRange:
          let stop = (i - 1).uint8
          if start == stop: ranges.add(prettyAtom(start))
          elif stop == start + 1:
             ranges.add(prettyAtom(start)); ranges.add(prettyAtom(stop))
          else: ranges.add(prettyAtom(start) & "-" & prettyAtom(stop))
          inRange = false
    if inRange:
      let stop = 255.uint8
      if start == stop: ranges.add(prettyAtom(start))
      else: ranges.add(prettyAtom(start) & "-" & prettyAtom(stop))
    return "[" & ranges.join(", ") & "]"

func prettySeq[A](s: seq[A]): string =
  when A is char:
    var buf = newStringOfCap(s.len)
    for c in s: buf.add(prettyAtom(c))
    escape(buf, "", "")
  else:
    # Hex Dump style for bytes
    var parts: seq[string]
    let limit = 8
    for i, x in s:
      if i >= limit: 
        parts.add("...")
        break
      parts.add(toHex(x))
    "[" & parts.join(" ") & "]"

type
  BacktrackFrame[G: Ordinal, A: Atom, L: static bool] = object
    resumeIdx: int
    cursorPos: int
    capStackLen: int     
    callStackLen: int
    labelStackLen: int
    isLookahead: bool
    invertLookahead: bool
    savedChannels: array[G, seq[seq[A]]]
    when L:
      line: int
      column: int
      lastCr: bool

  CallFrame = object
    returnIdx: int

  VmResult* = object
    success*: bool
    matchLen*: int
    furthestFailureIdx*: int
    expectedTerminals*: seq[string]
    foundTerminal*: string

proc run*[C: Ctx, G: Ordinal, A: Atom, L: static bool](
  glyph: Glyph[C, G, A, L],
  input: seq[A],
  ctx: var ParserCtx[C, G, A, L],
  debug = false
): VmResult =
  var
    instructionIdx = 0
    backtrackStack: seq[BacktrackFrame[G, A, L]]
    callStack: seq[CallFrame]
    captureStartStack: seq[int]
    labelStack: seq[string]
    furthestFailureIdx = -1
    failuresAtMax: HashSet[string]
    lastCr: bool
  
  ctx.cursorPos = 0
  when L:
    ctx.line = 1
    ctx.column = 1
    lastCr = false

  template trackAdvance(atom: A) =
    when L:
      when A is char:
        if atom == '\r': # CR (\r)
          inc ctx.line
          ctx.column = 1
          ctx.lastCr = true
        elif atom == '\n': # LF (\n)
          if ctx.lastCr:
            # We just processed a CR, so this is the LF of a CRLF.
            # We already incremented the line for the CR.
            # Just turn off the flag.
            ctx.lastCr = false
          else:
            # Standard Unix Newline
            inc ctx.line
            ctx.column = 1
            ctx.lastCr = false
        else:
          # Normal char
          inc ctx.column
          ctx.lastCr = false
      else:
        inc ctx.column
    else: discard

  template log(msg: string) =
    if debug: echo "[Inst: ", instructionIdx, " Cursor: ", ctx.cursorPos, "] ", msg

  template recordFailure(msg: string) =
    let finalMsg = if labelStack.len > 0: labelStack[^1] else: msg
    if ctx.cursorPos > furthestFailureIdx:
      furthestFailureIdx = ctx.cursorPos
      failuresAtMax.clear()
      failuresAtMax.incl(finalMsg)
    elif ctx.cursorPos == furthestFailureIdx:
      failuresAtMax.incl(finalMsg)

  template pushBacktrack(target: int, isLook: bool, invert: bool) =
    var frame = BacktrackFrame[G, A, L](
      resumeIdx: target,
      cursorPos: ctx.cursorPos,
      capStackLen: captureStartStack.len,
      callStackLen: callStack.len,
      labelStackLen: labelStack.len,
      isLookahead: isLook,
      invertLookahead: invert,
      savedChannels: ctx.channels
    )
    when L:
      frame.line = ctx.line
      frame.column = ctx.column
      frame.lastCr = ctx.lastCr

    backtrackStack.add(frame)

  template restoreState(frame: BacktrackFrame[G, A, L]) =
    ctx.cursorPos = frame.cursorPos
    captureStartStack.setLen(frame.capStackLen)
    callStack.setLen(frame.callStackLen)
    labelStack.setLen(frame.labelStackLen)
    ctx.channels = frame.savedChannels
    when L:
      ctx.line = frame.line
      ctx.column = frame.column
      ctx.lastCr = frame.lastCr

  template triggerFail() =
    block failureLoop:
      var handled = false
      while backtrackStack.len > 0:
        let frame = backtrackStack.pop()
        
        if not frame.isLookahead:
           restoreState(frame)
           instructionIdx = frame.resumeIdx
           handled = true
           log "Backtracking..."
           break failureLoop
        else:
           if frame.invertLookahead:
             log "Neg Lookahead Success"
             restoreState(frame)
             instructionIdx = frame.resumeIdx
             handled = true
             break failureLoop
           else:
             log "Pos Lookahead Fail"
             continue 

      if not handled:
        log "Hard Fail"
        var errs: seq[string]
        for e in failuresAtMax.items: errs.add(e)
        
        let found = block:
          if furthestFailureIdx >= input.len: "End of Input"
          else: "`" & prettyAtom(input[furthestFailureIdx]) & "`"

        return VmResult(
          success: false, 
          furthestFailureIdx: furthestFailureIdx,
          expectedTerminals: errs,
          foundTerminal: found
        )

  while instructionIdx < glyph.insts.len:
    let inst = glyph.insts[instructionIdx]
    
    case inst.op
    of opAtom:
      if ctx.cursorPos < input.len and input[ctx.cursorPos] == inst.valAtom:
        trackAdvance(inst.valAtom)
        inc ctx.cursorPos; inc instructionIdx
      else:
        recordFailure(prettyAtom(inst.valAtom))
        triggerFail()
        
    of opSet:
      if ctx.cursorPos < input.len and input[ctx.cursorPos] in glyph.setPool[inst.valSetIdx]:
        trackAdvance(input[ctx.cursorPos])
        inc ctx.cursorPos; inc instructionIdx
      else:
        recordFailure(prettySet(glyph.setPool[inst.valSetIdx]))
        triggerFail()

    of opSeqAtom:
      let s = glyph.atomPool[inst.valPoolIdx]
      if ctx.cursorPos + s.len <= input.len:
        var match = true
        for i in 0..<s.len:
          if input[ctx.cursorPos+i] != s[i]: 
            match = false; break
        
        if match:
          for item in s: trackAdvance(item)
          ctx.cursorPos += s.len; inc instructionIdx
        else:
          recordFailure(prettySeq(s))
          triggerFail()
      else:
        recordFailure(prettySeq(s))
        triggerFail()
        
    of opAny:
      if ctx.cursorPos < input.len:
        trackAdvance(input[ctx.cursorPos])
        inc ctx.cursorPos; inc instructionIdx
      else:
        recordFailure("Any")
        triggerFail()

    of opExceptAtom:
      if ctx.cursorPos < input.len and input[ctx.cursorPos] != inst.valAtom:
        trackAdvance(input[ctx.cursorPos])
        inc ctx.cursorPos; inc instructionIdx
      else:
        recordFailure("Not " & prettyAtom(inst.valAtom))
        triggerFail()

    of opExceptSet:
      if ctx.cursorPos < input.len and input[ctx.cursorPos] notin glyph.setPool[inst.valSetIdx]:
        trackAdvance(input[ctx.cursorPos])
        inc ctx.cursorPos; inc instructionIdx
      else:
        recordFailure("Not " & prettySet(glyph.setPool[inst.valSetIdx]))
        triggerFail()

    of opCapPushPos:
      captureStartStack.add(ctx.cursorPos)
      inc instructionIdx

    of opSiphonPop:
      if captureStartStack.len > 0:
        let start = captureStartStack.pop()
        ctx.channels[inst.siphonChannel].add input[start..<ctx.cursorPos]
        inc instructionIdx
      else: 
        triggerFail()

    of opTransmute:
      let cb = glyph.transmutePool[inst.valTransmuteIdx]
      if cb(ctx, ctx.channels[inst.transmuteChannel]):
        inc instructionIdx
      else:
        recordFailure("Transmute Check Failed")
        triggerFail()

    of opAbsorb:
      let absProc = glyph.absorbPool[inst.valAbsorbIdx]
      if absProc(ctx):
        inc instructionIdx
      else:
        recordFailure("Absorb Failed")
        triggerFail()

    of opScry:
      let scryProc = glyph.scryPool[inst.valScryIdx]
      if scryProc(ctx):
        inc instructionIdx
      else:
        recordFailure("Scry Failed")
        triggerFail()

    of opJump: 
      instructionIdx = inst.valTarget

    of opChoice:
      log "Push Choice -> " & $inst.valTarget
      pushBacktrack(inst.valTarget, false, false)
      inc instructionIdx
      
    of opCommit:
      if backtrackStack.len > 0:
        let frame = backtrackStack.pop()
        if frame.isLookahead:
           if frame.invertLookahead:
             log "Neg Lookahead Match (Fail)"
             recordFailure("Neg Lookahead Match")
             triggerFail()
           else:
             log "Pos Lookahead Match (Success)"
             ctx.cursorPos = frame.cursorPos
             captureStartStack.setLen(frame.capStackLen)
             callStack.setLen(frame.callStackLen)
             labelStack.setLen(frame.labelStackLen)
             instructionIdx = frame.resumeIdx
        else:
           instructionIdx = inst.valTarget
      else:
        return VmResult(success: false)

    of opFail: 
      triggerFail()

    of opPeek, opReject:
      let isInverted = (inst.op != opPeek)
      log "Lookahead -> " & $inst.valTarget
      pushBacktrack(inst.valTarget, true, isInverted)
      inc instructionIdx

    of opCall:
      callStack.add CallFrame(returnIdx: instructionIdx + 1)
      instructionIdx = inst.valTarget

    of opReturn:
      if callStack.len > 0: instructionIdx = callStack.pop().returnIdx
      else: break 

    of opPushErrLabel:
      labelStack.add(glyph.strPool[inst.valStrIdx])
      inc instructionIdx

    of opPopErrLabel:
      if labelStack.len > 0: discard labelStack.pop()
      inc instructionIdx

  VmResult(success: true, matchLen: ctx.cursorPos)
