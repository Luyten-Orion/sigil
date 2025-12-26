import sigil
import sigil/codex
import sigil/combinators

type
  TestCtx = object
  TestGroups = enum tgNone
  # Define the specific RuleBuilder we are testing
  # Context: TestCtx, Groups: TestGroups, Atom: char, Lines: false
  RB = RuleBuilder[TestCtx, TestGroups, char, false]

block BasicMatching:
  # RB.match is now a static proc on the generic type
  let p = RB.match('a')
  let c = p.codex[]
  let entry = c[p.root]
   
  doAssert entry.kind == vkCheckMatch
  # 'char' is an Atom, so it uses ckAtom
  doAssert entry.checkType == ckAtom 
  doAssert entry.valAtom == 'a'

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
  doAssert child1.valAtom == 'a'
   
  doAssert child2.kind == vkCheckMatch
  doAssert child2.valAtom == 'b'

block RecursionAndDefinitions:
  # define is now called on the Typedesc
  let ruleA = RB.define("A")
  ruleA.implement(RB.match('a'))
   
  let p = call(ruleA)
  let c = p.codex[]
   
  let callNode = c[p.root]
  doAssert callNode.kind == vkCall
   
  let rDef = c[callNode.ruleIdx]
  doAssert rDef.name == "A"
   
  let entryNode = c[rDef.entry]
  doAssert entryNode.kind == vkCheckMatch
  doAssert entryNode.valAtom == 'a'

block Lookaheads:
  let p = peek(RB.match('a'))
  let c = p.codex[]
  let root = c[p.root]
   
  doAssert root.kind == vkLookahead
  doAssert root.invert == false
   
  let innerIdx = root.lookaheadVerse
  let inner = c[innerIdx]
  doAssert inner.kind == vkCheckMatch
  doAssert inner.valAtom == 'a'

block StringMatching:
  # Testing the openArray[char] matcher
  let p = RB.match("hello")
  let c = p.codex[]
  let root = c[p.root]

  doAssert root.kind == vkCheckMatch
  doAssert root.checkType == ckSeqAtom
  doAssert c[root.atomPoolIdx] == "hello"