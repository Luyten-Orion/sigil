import sigil/sigir/[types, utils]

# Basic constructor
template parser*(userGivenName: string): ParserBuilder =
  const info = instantiationInfo()
  const prefix = sanitize(info.filename)
  initParser(prefix & "_" & userGivenName, userGivenName)

# Primitives
func match*(c: char): ParserBuilder =
  result = initParser("match_char(" & $c & ")", "match_char(" & $c & ")")
  result.instructions.add Instruction(op: opChar, valChar: c)

func match*(s: set[char]): ParserBuilder =
  result = initParser("match_set(" & $s & ")", "match_set(" & $s & ")")
  result.instructions.add Instruction(op: opSet, valSet: s)

func match*(s: string): ParserBuilder =
  result = initParser("match_str(" & s & ")", "match_str(" & s & ")")
  result.instructions.add Instruction(op: opStr, valStr: s)

# Match except
func matchExcept*(c: char): ParserBuilder =
  result = initParser("except_char(" & $c & ")", "except_char(" & $c & ")")
  result.instructions.add Instruction(op: opExceptChar, valChar: c)

func matchExcept*(s: set[char]): ParserBuilder =
  result = initParser("except_set(" & $s & ")", "except_set(" & $s & ")")
  result.instructions.add Instruction(op: opExceptSet, valSet: s)

func matchExcept*(s: string): ParserBuilder =
  result = initParser("except_str(" & s & ")", "except_str(" & s & ")")
  result.instructions.add Instruction(op: opExceptStr, valStr: s)


# Combinators
func `and`*(a, b: ParserBuilder): ParserBuilder =
  result = initParser("and(" & a.id & "," & b.id & ")", "and(" & a.name & "," & b.name & ")")
  result.instructions.add(a.instructions)
  
  var bInsts = b.instructions
  shiftAddresses(bInsts, a.instructions.len)
  result.instructions.add(bInsts)


func `or`*(a, b: ParserBuilder): ParserBuilder =
  result = initParser("or(" & a.id & "," & b.id & ")", "or(" & a.name & "," & b.name & ")")
  
  let lenA = a.instructions.len
  let lenB = b.instructions.len
  let startOfB = 1 + lenA + 1
  let endOfAll = startOfB + lenB

  result.instructions.add Instruction(op: opChoice, valTarget: startOfB)
  
  var aInsts = a.instructions
  shiftAddresses(aInsts, 1)
  result.instructions.add(aInsts)
  
  result.instructions.add Instruction(op: opCommit, valTarget: endOfAll)
  
  var bInsts = b.instructions
  shiftAddresses(bInsts, startOfB)
  result.instructions.add(bInsts)


func many0*(p: ParserBuilder): ParserBuilder =
  result = initParser("many0(" & p.id & ")", "many0(" & p.name & ")")
  let lenP = p.instructions.len   
  let endLabel = lenP + 2

  result.instructions.add Instruction(op: opChoice, valTarget: endLabel)
  
  var pInsts = p.instructions
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction(op: opCommit, valTarget: 0)


func many1*(p: ParserBuilder): ParserBuilder =
  result = p and many0(p)
  result.id = "many1(" & p.id & ")"
  result.name = "many1(" & p.name & ")"


func optional*(p: ParserBuilder): ParserBuilder =
  result = initParser("opt(" & p.id & ")", "opt(" & p.name & ")")
  let lenP = p.instructions.len
  let endLabel = 1 + lenP + 1
  
  result.instructions.add Instruction(op: opChoice, valTarget: endLabel)
  
  var pInsts = p.instructions
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction(op: opCommit, valTarget: endLabel)


func capture*(p: ParserBuilder): ParserBuilder =
  result = initParser("cap(" & p.id & ")", "cap(" & p.name & ")")
  
  result.instructions.add Instruction(op: opCapPushPos)
  
  var pInsts = p.instructions
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction(op: opCapPopPos)


func sepBy1*(p, sep: ParserBuilder): ParserBuilder =
  # p (sep p)*
  result = p and many0(sep and p)
  result.id = "sep(" & p.id & ")_by(" & sep.id & ")_1"
  result.name = "sep(" & p.name & ")_by(" & sep.name & ")_1"


func sepBy*(p, sep: ParserBuilder): ParserBuilder =
  # optional(sepBy1)
  result = optional(sepBy1(p, sep))
  result.id = "sep(" & p.id & ")_by(" & sep.id & ")"
  result.name = "sep(" & p.name & ")_by(" & sep.name & ")"


# Call types
func call*(name: string): ParserBuilder =
  result = initParser("call(" & name & ")", "call(" & name & ")")
  result.instructions.add Instruction(op: opRuleCall, valStr: name)


func smartCall*(p: ParserBuilder): ParserBuilder =
  if p.instructions.len < 6: p else: call(p.id)