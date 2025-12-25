import sigil/combinators
import sigil/codex/ctypes
import sigil/sigir/compiler
import sigil/sigir/stypes

type TestCtx = object
type RB = RuleBuilder[TestCtx]

block CompileChar:
  let p = RB.define("Main", RB.match('x'))
  let glyph = compile(p)
   
  doAssert glyph.insts.len >= 2
  doAssert glyph.insts[0].op == opChar
  doAssert glyph.insts[0].valChar == 'x'
  doAssert glyph.insts[1].op == opReturn

block CompileChoice:
  let p = RB.define("Main", RB.match('a') or RB.match('b'))
  let glyph = compile(p)
   
  doAssert glyph.insts[0].op == opChoice
  let elseTarget = glyph.insts[0].valTarget
   
  doAssert glyph.insts[1].op == opChar
  doAssert glyph.insts[1].valChar == 'a'
   
  doAssert glyph.insts[2].op == opCommit
  let endTarget = glyph.insts[2].valTarget
   
  doAssert elseTarget == 3
  doAssert glyph.insts[elseTarget].op == opChar
  doAssert glyph.insts[elseTarget].valChar == 'b'
   
  doAssert endTarget == 4

block CompileCalls:
  let sub = RB.define("Sub", RB.match('b'))
  let main = RB.define("Main", RB.match('a') and call(sub))
   
  let glyph = compile(main)
   
  doAssert glyph.insts[1].op == opCall
  let callTarget = glyph.insts[1].valTarget
   
  doAssert callTarget == 3
  doAssert glyph.insts[callTarget].valChar == 'b'