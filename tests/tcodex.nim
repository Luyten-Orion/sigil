import std/importutils
import sigil/codex/ctypes {.all.}
import sigil/lib

type 
  TestCtx = object
  TestGroups = enum tgNone
  TestCodex = Codex[TestCtx, TestGroups, char, false]
  TestVerse = Verse[TestGroups, char]

privateAccess(TestCodex)

block CodexPooling:
  var c = TestCodex()
  let idx1 = c.add(@"hello")
  let idx2 = c.add(@"world")
  let idx3 = c.add(@"hello")

  doAssert idx1.int == 0
  doAssert idx2.int == 1
  doAssert idx3.int == 0

  doAssert c.atomPool.len == 2
  doAssert c.atomPool[0] == @"hello"

  let s1 = {'a'..'z'}
  let s2 = {'0'..'9'}
  let setIdx1 = c.add(s1)
  let setIdx2 = c.add(s2)
  let setIdx3 = c.add(s1)

  doAssert setIdx1 != setIdx2
  doAssert setIdx1 == setIdx3
  doAssert c.setPool.len == 2

block VerseConstruction:
  var c = TestCodex()

  let v1 = TestVerse.checkMatch(c, 'a')
  let v1Idx = c.add(v1)
   
  let v2 = TestVerse.checkMatch(c, 'b')
  let v2Idx = c.add(v2)
   
  let spineStart = c.add(v1Idx)
  discard c.add(v2Idx)
   
  let seqVerse = TestVerse.seq(spineStart, 2)
  doAssert seqVerse.kind == vkSeq
  doAssert seqVerse.spineLen == 2
   
  doAssert c[spineStart] == v1Idx
  doAssert c[SpineIdx(spineStart.int + 1)] == v2Idx