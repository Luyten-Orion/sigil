import sigil

type
  OpCode* = enum
    # Matching
    opChar, opSet, opAny, opStr
    # Exclusion
    opExceptChar, opExceptSet
    # Control flow
    opJump, opChoice, opCommit, opFail
    # Lookahead
    opPeek,   # Positive lookahead
    opReject  # Negative lookahead
    # Subroutines
    opCall, opReturn
    # Captures
    opCapPushPos, opCapPopPos
    # Actions
    opAction
    # Error reporting
    opPushErrLabel, opPopErrLabel

  Instruction* = object
    case op*: OpCode
    of opChar, opExceptChar: valChar*: char
    of opSet, opExceptSet:   valSetIdx*: int
    of opStr, opPushErrLabel: valStrIdx*: int
    of opJump, opChoice, opCommit, opCall, opPeek, opReject: valTarget*: int
    of opAction: valActionIdx*: int
    else: discard

  # The executable program
  Glyph*[C: Ctx] = object
    insts*: seq[Instruction]
    strPool*: seq[string]
    setPool*: seq[set[char]]
    actionPool*: seq[ActionProc[C]]