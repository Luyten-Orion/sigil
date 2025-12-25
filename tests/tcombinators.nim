import sigil/combinators
import sigil/codex/ctypes

type
  TestCtx = object
  RB = RuleBuilder[TestCtx]

block BasicMatching:
  let p = RB.match('a')
  let c = p.codex[]
  let entry = c[p.root]
   
  doAssert entry.kind == vkCheckMatch
  doAssert entry.checkType == ckChar
  doAssert entry.valChar == 'a'

block SequenceAndStitching:
  let p1 = RB.match('a')
  let p2 = RB.match('b')
   
  let seqP = p1 and p2
  let c = seqP.codex[]
  let root = c[seqP.root]
   
  doAssert root.kind == vkSeq
  doAssert root.spineLen == 2
   
  let child1Idx = c[root.spineStart]
  let child2Idx = c[SpineIdx(root.spineStart.int + 1)]
   
  let child1 = c[child1Idx]
  let child2 = c[child2Idx]
   
  doAssert child1.kind == vkCheckMatch
  doAssert child1.valChar == 'a'
   
  doAssert child2.kind == vkCheckMatch
  doAssert child2.valChar == 'b'

block RecursionAndDefinitions:
  let ruleA = define(RB, "A")
  ruleA.implement(RB.match('a'))
   
  let p = call(ruleA)
  let c = p.codex[]
   
  let callNode = c[p.root]
  doAssert callNode.kind == vkCall
   
  let rDef = c[callNode.ruleIdx]
  doAssert rDef.name == "A"
   
  let entryNode = c[rDef.entry]
  doAssert entryNode.kind == vkCheckMatch
  doAssert entryNode.valChar == 'a'

block Lookaheads:
  let p = peek(RB.match('a'))
  let c = p.codex[]
  let root = c[p.root]
   
  doAssert root.kind == vkLookahead
  doAssert root.invert == false
   
  let innerIdx = root.lookaheadVerse
  let inner = c[innerIdx]
  doAssert inner.kind == vkCheckMatch
  doAssert inner.valChar == 'a'