import sigil/sigir/[types, utils]

# Basic constructor
template parser*[C: Ctx](name: string): ParserBuilder[C] =
  const info = instantiationInfo()
  const prefix = sanitize(info.filename)
  initParser[C](prefix & "_" & name, name)

# Helper for pools
func getOrAdd[T: string | set[char]](pool: var seq[T], val: T): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high


func mergePools[C](dest: var ParserBuilder[C], src: ParserBuilder[C]): seq[Instruction[C]] =
  result = src.instructions
  
  let
    strOffset = dest.localStrPool.len
    setOffset = dest.localSetPool.len
  
  dest.localStrPool.add(src.localStrPool)
  dest.localSetPool.add(src.localSetPool)
  
  # Remap indices in B's instructions
  for inst in result.mitems:
    if inst.op in {opStr, opExceptStr, opPushErrLabel, opRuleCall}:
      inst.valStrIdx += strOffset
    elif inst.op in {opSet, opExceptSet}:
      inst.valSetIdx += setOffset


# Primitives
func match*[C: Ctx](c: char): ParserBuilder[C] =
  result = initParser[C]("match_char(" & $c & ")", "match_char(" & $c & ")")
  result.instructions.add Instruction[C](op: opChar, valChar: c)

func match*[C: Ctx](s: set[char]): ParserBuilder[C] =
  result = initParser[C]("match_set(" & $s & ")", "match_set(" & $s & ")")
  let idx = result.localSetPool.getOrAdd(s)
  result.instructions.add Instruction[C](op: opSet, valSetIdx: idx)

func match*[C: Ctx](s: string): ParserBuilder[C] =
  result = initParser[C]("match_str(" & s & ")", "match_str(" & s & ")")
  let idx = result.localStrPool.getOrAdd(s)
  result.instructions.add Instruction[C](op: opStr, valStrIdx: idx)

# Match except
func matchExcept*[C: Ctx](c: char): ParserBuilder[C] =
  result = initParser[C]("except_char(" & $c & ")", "except_char(" & $c & ")")
  result.instructions.add Instruction[C](op: opExceptChar, valChar: c)

func matchExcept*[C: Ctx](s: set[char]): ParserBuilder[C] =
  result = initParser[C]("except_set(" & $s & ")", "except_set(" & $s & ")")
  let idx = result.localSetPool.getOrAdd(s)
  result.instructions.add Instruction[C](op: opExceptSet, valSetIdx: idx)

func matchExcept*[C: Ctx](s: string): ParserBuilder[C] =
  result = initParser[C]("except_str(" & s & ")", "except_str(" & s & ")")
  let idx = result.localStrPool.getOrAdd(s)
  result.instructions.add Instruction[C](op: opExceptStr, valStrIdx: idx)


# Combinators
func `and`*[C: Ctx](a, b: ParserBuilder[C]): ParserBuilder[C] =
  result = initParser[C]("and(" & a.id & "," & b.id & ")", "and(" & a.name & "," & b.name & ")")
  result.instructions.add(result.mergePools(a))
  # TODO: Just make a `merge` helper?
  var bInsts = result.mergePools(b)
  shiftAddresses(bInsts, a.instructions.len)
  result.instructions.add(bInsts)


func `or`*[C: Ctx](a, b: ParserBuilder[C]): ParserBuilder[C] =
  result = initParser[C]("or(" & a.id & "," & b.id & ")", "or(" & a.name & "," & b.name & ")")
  
  let
    lenA = a.instructions.len
    lenB = b.instructions.len
    startOfB = 1 + lenA + 1
    endOfAll = startOfB + lenB

  var
    aInsts = result.mergePools(a)
    bInsts = result.mergePools(b)

  shiftAddresses(aInsts, 1)
  shiftAddresses(bInsts, startOfB)

  result.instructions.add Instruction[C](op: opChoice, valTarget: startOfB)
  result.instructions.add(aInsts)
  result.instructions.add Instruction[C](op: opCommit, valTarget: endOfAll)
  result.instructions.add(bInsts)


func many0*[C: Ctx](p: ParserBuilder[C]): ParserBuilder[C] =
  result = initParser[C]("many0(" & p.id & ")", "many0(" & p.name & ")")
  let lenP = p.instructions.len   
  let endLabel = lenP + 2

  result.instructions.add Instruction[C](op: opChoice, valTarget: endLabel)
  
  var pInsts = result.mergePools(p)
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction[C](op: opCommit, valTarget: 0)


func many1*[C: Ctx](p: ParserBuilder[C]): ParserBuilder[C] =
  result = p and many0(p)
  result.id = "many1(" & p.id & ")"
  result.name = "many1(" & p.name & ")"


func optional*[C: Ctx](p: ParserBuilder[C]): ParserBuilder[C] =
  result = initParser[C]("opt(" & p.id & ")", "opt(" & p.name & ")")
  let lenP = p.instructions.len
  let endLabel = 1 + lenP + 1
  
  result.instructions.add Instruction[C](op: opChoice, valTarget: endLabel)
  
  var pInsts = result.mergePools(p)
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction[C](op: opCommit, valTarget: endLabel)


func capture*[C: Ctx](p: ParserBuilder[C]): ParserBuilder[C] =
  result = initParser[C]("cap(" & p.id & ")", "cap(" & p.name & ")")
  
  result.instructions.add Instruction[C](op: opCapPushPos)
  
  var pInsts = result.mergePools(p)
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)
  
  result.instructions.add Instruction[C](op: opCapPopPos)


func action*[C: Ctx](p: ParserBuilder[C], act: ActionProc[C]): ParserBuilder[C] =
  result = initParser[C]("act(" & p.id & ")", "act(" & p.name & ")")
  result.instructions.add(result.mergePools(p))
  result.instructions.add Instruction[C](op: opAction, actionFunc: act)


func sepBy1*[C: Ctx](p, sep: ParserBuilder[C]): ParserBuilder[C] =
  # p (sep p)*
  result = p and many0(sep and p)
  result.id = "sep(" & p.id & ")_by(" & sep.id & ")_1"
  result.name = "sep(" & p.name & ")_by(" & sep.name & ")_1"


func sepBy*[C: Ctx](p, sep: ParserBuilder[C]): ParserBuilder[C] =
  # optional(sepBy1)
  result = optional(sepBy1(p, sep))
  result.id = "sep(" & p.id & ")_by(" & sep.id & ")"
  result.name = "sep(" & p.name & ")_by(" & sep.name & ")"


# Call types
func call*[C: Ctx](name: string): ParserBuilder[C] =
  result = initParser[C]("call(" & name & ")", "call(" & name & ")")
  let idx = result.localStrPool.getOrAdd(name)
  result.instructions.add Instruction[C](op: opRuleCall, valStrIdx: idx)


func smartCall*[C: Ctx](p: ParserBuilder[C]): ParserBuilder[C] =
  if p.instructions.len < 6: p else: call[C](p.id)


# Error label combinator
func expect*[C: Ctx](p: ParserBuilder[C], msg: string): ParserBuilder[C] =
  # Wraps a given parser in a label
  result = initParser[C](
    "expect(id: `" & p.id & "`,msg: `" & msg & "`)",
    "expect(id: `" & p.name & "`,msg: `" & msg & "`)"
  )
  var pInsts = result.mergePools(p)
  let idx = result.localStrPool.getOrAdd(msg)
  result.instructions.add Instruction[C](op: opPushErrLabel, valStrIdx: idx)  

  # Shift by 1 because of `opPushErrLabel`
  shiftAddresses(pInsts, 1)
  result.instructions.add(pInsts)

  result.instructions.add Instruction[C](op: opPopErrLabel)