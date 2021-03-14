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
    doAssert ui.children[0].Rectangle.color == color(0, 255, 255, 255)
    doAssert ui.children[1].Rectangle.color == color(0, 1, 255, 255)


  test "Anchors":
    mkui(Ui1):
      Rectangle:
        color cWhite

        a = Rectangle:
          color cBlack

          size <- parent / 2
          center <- parent.center

        Rectangle:
          color cBlue
          
          right <- a.left
          centerY <- a.centerY
          size <- min(parent.w, parent.h) / 4
