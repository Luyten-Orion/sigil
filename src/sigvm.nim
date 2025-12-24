import std/[
  strutils, sets
]
import sigil/sigir/types


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


proc run*[C](
  instructions: seq[Instruction[C]],
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

  while instructionIdx < instructions.len:
    let inst = instructions[instructionIdx]
    
    case inst.op
    # Err ops
    of opPushErrLabel:
      labelStack.add(inst.valStr)
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
      if inputCursor < input.len and input[inputCursor] in inst.valSet:
        inc inputCursor; inc instructionIdx
      else:
        recordFailure(prettySet(inst.valSet))
        triggerFail()

    of opStr:
      let s = inst.valStr
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
      if inputCursor < input.len and input[inputCursor] notin inst.valSet:
        log "Matched ExceptSet"
        inc inputCursor; inc instructionIdx
      else:
        recordFailure("anything but '" & prettySet(inst.valSet) & "'")
        triggerFail()

    of opExceptStr:
      let s = inst.valStr
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
      let ok = inst.actionFunc(ctx, finalCaptures)
      if ok:
        log "Action Succeeded"
        # Consume captured strings
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
        discard backtrackStack.pop()
        instructionIdx = inst.valTarget
      else:
        return VmResult(success: false)

    of opFail:
      triggerFail()

    # Subroutines
    of opCall:
      callStack.add CallFrame(returnIdx: instructionIdx + 1)
      instructionIdx = inst.valTarget
    
    of opReturn:
      if callStack.len > 0: instructionIdx = callStack.pop().returnIdx
      else: break

    of opRuleCall:
      raise newException(ValueError, "VM Error: Encountered opRuleCall. Did you forget to link()?")

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