import std/[tables]

type
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

  Instruction* = object
    case op*: OpCode
    of opChar, opExceptChar: valChar*: char
    of opSet, opExceptSet: valSet*: set[char]
    of opStr, opRuleCall, opExceptStr: valStr*: string
    of opJump, opChoice, opCommit, opCall: valTarget*: int
    else: discard

  ParserBuilder* = object
    id*: string
    name*: string
    instructions*: seq[Instruction]

  ParserLibrary* = object
    rules*: Table[string, ParserBuilder]

# Basic constructors
func initParser*(id, name: string): ParserBuilder =
  ParserBuilder(id: id, name: name)

func initLibrary*(): ParserLibrary =
  result.rules = initTable[string, ParserBuilder]()

func add*(lib: var ParserLibrary, p: ParserBuilder) =
  if p.id in lib.rules:
    raise newException(ValueError, "Library Error: Rule '" & p.id & "' already exists.")
  lib.rules[p.id] = p

func add*(lib: var ParserLibrary, other: ParserLibrary) =
  for id, p in other.rules: lib.add(p)