import QtQuick
import QtTest
import "../settings"
Item {
    width: 450; height: 150
    SettingsActionButton { id: button; x: 40; y: 40; width: 250; text: "Restore Device"; primary: true; softPress: true }
    TestCase {
        when: windowShown
        name: "PrimaryButtonColors"
        function rgb(c) { return {r:c.r,g:c.g,b:c.b} }
        function test_colors() {
            waitForRendering(button)
            mouseMove(button, -20, -20)
            tryCompare(button,"hovered",false)
            tryVerify(function() { return Math.abs(button.background.color.r-button.accentColor.r)<0.002 })
            var idle = rgb(button.background.color)
            mouseMove(button, button.width/2, button.height/2)
            tryCompare(button,"hovered",true)
            tryVerify(function() { return button.background.color.r > idle.r+0.08 })
            var hover = rgb(button.background.color)
            mousePress(button,button.width/2,button.height/2)
            tryCompare(button,"down",true)
            tryVerify(function() { return button.background.color.r > hover.r+0.06 })
            var press = rgb(button.background.color)
            mouseRelease(button,button.width/2,button.height/2)
            console.log("colors",JSON.stringify([idle,hover,press]))
            verify(hover.g >= idle.g && hover.r > idle.r, "hover must lighten")
            verify(press.g >= hover.g && press.r > hover.r, "press must lighten further")
        }
    }
}
