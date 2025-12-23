import sigil/sigir/[types, combinators, linker]

type
  Grammar* = ref object
    lib*: ParserLibrary

func newGrammar*(): Grammar =
  Grammar(lib: initLibrary())

# Defining a rule (without any sort of forward declaration)
proc define*(g: Grammar, name: string, builder: ParserBuilder): ParserBuilder =
  var p = builder
  p.name = name
  p.id = "rule_" & name
  
  # Ensure the rule ends with opReturn so the VM pops the call stack
  if p.instructions.len > 0 and p.instructions[^1].op != opReturn:
    p.instructions.add Instruction(op: opReturn)
  
  g.lib.add(p)
  
  # Return a call to the rule so it can be used elsewhere
  return call(p.id)

# Forward Declaration
proc forward*(g: Grammar, name: string): ParserBuilder =
  # Returns a call to a forward-declared rule
  return call("rule_" & name)

# Implementation
proc implement*(g: Grammar, name: string, builder: ParserBuilder) =
  # Implements the logic for a forward-declared rule. No real difference from
  # `define` besides for the fact it doesn't return a call
  discard g.define(name, builder)

# Compilation
proc compile*(g: Grammar, entryRule: ParserBuilder): seq[Instruction] =
  var entry = entryRule
  entry.instructions.add Instruction(op: opReturn)
  link(entry, g.lib)

proc compile*(g: Grammar, entryRule: string): seq[Instruction] =
  # Convenience overload to compile starting from a named rule
  compile(g, call(entryRule))