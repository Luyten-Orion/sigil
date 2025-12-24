import std/[strutils, sets]
import sigil/[sigir, sigvm]
import common

block ErrorReporting:
  echo "Running Error Reporting Test..."
  var ctx = TestContext()

  const errParser = static:
    let g = newGrammar[TestContext]()
    
    let digit = g.match({'0'..'9'})
    let alpha = g.match({'a'..'z'})
    
    # Labelled rules
    let myInt = many1(digit).expect("an integer")
    let myWord = many1(alpha).expect("a lowercase word")
    
    # Parser: integer, then a dash, then a word
    let p = myInt and g.match('-') and myWord
    
    g.compile(p)

  # Case 1: Fail at start
  let r1 = run(errParser, "abc-123", ctx)
  doAssert not r1.success
  doAssert r1.furthestFailureIdx == 0
  doAssert "an integer" in r1.expectedTerminals, "Expected 'an integer' error, got: " & $r1.expectedTerminals

  # Case 2: Fail at dash (Unlabelled literal)
  let r2 = run(errParser, "123#abc", ctx)
  doAssert not r2.success
  doAssert r2.furthestFailureIdx == 3
  # match('-') uses prettyChar, so it expects "'" or "'-'"
  doAssert "'\\''" in r2.expectedTerminals or "'-'" in r2.expectedTerminals, "Expected dash error, got: " & $r2.expectedTerminals

  # Case 3: Fail at word
  let r3 = run(errParser, "123-999", ctx)
  doAssert not r3.success
  doAssert r3.furthestFailureIdx == 4
  doAssert "a lowercase word" in r3.expectedTerminals
  doAssert r3.foundTerminal == "`9`", "Expected found=`9`, got: " & r3.foundTerminal