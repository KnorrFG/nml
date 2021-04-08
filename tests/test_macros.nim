import nml
import unittest
import macroutils
import sugar

event FooEvent, int, char

var 
  fooEvent = FooEvent()
  arglessEvent = EventEmpty()

suite "Macro Internals":
  test "basic":
    mkui(Ui1, a: int):
      Rectangle:
        color color(0, 255, 255, 255)
      foo = Rectangle:
        color color(0, a, 255, 255)

    let ui = newUi1(1)
    check ui.children.len == 2
    doAssert ui.children[0].Rectangle.color.get() == color(0, 255, 255, 255)
    doAssert ui.children[1].Rectangle.color.get() == color(0, 1, 255, 255)


  test "property bindings and slots":
    mkui(Ui2):
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
          echo "Foo"

        slot arglessEvent:
          echo "argless"

        slot parent.size(s):
          let sl = min(s.w, s.h) / 4
          self.size.set size(sl, sl)

    let ui = newUi2()
    ui.rect.set rect(0, 0, 100, 100)

    doAssert ui.children[0].rect.get() == rect(0, 0, 100, 100)
    doAssert ui.children[1].size.get() == size(50, 50)
    doAssert ui.children[1].center.get() == point(50, 50)
    doAssert ui.children[2].right.get() == 25
    doAssert ui.children[2].size.get() == point(25, 25)

    arglessEvent.invoke()
    fooEvent.invoke(1, 'c')


  test "forwarding":
    mkui(Ui3):
      forward:
        color = myRect.color
        ev = myRect.color.onChange

      myRect = Rectangle:
        color cWhite
        rect <- parent

    let ui = newUi3()
    var color = cWhite
    #ui.ev.add(c => (color = c; discard))
    ui.ev.add(proc(c: auto) = color = c)
    ui.color.set cBlack
    doAssert ui.children[0].Rectangle.color.get() == cBlack
    doAssert color == cBlack

  test "local slot":
    mkui(Ui4):
      Rectangle:
        rect <- parent
        slot color.onChange(c): echo "color changed: ", c

  #test "Animations":
  #  mkui(Ui5):
  #    r = Rectangle:
  #      color cWhite
  #      x 0
  #      size <- *parent / 10
        
  #      animation moveTopRight:
  #        transition:
  #          right -> parent.right
  #          top -> parent.top
  #        duration: 1

  #      animation moveBottomLeft:
  #        transition:
  #          left -> parent.left
  #          bottom -> parent.bottom
  #        duration 1
  #        freq 60

  #      MouseArea:
  #        rect <- parent
  #        slot onClicked:
  #          if self.currentState == default:
  #            moveRight.play
  #          else:
  #            moveRight.inverse.play
          
