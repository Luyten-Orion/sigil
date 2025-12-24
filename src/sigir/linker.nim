import sigil
import std/[tables]
import sigil/sigir/[stypes, utils]


# TODO: Move into `utils`
func getOrAdd[T: string | set[char]](pool: var seq[T], val: T): int =
  result = pool.find(val)
  if result == -1:
    pool.add(val)
    result = pool.high


func appendAndRemap*[C: Ctx](target: var Glyph[C], src: ParserBuilder[C]): int =
  # Returns the index of the first instruction in `src`
  result = target.insts.len
  
  for inst in src.instructions:
    var newInst = inst
    
    # Local Pool -> Global Pool
    if inst.op in {opStr, opExceptStr, opPushErrLabel, opRuleCall}:
      let val = src.localStrPool[inst.valStrIdx]
      newInst.valStrIdx = target.strPool.getOrAdd(val)
      
    elif inst.op in {opSet, opExceptSet}:
      let val = src.localSetPool[inst.valSetIdx]
      newInst.valSetIdx = target.setPool.getOrAdd(val)
      
    target.insts.add(newInst)


func link*[C: Ctx](entry: ParserBuilder[C], lib: ParserLibrary[C]): Glyph[C] =
  var ruleLocations: Table[string, int]

  # Entrypoint
  discard result.appendAndRemap(entry)
  
  var pendingIp = 0
  while pendingIp < result.insts.len: # iterate the Glyph's code
    let inst = result.insts[pendingIp]
    
    if inst.op == opRuleCall:
      # Use the remapped index to find the name in the global pool
      let requiredId = result.strPool[inst.valStrIdx]
      var targetIp = 0

      if requiredId in ruleLocations:
        targetIp = ruleLocations[requiredId]
      else:
        if requiredId notin lib.rules:
           raise newException(ValueError, "Linker Error: Rule '" & requiredId & "' missing.")
        
        targetIp = result.insts.len
        ruleLocations[requiredId] = targetIp

        # Create a temp copy of the builder so we can shift addresses
        # without mutating the original library rule
        var ruleBuilder = lib.rules[requiredId]
        shiftAddresses(ruleBuilder.instructions, targetIp)
        
        # Pass the BUILDER (with local pools) to the remapper
        discard result.appendAndRemap(ruleBuilder)
      
      # Patch: opRuleCall -> opCall
      result.insts[pendingIp] = Instruction[C](op: opCall, valTarget: targetIp)
      
    pendingIp.inc