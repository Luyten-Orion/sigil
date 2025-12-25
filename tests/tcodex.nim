import std/importutils
import sigil/codex/ctypes {.all.}

type TestCtx = object

privateAccess(Codex[TestCtx])

block CodexPooling:
  var c = Codex[TestCtx]()

  let idx1 = c.add("hello")
  let idx2 = c.add("world")
  let idx3 = c.add("hello")

  doAssert idx1.int == 0
  doAssert idx2.int == 1
  doAssert idx3.int == 0
  doAssert c.strPool.len == 2
  doAssert c.strPool[0] == "hello"

  let s1 = {'a'..'z'}
  let s2 = {'0'..'9'}
  let setIdx1 = c.add(s1)
  let setIdx2 = c.add(s2)
  let setIdx3 = c.add(s1)

  doAssert setIdx1 != setIdx2
  doAssert setIdx1 == setIdx3
  doAssert c.setPool.len == 2

block VerseConstruction:
  var c = Codex[TestCtx]()

  let v1 = Verse.checkMatch(c, 'a')
  let v1Idx = c.add(v1)
   
  let v2 = Verse.checkMatch(c, 'b')
  let v2Idx = c.add(v2)
   
  let spineStart = c.add(v1Idx)
  discard c.add(v2Idx)
   
  let seqVerse = Verse.seq(spineStart, 2)
  doAssert seqVerse.kind == vkSeq
  doAssert seqVerse.spineLen == 2
   
  doAssert c[spineStart] == v1Idx
  doAssert c[SpineIdx(spineStart.int + 1)] == v2Idx