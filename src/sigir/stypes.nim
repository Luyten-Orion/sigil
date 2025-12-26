import sigil

type
  OpCode* = enum
    # Matching
    opAtom, opSet, opAny, opSeqAtom
    # Exclusion
    opExceptAtom, opExceptSet
    # Control flow
    opJump, opChoice, opCommit, opFail
    # Lookahead
    opPeek,   # Positive lookahead
    opReject  # Negative lookahead
    # Subroutines
    opCall, opReturn
    # Captures
    opCapPushPos, opSiphonPop
    # Actions
    opTransmute
    opAbsorb
    opScry
    # Error reporting
    opPushErrLabel, opPopErrLabel

  # TODO: Use the same `distinct` types we use for indexing in ctypes
  Instruction*[G: Ordinal, A: Atom] = object
    case op*: OpCode
    of opAtom, opExceptAtom: valAtom*: A
    of opSet, opExceptSet: valSetIdx*: int
    of opSeqAtom: valPoolIdx*: int
    of opPushErrLabel: valStrIdx*: int
    of opJump, opChoice, opCommit, opCall, opPeek, opReject: valTarget*: int
    of opSiphonPop: siphonChannel*: G
    of opTransmute:
      valTransmuteIdx*: int
      transmuteChannel*: G
    of opAbsorb: valAbsorbIdx*: int
    of opScry: valScryIdx*: int
    else: discard

  # The executable program
  Glyph*[C: Ctx, G: Ordinal, A: Atom, L: static bool] = object
    insts*: seq[Instruction[G, A]]
    strPool*: seq[string]
    atomPool*: seq[seq[A]]
    setPool*: seq[set[A]]
    transmutePool*: seq[TransmuteProc[C, G, A, L]]
    absorbPool*: seq[AbsorbProc[C, G, A, L]]
    scryPool*: seq[ScryProc[C, G, A, L]]