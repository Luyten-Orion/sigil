import std/[strutils, sets]
import sigil/[sigir, sigvm]
import ./common

block Combinators:
  echo "Running Combinators Test..."
  var ctx = TestContext()

  const logicParser = static:
    let g = newGrammar[TestContext]()
    let a = g.match('a')
    let b = g.match('b')
    
    # (a and b) or (many1(b))
    g.compile((a and b) or many1(b))

  # Test Sequence (And)
  let res1 = run(logicParser, "ab", ctx)
  doAssert res1.success, "Should match sequence 'ab'"
  doAssert res1.matchLen == 2, "Should consume 2 chars"

  # Test Many1
  let res2 = run(logicParser, "bbb", ctx)
  doAssert res2.success, "Should match many 'b's"
  doAssert res2.matchLen == 3, "Should consume 3 chars"
  
  # Test Failure
  doAssert not run(logicParser, "c", ctx).success, "Should fail on 'c'"

block Optional:
  echo "Running Optional Test..."
  var ctx = TestContext()

  const optParser = static:
    let g = newGrammar[TestContext]()
    let a = g.match('a')
    # optional(a) matches 'a' OR nothing
    g.compile(optional(a))

  doAssert run(optParser, "a", ctx).success, "Should match 'a'"
  doAssert run(optParser, "b", ctx).success, "Should succeed (matching empty string)"
  doAssert run(optParser, "", ctx).success, "Should succeed on empty input"