# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import nml
import unittest, os, strformat

suite "Interactive":
  setup:
    var engine = newEngine()

  test "MouseArea":
    mkui(Ui1):
      Rectangle:
        color cBlack
        rect <- parent
      Rectangle:
        color cWhite
        center <- parent
        rect <- *parent / 6

        MouseArea:
          rect <- parent
          
          slot onClicked:
            self.window.close()

    engine.createWindow(800, 600, newUi1())
    engine.run()

