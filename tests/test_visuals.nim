# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import nml
import unittest, os, strformat, strutils

suite "Interactive":
  setup:
    var engine = newEngine()

  test "MouseArea":
    mkui(Ui1):
      Rectangle:
        color cGreen
        size <- parent
      Rectangle:
        color cWhite
        center <- parent
        size <- *parent / 6

        Text:
          text unindent"""Click Me.
                          I have two lines"""
          fontFile "tests/font.ttf"
          pointSize 20
          vAlign aCenter
          hAlign aCenter
          rect <- parent

        MouseArea:
          rect <- parent
          
          slot onLClick: echo "hi"
          slot onLPress: parent.color.set color(200, 200, 200, 255)
          slot onLClickEnd: parent.color.set cWhite

    engine.createWindow(800, 600, newUi1())
    engine.run()

