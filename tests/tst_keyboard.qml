import QtQuick
import QtTest
import "file:/usr/share/omarchy/shell/Ui" as OmarchyUi

TestCase {
  id: testCase
  name: "SteamFriendsKeyboard"
  when: windowShown
  width: 240
  height: 160

  property int activateCount: 0
  property int returnCount: 0
  property int closeCount: 0
  property int moveX: 0
  property int moveY: 0
  property int tabDirection: 0
  property string textKey: ""

  OmarchyUi.PanelKeyCatcher {
    id: catcher
    anchors.fill: parent
    onActivateRequested: testCase.activateCount++
    onReturnRequested: testCase.returnCount++
    onCloseRequested: testCase.closeCount++
    onMoveRequested: function(dx, dy) {
      testCase.moveX += dx
      testCase.moveY += dy
    }
    onTabRequested: function(direction) { testCase.tabDirection = direction }
    onTextKey: function(text) { testCase.textKey = text }

    TextInput {
      id: editor
      anchors.fill: parent
    }
  }

  function init() {
    activateCount = 0
    returnCount = 0
    closeCount = 0
    moveX = 0
    moveY = 0
    tabDirection = 0
    textKey = ""
    catcher.blocked = false
    catcher.forceActiveFocus()
    verify(catcher.activeFocus)
  }

  function test_return_and_keypad_enter_activate_once() {
    keyClick(Qt.Key_Return)
    compare(returnCount, 1)
    compare(activateCount, 1)

    keyClick(Qt.Key_Enter)
    compare(returnCount, 2)
    compare(activateCount, 2)

    keyClick(Qt.Key_Space)
    compare(returnCount, 2)
    compare(activateCount, 3)
  }

  function test_arrows_and_vim_navigation() {
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Up)
    keyClick(Qt.Key_Right)
    keyClick(Qt.Key_Left)
    compare(moveX, 0)
    compare(moveY, 0)

    keyClick(Qt.Key_J)
    keyClick(Qt.Key_K)
    keyClick(Qt.Key_L)
    keyClick(Qt.Key_H)
    compare(moveX, 0)
    compare(moveY, 0)
  }

  function test_shortcuts_escape_and_tabs() {
    keyClick(Qt.Key_R)
    compare(textKey, "r")
    keyClick(Qt.Key_S)
    compare(textKey, "s")
    keyClick(Qt.Key_Slash)
    compare(textKey, "/")
    keyClick(Qt.Key_Escape)
    compare(closeCount, 1)
    keyClick(Qt.Key_Tab)
    compare(tabDirection, 1)
    keyClick(Qt.Key_Backtab)
    compare(tabDirection, -1)
  }

  function test_blocked_catcher_does_not_activate() {
    catcher.blocked = true
    editor.forceActiveFocus()
    verify(editor.activeFocus)
    keyClick(Qt.Key_Return)
    keyClick(Qt.Key_Down)
    keyClick(Qt.Key_Escape)
    keyClick(Qt.Key_R)
    compare(returnCount, 0)
    compare(activateCount, 0)
    compare(moveY, 0)
    compare(closeCount, 0)
    compare(textKey, "")
  }
}
