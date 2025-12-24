import std/[tables]

type
  Ctx* = not (ref | void)
  # Accepts a mutable context and the currently captured strings
  ActionProc*[C: Ctx] = proc(ctx: var C, captures: seq[string]): bool {.nimcall.}

  OpCode* = enum
    # Matching ops
    opChar, opSet, opAny, opStr
    # Exclusion ops
    opExceptChar, opExceptSet, opExceptStr
    # Control flow
    opJump, opChoice, opCommit, opFail
    # Linking & Calls
    opRuleCall, opCall, opReturn
    # Captures
    opCapPushPos, opCapPopPos
    # Action (callbacks)
    opAction
    # Error reporting
    opPushErrLabel, opPopErrLabel

  Instruction*[C: Ctx] = object
    case op*: OpCode
    of opChar, opExceptChar: valChar*: char
    # Indexes into `Glyph.setPool`
    of opSet, opExceptSet: valSetIdx*: int
    # Indexes into `Glyph.strPool`
    of opStr, opRuleCall, opExceptStr, opPushErrLabel: valStrIdx*: int
    of opJump, opChoice, opCommit, opCall: valTarget*: int
    of opAction: actionFunc*: ActionProc[C]
    else: discard

  ParserBuilder*[C: Ctx] = object
    id*: string
    name*: string
    instructions*: seq[Instruction[C]]
    localStrPool*: seq[string]
    localSetPool*: seq[set[char]]

  ParserLibrary*[C: Ctx] = object
    rules*: Table[string, ParserBuilder[C]]

  Glyph*[C: Ctx] = object
    insts*: seq[Instruction[C]]
    strPool*: seq[string]
    setPool*: seq[set[char]]

# Basic constructors
func initParser*[C: Ctx](id, name: string): ParserBuilder[C] =
  ParserBuilder[C](id: id, name: name)

func initLibrary*[C: Ctx](): ParserLibrary[C] =
  result.rules = initTable[string, ParserBuilder[C]]()

# TODO: Maybe add an overload for converting instructions from one
# type, to another? We just need to verify that there are no
# action instructions.
func add*[C: Ctx](lib: var ParserLibrary[C], p: ParserBuilder[C]) =
  if p.id in lib.rules:
    raise newException(ValueError, "Library Error: Rule '" & p.id & "' already exists.")
  lib.rules[p.id] = p

func add*[C: Ctx](lib: var ParserLibrary[C], other: ParserLibrary[C]) =
  for id, p in other.rules: lib.add(p)