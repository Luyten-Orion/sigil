import std/[strutils, sets]
import sigil/[sigir, sigvm]
import common

block Captures:
  echo "Running Captures Test..."
  var ctx = TestContext()

  const capParser = static:
    let g = newGrammar[TestContext]()
    let digit = g.match({'0'..'9'})
    g.compile(capture(many1(digit)))

  let res = run(capParser, "1234a", ctx)
  doAssert res.success
  doAssert res.matchLen == 4
  doAssert res.captures == @["1234"], "Expected capture '1234', got: " & $res.captures