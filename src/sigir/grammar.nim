import sigil/sigir/[types, combinators, linker]

type
  Grammar*[C: Ctx] = ref object
    lib*: ParserLibrary[C]

func newGrammar*[C: Ctx](): Grammar[C] =
  Grammar[C](lib: initLibrary[C]())

# Helpers (to infer the context using a grammar type)
func match*[C: Ctx](g: Grammar[C], c: char): ParserBuilder[C] =
  combinators.match[C](c)

func match*[C: Ctx](g: Grammar[C], s: set[char]): ParserBuilder[C] =
  combinators.match[C](s)

func match*[C: Ctx](g: Grammar[C], s: string): ParserBuilder[C] =
  combinators.match[C](s)

func matchExcept*[C: Ctx](g: Grammar[C], c: char): ParserBuilder[C] =
  combinators.matchExcept[C](c)

func matchExcept*[C: Ctx](g: Grammar[C], s: set[char]): ParserBuilder[C] =
  combinators.matchExcept[C](s)

func matchExcept*[C: Ctx](g: Grammar[C], s: string): ParserBuilder[C] =
  combinators.matchExcept[C](s)

# Defining a rule (without any sort of forward declaration)
proc define*[C: Ctx](
  g: Grammar[C],
  name: string,
  builder: ParserBuilder[C]
): ParserBuilder[C] =
  var p = builder
  p.name = name
  p.id = "rule(" & name & ")"
  
  # Ensure the rule ends with opReturn so the VM pops the call stack
  if p.instructions.len > 0 and p.instructions[^1].op != opReturn:
    p.instructions.add Instruction[C](op: opReturn)
  
  g.lib.add(p)
  
  # Return a call to the rule so it can be used elsewhere
  return call[C](p.id)

# Forward Declaration
proc forward*[C: Ctx](g: Grammar[C], name: string): ParserBuilder[C] =
  # Returns a call to a forward-declared rule
  return call[C]("rule(" & name & ")")

# Implementation
proc implement*[C: Ctx](g: Grammar[C], name: string, builder: ParserBuilder[C]) =
  # Implements the logic for a forward-declared rule. No real difference from
  # `define` besides for the fact it doesn't return a call
  discard g.define[:C](name, builder)

# Compilation
proc compile*[C: Ctx](g: Grammar[C], entryRule: ParserBuilder[C]): Glyph[C] =
  var entry = entryRule
  entry.instructions.add Instruction[C](op: opReturn)
  link[C](entry, g.lib)

proc compile*[C: Ctx](g: Grammar[C], entryRule: string): Glyph[C] =
  # Convenience overload to compile starting from a named rule
  compile[C](g, call[C](entryRule))