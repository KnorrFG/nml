import nml
import unittest
import macroutils

suite "Macro Internals":
  test "basic":
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

from constructor import event

event FooEvent, int, char
event Event

var 
  fooEvent = FooEvent()
  arglessEvent = Event()

test "property bindings and slots":
  mkui(Ui1):
    Rectangle:
      color cWhite
      rect <- parent

    a = Rectangle:
      color cBlack

      size <- *parent / 2
      center <- parent

    Rectangle:
      color cBlue
      right <- a.left
      centerY <- a
      
      slot fooEvent(i, c):
        discard

      slot arglessEvent():
        discard

      slot parent.size(s):
        let sl = min(s.w, s.h) / 4
        self.size.set size(sl, sl)

  let ui = newUi1()
  ui.rect.set rect(0, 0, 100, 100)

  doAssert ui.children[0].rect.get() == rect(0, 0, 100, 100)
  doAssert ui.children[1].size.get() == size(50, 50)
  doAssert ui.children[1].center.get() == point(50, 50)
  doAssert ui.children[2].right.get() == 25
  doAssert ui.children[2].size.get() == point(25, 25)

