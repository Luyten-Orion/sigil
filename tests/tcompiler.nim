import sigil
import sigil/codex
import sigil/sigir
import sigil/combinators
import sigil/sigir/compiler

type 
  TestCtx = object
  TestGroups = enum tgNone, tgVal
  
  # fully generic alias: Context, Groups, Atom(char), LineTracking(false)
  RB = RuleBuilder[TestCtx, TestGroups, char, false]

block CompileChar:
  let p = RB.define("Main", RB.match('x'))
  let glyph = compile(p)
   
  # Expected: [opAtom 'x', opReturn]
  doAssert glyph.insts.len == 2
  doAssert glyph.insts[0].op == opAtom
  doAssert glyph.insts[0].valAtom == 'x'
  doAssert glyph.insts[1].op == opReturn

block CompileChoice:
  let p = RB.define("Main", RB.match('a') or RB.match('b'))
  let glyph = compile(p)
   
  # Expected Layout:
  # 0: opChoice -> Jump to 3 (Else)
  # 1: opAtom 'a'
  # 2: opCommit -> Jump to 4 (End)
  # 3: opAtom 'b'
  # 4: opReturn
  
  doAssert glyph.insts[0].op == opChoice
  let elseTarget = glyph.insts[0].valTarget
   
  doAssert glyph.insts[1].op == opAtom
  doAssert glyph.insts[1].valAtom == 'a'
   
  doAssert glyph.insts[2].op == opCommit
  let endTarget = glyph.insts[2].valTarget
   
  # Verify Jump Targets
  doAssert elseTarget == 3
  doAssert glyph.insts[elseTarget].op == opAtom
  doAssert glyph.insts[elseTarget].valAtom == 'b'
   
  doAssert endTarget == 4
  doAssert glyph.insts[endTarget].op == opReturn

block CompileCalls:
  let sub = RB.define("Sub", RB.match('b'))
  let main = RB.define("Main", RB.match('a') and call(sub))
   
  let glyph = compile(main)
   
  # Expected Layout:
  # --- Main ---
  # 0: opAtom 'a'
  # 1: opCall -> Jump to Sub
  # 2: opReturn
  # --- Sub ---
  # 3: opAtom 'b'
  # 4: opReturn
  
  doAssert glyph.insts[0].op == opAtom
  doAssert glyph.insts[0].valAtom == 'a'

  doAssert glyph.insts[1].op == opCall
  let callTarget = glyph.insts[1].valTarget
  
  # Verify Linker Logic
  doAssert callTarget == 3
  doAssert glyph.insts[callTarget].op == opAtom
  doAssert glyph.insts[callTarget].valAtom == 'b'
  doAssert glyph.insts[callTarget+1].op == opReturn

block CompilePipeline:
  # Test the new Siphon architecture
  let p = RB.define("Pipe", RB.match('z').siphon(tgVal))
  let glyph = compile(p)

  # Expected Layout:
  # 0: opCapPushPos   (Start Capture)
  # 1: opAtom 'z'     (Body)
  # 2: opSiphonPop    (End Capture -> Store)
  # 3: opReturn

  doAssert glyph.insts[0].op == opCapPushPos
  doAssert glyph.insts[1].op == opAtom
  doAssert glyph.insts[1].valAtom == 'z'
  
  doAssert glyph.insts[2].op == opSiphonPop
  doAssert glyph.insts[2].siphonChannel == tgVal
  
  doAssert glyph.insts[3].op == opReturn