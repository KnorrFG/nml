import nml
import unittest
import macroutils

suite "Macro Internals":
  test "1":
    mkui(Ui1, a: int):
      Rectangle:
        color color(0, 255, 255, 255)
      foo = Rectangle:
        color color(0, a, 255, 255)

    let ui = newUi1(1)
    #echo ui.repr
    check ui.children.len == 2
    doAssert ui.children[0].Rectangle.color.get() == color(0, 255, 255, 255)
    doAssert ui.children[1].Rectangle.color.get() == color(0, 1, 255, 255)


# Es könnte gut sein, dass man in untyped macros keine types nachschauen kann.
# in dem fall gäbe es stufen von property binding. 
# 1. RHS ist ein identifiers. in dem fall wird die lhs property an den rhs
# identifier angehaengt, und falls der rhs ident parent ist, wird er
# substituiert
# 2. Rhs ist eine dot expression, in dem Fall muss die dot expression zu einer
# Property evaluieren
# 3. eine kompliziertere expression. in dem fall muss die source-property
# syntaktisch makiert werden. (z.b. durch einen * prefix), Da der predfix
# schwächer bindet als die dotexpression kann dann dafür 1. und 2. wieder
# angewandt werden.

  test "Anchors":
    mkui(Ui1):
      Rectangle:
        color cWhite
        slot(s: parent.size):
          self.size.set s

        a = Rectangle:
          color cBlack

          slot(s: parent.size):
            self.size.set s / 2
          #size <- parent / 2
          #center <- parent.center

        Rectangle:
          color cBlue
          
          slot(s: parent.size):
            let sl = min(s.w, s.h) / 4
            self.size.set size(sl, sl)

    let ui = newUi1()
    let engine = newEngine()
    engine.createWindow(800, 600, ui, "Test Window")
    engine.run()

