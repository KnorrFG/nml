# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import nml
import unittest, os

suite "Basics":
  setup:
    var engine = newEngine()

  test "Basics":
    var tmp1 = newRectangle()
    tmp1.color = color(0, 255, 255, 255)

    engine.createWindow(800, 600, tmp1, "Test Window")
    engine.run()

