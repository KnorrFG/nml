# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import nml
import unittest, os, strformat

suite "Basics":
  setup:
    var engine = newEngine()

  test "Basics":
    var tmp1 = newRectangle()
    tmp1.color = color(0, 255, 255, 255)

    engine.createWindow(800, 600, tmp1, "Test Window")
    engine.run()

  test "Property Propagation":
    var tmp1 = newRectangle()
    tmp1.color = cWhite
    var a = newRectangle()
    tmp1.add a
    a.color = cBlack
    
    proc setASize(s: Size) = a.size.set(s / 2) 
    tmp1.size.onChange.add setASize

    proc setACenter(c: nml.Point) = a.center.set c 
    tmp1.center.onChange.add setACenter

    var tmp2 = newRectangle()
    tmp1.add tmp2
    tmp2.color = cBlue

    proc setTmp2Right(r: cint) = tmp2.right.set r
    a.left.onChange.add setTmp2Right
    proc setTmp2CenterY(cy: cint) = tmp2.centerY.set cy
    a.centerY.onChange.add setTmp2CenterY
    
    proc setTmp2Size(h: cint) =
      let s = cint(min(tmp1.w.get(), tmp1.h.get()) / 4)
      tmp2.size.set v(s, s)
    tmp1.w.onChange.add setTmp2Size
    tmp1.h.onChange.add setTmp2Size

    engine.createWindow(800, 600, tmp1, "Test Window")
    engine.run()


