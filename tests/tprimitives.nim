import std/[strutils, sets]
import sigil/[sigir, sigvm]
import ./common

block Primitives:
  echo "Running Primitives Test..."
  var ctx = TestContext()

  const primitiveParser = static:
    let g = newGrammar[TestContext]()
    
    let pChar = g.match('a')
    let pStr  = g.match("foo")
    let pSet  = g.match({'0'..'9'})
    
    # (a or foo or [0-9])
    g.compile(pChar or pStr or pSet)

  # Test Char
  doAssert run(primitiveParser, "a", ctx).success, "Should match char 'a'"
  doAssert not run(primitiveParser, "b", ctx).success, "Should fail char 'b'"

  # Test String
  doAssert run(primitiveParser, "foo", ctx).success, "Should match string 'foo'"
  doAssert not run(primitiveParser, "bar", ctx).success, "Should fail string 'bar'"
  
  # Test Set
  doAssert run(primitiveParser, "5", ctx).success, "Should match digit set"
  doAssert not run(primitiveParser, "z", ctx).success, "Should fail non-digit"

block Negation:
  echo "Running Negation Test..."
  var ctx = TestContext()

  const exceptParser = static:
    let g = newGrammar[TestContext]()
    # Match any char EXCEPT 'X'
    g.compile(g.matchExcept('X'))

  doAssert run(exceptParser, "Y", ctx).success, "Should match 'Y'"
  
  let resFail = run(exceptParser, "X", ctx)
  doAssert not resFail.success, "Should fail on 'X'"
  # Pretty printed char `X`
  doAssert resFail.foundTerminal == "`X`", "Expected foundTerminal to be `X`, got: " & resFail.foundTerminal