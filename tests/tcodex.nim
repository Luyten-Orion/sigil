import std/importutils
import sigil/codex/ctypes {.all.}
import sigil

type 
  TestCtx = object
  TestGroups = enum tgNone
  TestCodex = Codex[TestCtx, TestGroups, char, false]
  TestVerse = Verse[TestGroups, char]
  TestParserCtx = ParserCtx[TestCtx, TestGroups, char, false]
  TestActProc = ActProc[TestCtx, TestGroups, char, false]

privateAccess(TestCodex)

# ---------- Pooling ----------
block CodexPooling:
  var c = TestCodex()
  let
    idx1 = c.add(@"hello")
    idx2 = c.add(@"world")
    idx3 = c.add(@"hello")
  doAssert idx1.int == 0
  doAssert idx2.int == 1
  doAssert idx3.int == 0
  doAssert c.atomPool.len == 2
  doAssert c.atomPool[0] == @"hello"

  let
    s1 = {'a'..'z'}
    s2 = {'0'..'9'}
    setIdx1 = c.add(s1)
    setIdx2 = c.add(s2)
    setIdx3 = c.add(s1)
  doAssert setIdx1 != setIdx2
  doAssert setIdx1 == setIdx3
  doAssert c.setPool.len == 2

  let
    str1 = c.add("alpha")
    str2 = c.add("beta")
    str3 = c.add("alpha")
  doAssert str1 == str3
  doAssert str1 != str2

  var
    act1: TestActProc = proc(ctx: var TestParserCtx): bool = false
    act2: TestActProc = proc(ctx: var TestParserCtx): bool = true
  let
    actIdx1 = c.addAct(act1)
    actIdx2 = c.addAct(act2)
    actIdx3 = c.addAct(act1)
  doAssert actIdx1 == actIdx3
  doAssert actIdx1 != actIdx2

# ---------- Edge cases for pooling ----------
block PoolingEdgeCases:
  var c = TestCodex()
  let
    emptyAtom = c.add(newSeq[char]()) # `@[]` causes mirtypes.nim(986, 16) unreachable: tyEmpty
    emptyAtom2 = c.add(newSeq[char]())
  doAssert emptyAtom == emptyAtom2
  doAssert c.atomPool.len == 1
  doAssert c.atomPool[0] == @[]

  let
    emptySet = c.add({})
    emptySet2 = c.add({})
  doAssert emptySet == emptySet2
  doAssert c.setPool.len == 1
  doAssert c.setPool[0] == {}

  let
    emptyStr = c.add("")
    emptyStr2 = c.add("")
  doAssert emptyStr == emptyStr2
  doAssert c.strPool.len == 1
  doAssert c.strPool[0] == ""


# ---------- Verse deduplication ----------
block VerseDeduplication:
  var c = TestCodex()
  let
    v = TestVerse.checkMatch(c, 'a')
    idx1 = c.add(v)
    idx2 = c.add(v)
  doAssert idx1 == idx2
  doAssert c.verses.len == 1

  # Also check with different verse kinds
  let
    v2 = TestVerse.loop(VerseIdx(0))
    idx3 = c.add(v2)
    idx4 = c.add(v2)
  doAssert idx3 == idx4
  doAssert c.verses.len == 2

# ---------- Verse construction ----------
block VerseConstructors:
  var c = TestCodex()

  # CheckMatch
  let vm1 = TestVerse.checkMatch(c, 'a')
  doAssert vm1.kind == vkCheckMatch
  doAssert vm1.checkType == ckAtom
  doAssert vm1.valAtom == 'a'

  let vmSeq = TestVerse.checkMatch(c, @"ab")
  doAssert vmSeq.kind == vkCheckMatch
  doAssert vmSeq.checkType == ckSeqAtom

  let vmSet = TestVerse.checkMatch(c, {'0'..'9'})
  doAssert vmSet.kind == vkCheckMatch
  doAssert vmSet.checkType == ckSet

  let vmAny = TestVerse.checkMatchAny()
  doAssert vmAny.kind == vkCheckMatch
  doAssert vmAny.checkType == ckAny

  # CheckNoMatch
  let vn1 = TestVerse.checkNoMatch(c, 'b')
  doAssert vn1.kind == vkCheckNoMatch
  doAssert vn1.checkType == ckAtom
  doAssert vn1.valAtom == 'b'
  let vnSet = TestVerse.checkNoMatch(c, {'x','y'})
  doAssert vnSet.kind == vkCheckNoMatch
  doAssert vnSet.checkType == ckSet
  let vnAny = TestVerse.checkNoMatchAny()
  doAssert vnAny.kind == vkCheckNoMatch
  doAssert vnAny.checkType == ckAny

  # Seq
  let
    s1 = c.add(vm1)
    s2 = c.add(vmSeq)
    spineStart = c.add(s1)
    seqV = TestVerse.seq(spineStart, 2)
  discard c.add(s2)
  doAssert seqV.kind == vkSeq
  doAssert seqV.spineLen == 2

  # Choice
  let choiceV = TestVerse.choice(s1, s2)
  doAssert choiceV.kind == vkChoice
  doAssert choiceV.tryVerse == s1
  doAssert choiceV.elseVerse == s2

  # Loop
  let loopV = TestVerse.loop(s1)
  doAssert loopV.kind == vkLoop
  doAssert loopV.bodyVerse == s1

  # Call
  let
    ruleDef = RuleDef(name: "test", entry: VerseIdx(-1))
    ruleIdx = c.add(ruleDef)
    callV = TestVerse.call(c, ruleDef)
  doAssert callV.kind == vkCall
  doAssert callV.ruleIdx == ruleIdx

  # Siphon
  let siphonV = TestVerse.siphon(c, s1, tgNone)
  doAssert siphonV.kind == vkSiphon
  doAssert siphonV.siphonBody == s1
  doAssert siphonV.channelIdx == tgNone

  # Act
  let
    actIdx = c.addAct(proc(ctx: var TestParserCtx): bool = true)
    actV = TestVerse.act(c, s1, actIdx)
  doAssert actV.kind == vkAct
  doAssert actV.actBody == s1
  doAssert actV.actIdx == actIdx

  # ErrorLabel
  let
    labelIdx = c.add("my error")
    errV = TestVerse.errorLabel(c, s1, "my error")
  doAssert errV.kind == vkErrorLabel
  doAssert errV.labelledVerseIdx == s1
  doAssert errV.labelStrIdx == labelIdx

  # Lookahead
  let peekV = TestVerse.lookahead(s1, false)
  doAssert peekV.kind == vkLookahead
  doAssert peekV.lookaheadVerse == s1
  doAssert peekV.invert == false
  let rejectV = TestVerse.lookahead(s1, true)
  doAssert rejectV.invert == true

  # Commit
  let commitV = TestVerse.commit(c, s1)
  doAssert commitV.kind == vkCommit
  doAssert commitV.commitBody == s1

# ---------- Full verse equality for all kinds ----------
block VerseEqualityAllKinds:
  var c = TestCodex()
  let
    a = TestVerse.checkMatch(c, 'a')
    a2 = TestVerse.checkMatch(c, 'a')
    b = TestVerse.checkMatch(c, 'b')
  doAssert a == a2
  doAssert a != b

  let
    seq1 = TestVerse.seq(SpineIdx(0), 2)
    seq2 = TestVerse.seq(SpineIdx(0), 2)
    seq3 = TestVerse.seq(SpineIdx(1), 2)
  doAssert seq1 == seq2
  doAssert seq1 != seq3

  let
    ch1 = TestVerse.choice(VerseIdx(0), VerseIdx(1))
    ch2 = TestVerse.choice(VerseIdx(0), VerseIdx(1))
    ch3 = TestVerse.choice(VerseIdx(1), VerseIdx(0))
  doAssert ch1 == ch2
  doAssert ch1 != ch3

  # Loop
  let
    loop1 = TestVerse.loop(VerseIdx(0))
    loop2 = TestVerse.loop(VerseIdx(0))
    loop3 = TestVerse.loop(VerseIdx(1))
  doAssert loop1 == loop2
  doAssert loop1 != loop3

  # Call (depends on RuleIdx, which is an int)
  let ruleDef = RuleDef(name: "R", entry: VerseIdx(0))
  discard c.add(ruleDef)
  let
    call1 = TestVerse.call(c, ruleDef)  # adds rule to codex
    call2 = TestVerse.call(c, ruleDef)
  # These two are equal because the rule is deduplicated, so ruleIdx same
  doAssert call1 == call2
  # Different rule
  let ruleDef2 = RuleDef(name: "R2", entry: VerseIdx(1))
  discard c.add(ruleDef2)
  let call3 = TestVerse.call(c, ruleDef2)
  doAssert call1 != call3

  # Siphon
  let
    sip1 = TestVerse.siphon(c, VerseIdx(0), tgNone)
    sip2 = TestVerse.siphon(c, VerseIdx(0), tgNone)
    sip3 = TestVerse.siphon(c, VerseIdx(1), tgNone)
  doAssert sip1 == sip2
  doAssert sip1 != sip3

  # Act
  let
    actIdx1 = c.addAct(proc(ctx: var TestParserCtx): bool = true)
    actIdx2 = c.addAct(proc(ctx: var TestParserCtx): bool = false)
    act1 = TestVerse.act(c, VerseIdx(0), actIdx1)
    act2 = TestVerse.act(c, VerseIdx(0), actIdx1)
    act3 = TestVerse.act(c, VerseIdx(0), actIdx2)
  doAssert act1 == act2
  doAssert act1 != act3

  # ErrorLabel
  let
    err1 = TestVerse.errorLabel(c, VerseIdx(0), "error1")
    err2 = TestVerse.errorLabel(c, VerseIdx(0), "error1")
    err3 = TestVerse.errorLabel(c, VerseIdx(1), "error1")
    err4 = TestVerse.errorLabel(c, VerseIdx(0), "error2")
  doAssert err1 == err2
  doAssert err1 != err3
  doAssert err1 != err4

  # Lookahead
  let
    peek1 = TestVerse.lookahead(VerseIdx(0), false)
    peek2 = TestVerse.lookahead(VerseIdx(0), false)
    peek3 = TestVerse.lookahead(VerseIdx(0), true)
    peek4 = TestVerse.lookahead(VerseIdx(1), false)
  doAssert peek1 == peek2
  doAssert peek1 != peek3
  doAssert peek1 != peek4

  # Commit
  let
    com1 = TestVerse.commit(c, VerseIdx(0))
    com2 = TestVerse.commit(c, VerseIdx(0))
    com3 = TestVerse.commit(c, VerseIdx(1))
  doAssert com1 == com2
  doAssert com1 != com3

  # CheckMatch variants
  let
    cmAtom1 = TestVerse.checkMatch(c, 'a')
    cmAtom2 = TestVerse.checkMatch(c, 'a')
    cmAtom3 = TestVerse.checkMatch(c, 'b')
  doAssert cmAtom1 == cmAtom2
  doAssert cmAtom1 != cmAtom3

  let
    cmSeq1 = TestVerse.checkMatch(c, @"ab")
    cmSeq2 = TestVerse.checkMatch(c, @"ab")
    cmSeq3 = TestVerse.checkMatch(c, @"ac")
  doAssert cmSeq1 == cmSeq2
  doAssert cmSeq1 != cmSeq3

  let
    cmSet1 = TestVerse.checkMatch(c, {'a','b'})
    cmSet2 = TestVerse.checkMatch(c, {'a','b'})
    cmSet3 = TestVerse.checkMatch(c, {'a','c'})
  doAssert cmSet1 == cmSet2
  doAssert cmSet1 != cmSet3

  let
    cmAny1 = TestVerse.checkMatchAny()
    cmAny2 = TestVerse.checkMatchAny()
  doAssert cmAny1 == cmAny2

  # CheckNoMatch variants
  let
    cnAtom1 = TestVerse.checkNoMatch(c, 'a')
    cnAtom2 = TestVerse.checkNoMatch(c, 'a')
    cnAtom3 = TestVerse.checkNoMatch(c, 'b')
  doAssert cnAtom1 == cnAtom2
  doAssert cnAtom1 != cnAtom3

  let
    cnSet1 = TestVerse.checkNoMatch(c, {'a','b'})
    cnSet2 = TestVerse.checkNoMatch(c, {'a','b'})
    cnSet3 = TestVerse.checkNoMatch(c, {'a','c'})
  doAssert cnSet1 == cnSet2
  doAssert cnSet1 != cnSet3

  let
    cnAny1 = TestVerse.checkNoMatchAny()
    cnAny2 = TestVerse.checkNoMatchAny()
  doAssert cnAny1 == cnAny2

# ---------- Indexing ----------
block Indexing:
  var c = TestCodex()
  let
    v = TestVerse.checkMatch(c, 'a')
    idx = c.add(v)
  doAssert c[idx] == v
  let s = c.add("hello")
  doAssert c[s] == "hello"
  let atomSeq = c.add(@"abc")
  doAssert c[atomSeq] == @"abc"
  let setV = c.add({'a','b'})
  doAssert c[setV] == {'a','b'}
  let
    rule = RuleDef(name: "R", entry: VerseIdx(0))
    rIdx = c.add(rule)
  doAssert c[rIdx] == rule
  let
    act = proc(ctx: var TestParserCtx): bool = true
    aIdx = c.addAct(act)
  doAssert c[aIdx] != nil

# ---------- Spine ----------
block SpineManipulation:
  var c = TestCodex()
  let
    v1 = c.add(TestVerse.checkMatch(c, 'a'))
    v2 = c.add(TestVerse.checkMatch(c, 'b'))
    spine1 = c.add(v1)
    spine2 = c.add(v2)
  doAssert c[spine1] == v1
  doAssert c[spine2] == v2
  let spine3 = succ(spine1)
  doAssert spine3 == spine2

  # Test offset > 1
  let
    v3 = c.add(TestVerse.checkMatch(c, 'c'))
    spine4 = c.add(v3)
    spine5 = succ(spine1, 2)
  doAssert spine5 == spine4

# ---------- String representation (optional) ----------
block StringRepresentation:
  # Just check they don't crash and produce something sensible
  let vIdx = VerseIdx(5)
  doAssert $vIdx == "v@5"
  let sIdx = SpineIdx(3)
  doAssert $sIdx == "s@3"
  let strIdx = StrPoolIdx(1)
  doAssert $strIdx == "pstr@1"
  let atomIdx = AtomPoolIdx(2)
  doAssert $atomIdx == "patom@2"
  let setIdx = SetPoolIdx(4)
  doAssert $setIdx == "pset@4"
  let actIdx = ActIdx(6)
  doAssert $actIdx == "a@6"
  let ruleIdx = RuleIdx(7)
  doAssert $ruleIdx == "r@7"