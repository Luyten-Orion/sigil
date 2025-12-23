import sigil/sigir

type
  BacktrackFrame = object
    resumeIdx: int
    cursorPos: int
    capStackLen: int
    finalCapLen: int
    callStackLen: int

  CallFrame = object
    returnIdx: int

  VmResult* = object
    success*: bool
    matchLen*: int
    captures*: seq[string]

proc run*(instructions: seq[Instruction], input: string, debug = false): VmResult =
  var
    instructionIdx = 0
    inputCursor = 0
    backtrackStack: seq[BacktrackFrame]
    callStack: seq[CallFrame]
    
    captureStartStack: seq[int]
    finalCaptures: seq[string]

  template log(msg: string) =
    if debug: echo "[Inst: ", instructionIdx, " Cursor: ", inputCursor, "] ", msg

  template triggerFail() =
    if backtrackStack.len > 0:
      let frame = backtrackStack.pop()
      instructionIdx = frame.resumeIdx
      inputCursor = frame.cursorPos
      captureStartStack.setLen(frame.capStackLen)
      finalCaptures.setLen(frame.finalCapLen)
      callStack.setLen(frame.callStackLen)
      log "Backtracking to " & $instructionIdx
    else:
      log "Hard Fail"
      return VmResult(success: false)

  while instructionIdx < instructions.len:
    let inst = instructions[instructionIdx]
    
    case inst.op
    # Match
    of opChar:
      if inputCursor < input.len and input[inputCursor] == inst.valChar:
        inc inputCursor; inc instructionIdx
      else: triggerFail()
    of opSet:
      if inputCursor < input.len and input[inputCursor] in inst.valSet:
        inc inputCursor; inc instructionIdx
      else: triggerFail()
    of opStr:
      let s = inst.valStr
      if inputCursor + s.len <= input.len and input[inputCursor ..< inputCursor + s.len] == s:
        inputCursor += s.len; inc instructionIdx
      else: triggerFail()
    of opAny:
      if inputCursor < input.len:
        inc inputCursor; inc instructionIdx
      else: triggerFail()

    # Exclusion
    of opExceptChar:
      if inputCursor < input.len and input[inputCursor] != inst.valChar:
        log "Matched ExceptChar ('" & $inst.valChar & "')"
        inc inputCursor; inc instructionIdx
      else:
        triggerFail()

    of opExceptSet:
      if inputCursor < input.len and input[inputCursor] notin inst.valSet:
        log "Matched ExceptSet"
        inc inputCursor; inc instructionIdx
      else:
        triggerFail()

    of opExceptStr:
      let s = inst.valStr
      # Check if we are AT the forbidden string
      if inputCursor + s.len <= input.len and input[inputCursor ..< inputCursor + s.len] == s:
         # We found the forbidden string -> FAIL
         triggerFail()
      elif inputCursor < input.len:
         # We are NOT at the forbidden string, and have chars left -> Match 1 char
         log "Matched ExceptString (\"" & s & "\")"
         inc inputCursor; inc instructionIdx
      else:
         # EOF
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
        callStackLen: callStack.len # <--- SAVE THIS
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
      if callStack.len > 0:
        instructionIdx = callStack.pop().returnIdx
      else:
        break

    of opRuleCall:
      raise newException(ValueError, "VM Error: Encountered opRuleCall. Did you forget to link()?")

    # Captures
    of opCapPushPos:
      captureStartStack.add(inputCursor)
      inc instructionIdx

    of opCapPopPos:
      if captureStartStack.len > 0:
        let start = captureStartStack.pop()
        finalCaptures.add input[start ..< inputCursor]
        inc instructionIdx
      else:
        return VmResult(success: false)

  return VmResult(success: true, matchLen: inputCursor, captures: finalCaptures)