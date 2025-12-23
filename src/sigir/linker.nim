import std/[tables]
import sigil/sigir/[types, utils]

func link*(entry: ParserBuilder, lib: ParserLibrary): seq[Instruction] =
  var ruleLocations: Table[string, int]

  # Entrypoint
  result = entry.instructions
  
  var pendingIp = 0
  while pendingIp < result.len:
    let inst = result[pendingIp]
    if inst.op == opRuleCall:
      let requiredId = inst.valStr
      var targetIp = 0

      if requiredId in ruleLocations:
        targetIp = ruleLocations[requiredId]
      else:
        if requiredId notin lib.rules:
           raise newException(ValueError, "Linker Error: Rule '" & requiredId & "' is called but not in the Library.")
        
        targetIp = result.len
        ruleLocations[requiredId] = targetIp

        var body = lib.rules[requiredId].instructions
        shiftAddresses(body, targetIp)
        result.add(body)
      
      # Patch: opRuleCall("id") -> opCall(targetIp)
      result[pendingIp] = Instruction(op: opCall, valTarget: targetIp)
      
    pendingIp.inc