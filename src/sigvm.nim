import std/[
  strutils, sets
]
import sigil
import sigil/sigir/stypes


# Friendly-ish default error reporting
template prettyChar(c: char): string = escape($c, "", "")

func prettySet(s: set[char]): string =
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
        if start == stop: ranges.add(prettyChar(start))
        elif ord(stop) == ord(start) + 1:
           ranges.add(prettyChar(start)); ranges.add(prettyChar(stop))
        else: ranges.add(prettyChar(start) & "-" & prettyChar(stop))
        inRange = false
  if inRange:
    let stop = '\255'
    if start == stop: ranges.add(prettyChar(start))
    else: ranges.add(prettyChar(start) & "-" & prettyChar(stop))
  return "[" & ranges.join("") & "]"


type
  BacktrackFrame = object
    resumeIdx: int
    cursorPos: int
    capStackLen: int
    finalCapLen: int
    callStackLen: int
    labelStackLen: int
    isLookahead: bool
    invertLookahead: bool

  CallFrame = object
    returnIdx: int

  VmResult* = object
    success*: bool
    matchLen*: int
    captures*: seq[string]
    furthestFailureIdx*: int
    # TODO: Add friendlier error reporting
    expectedTerminals*: seq[string]
    foundTerminal*: string


proc run*[C: Ctx](
  glyph: Glyph[C],
  input: string,
  ctx: var C,
  debug = false
): VmResult =
  var
    instructionIdx = 0
    inputCursor = 0
    backtrackStack: seq[BacktrackFrame]
    callStack: seq[CallFrame]
    
    captureStartStack: seq[int]
    finalCaptures: seq[string]

    labelStack: seq[string]

    furthestFailureIdx = -1
    failuresAtMax: HashSet[string]

  template log(msg: string) =
    if debug: echo "[Inst: ", instructionIdx, " Cursor: ", inputCursor, "] ", msg

  template recordFailure(lowLevelMsg: string) =
    let finalMsg = if labelStack.len > 0: labelStack[^1] else: lowLevelMsg

    if inputCursor > furthestFailureIdx:
      # Deepest failure is likely the most correct path
      furthestFailureIdx = inputCursor
      failuresAtMax.clear()
      failuresAtMax.incl(finalMsg)
    elif inputCursor == furthestFailureIdx:
      # Same depth, record in the set
      failuresAtMax.incl(finalMsg)

  template triggerFail() =
    if backtrackStack.len > 0:
      let frame = backtrackStack.pop()

      if frame.isLookahead:
        if frame.isInverted:
          log "Negative lookahead no matched (success)"
          instructionIdx = frame.resumeIdx
          inputCursor = frame.cursorPos
          captureStartStack.setLen(frame.capStackLen)
          finalCaptures.setLen(frame.finalCapLen)
          callStack.setLen(frame.callStackLen)
          labelStack.setLen(frame.labelStackLen) 
          log "Resuming at " & $instructionIdx
        else:
          log "Positive lookahead no matched (fail)"
          recordFailure("Positive lookahead no matched (fail)")
          triggerFail()
      else:
        instructionIdx = frame.resumeIdx
        inputCursor = frame.cursorPos
        captureStartStack.setLen(frame.capStackLen)
        finalCaptures.setLen(frame.finalCapLen)
        callStack.setLen(frame.callStackLen)
        labelStack.setLen(frame.labelStackLen) 
        log "Backtracking to " & $instructionIdx
    else:
      log "Hard Fail"
      var errs: seq[string]
      for e in failuresAtMax: errs.add(e)
      
      let found = block:
        if furthestFailureIdx >= input.len: "End of Input"
        else: "`" & prettyChar(input[furthestFailureIdx]) & "`"

      return VmResult(
        success: false, 
        furthestFailureIdx: furthestFailureIdx, 
        expectedTerminals: errs,
        foundTerminal: found
      )

  while instructionIdx < glyph.insts.len:
    let inst = glyph.insts[instructionIdx]
    
    case inst.op
    # Err ops
    of opPushErrLabel:
      labelStack.add(glyph.strPool[inst.valStrIdx])
      inc instructionIdx
      
    of opPopErrLabel:
      if labelStack.len > 0:
        discard labelStack.pop()
      inc instructionIdx

    # Match
    of opChar:
      if inputCursor < input.len and input[inputCursor] == inst.valChar:
        inc inputCursor; inc instructionIdx
      else:
        recordFailure("'" & prettyChar(inst.valChar) & "'")
        triggerFail()

    of opSet:
      if inputCursor < input.len and input[inputCursor] in glyph.setPool[inst.valSetIdx]:
        inc inputCursor; inc instructionIdx
      else:
        recordFailure(prettySet(glyph.setPool[inst.valSetIdx]))
        triggerFail()

    of opStr:
      let s = glyph.strPool[inst.valStrIdx]
      if inputCursor + s.len <= input.len and input[inputCursor ..< inputCursor + s.len] == s:
        inputCursor += s.len; inc instructionIdx
      else:
        recordFailure(escape(s))
        triggerFail()

    of opAny:
      if inputCursor < input.len:
        inc inputCursor; inc instructionIdx
      else:
        recordFailure("any character")
        triggerFail()

    # Exclusion
    of opExceptChar:
      if inputCursor < input.len and input[inputCursor] != inst.valChar:
        log "Matched ExceptChar ('" & $inst.valChar & "')"
        inc inputCursor; inc instructionIdx
      else:
        recordFailure("anything but '" & prettyChar(inst.valChar) & "'")
        triggerFail()

    of opExceptSet:
      if inputCursor < input.len and input[inputCursor] notin glyph.setPool[inst.valSetIdx]:
        log "Matched ExceptSet"
        inc inputCursor; inc instructionIdx
      else:
        recordFailure("anything but '" & prettySet(glyph.setPool[inst.valSetIdx]) & "'")
        triggerFail()

    of opExceptStr:
      let s = glyph.strPool[inst.valStrIdx]
      if inputCursor + s.len <= input.len and input[inputCursor ..< inputCursor + s.len] == s:
         recordFailure("anything but " & escape(s))
         triggerFail()
      elif inputCursor < input.len:
         log "Matched ExceptString (\"" & s & "\")"
         inc inputCursor; inc instructionIdx
      else:
         # EOF
         recordFailure("any character")
         triggerFail()

    # Actions
    of opAction:
      # Execute user defined code with the context and current captures
      let act = glyph.actionPool[inst.valActionIdx]

      let ok = act(ctx, finalCaptures)
      if ok:
        log "Action Succeeded"
        finalCaptures.setLen(0)
        inc instructionIdx
      else:
        log "Action Failed (User code returned false)"
        # Do backtracking logic
        # TODO: Fatal error, how?
        # TODO: Make it so failed action returns error message?
        recordFailure("Action Failed (User code returned false)")
        triggerFail()

    # Control flow
    of opJump:
      instructionIdx = inst.valTarget

    of opChoice:
      log "Push Choice -> " & $inst.valTarget
      backtrackStack.add BacktrackFrame(
        resumeIdx: inst.valTarget, 
        cursorPos: inputCursor, 
        capStackLen: captureStartStack.len,
        finalCapLen: finalCaptures.len,
        callStackLen: callStack.len,
        labelStackLen: labelStack.len
      )
      inc instructionIdx

    of opCommit:
      if backtrackStack.len > 0:
        let frame = backtrackStack.pop()

        if frame.isLookahead:
          if frame.invertLookahead:
            log "Negative lookahead matched (fail)"
            recordFailure("Negative lookahead matched (fail)")
            triggerFail()
          else:
            log "Positive lookahead matched (success)"
            inputCursor = frame.cursorPos
            captureStartStack.setLen(frame.capStackLen)
            finalCaptures.setLen(frame.finalCapLen)
            callStack.setLen(frame.callStackLen)
            labelStack.setLen(frame.labelStackLen)
            instructionIdx = frame.resumeIdx
        else:
          instructionIdx = inst.valTarget
      else:
        return VmResult(success: false)

    of opFail:
      triggerFail()

# Lookahead
    of opPeek, opReject:
      let isInverted = (inst.op != opPeek)
      log "Start Lookahead -> " & $inst.valTarget & " Inverted: " & $isInverted
      
      backtrackStack.add BacktrackFrame(
        resumeIdx: inst.valTarget,
        cursorPos: inputCursor, 
        capStackLen: captureStartStack.len,
        finalCapLen: finalCaptures.len,
        callStackLen: callStack.len,
        labelStackLen: labelStack.len,
        isLookahead: true,
        invertLookahead: isInverted
      )

      inc instructionIdx

    # Subroutines
    of opCall:
      callStack.add CallFrame(returnIdx: instructionIdx + 1)
      instructionIdx = inst.valTarget
    
    of opReturn:
      if callStack.len > 0: instructionIdx = callStack.pop().returnIdx
      else: break

    # Captures
    of opCapPushPos:
      captureStartStack.add(inputCursor)
      inc instructionIdx

    of opCapPopPos:
      if captureStartStack.len > 0:
        let start = captureStartStack.pop()
        finalCaptures.add input[start..<inputCursor]
        inc instructionIdx
      else:
        return VmResult(success: false)

  VmResult(success: true, matchLen: inputCursor, captures: finalCaptures)