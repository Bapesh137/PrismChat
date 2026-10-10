import QtQuick
import QtQuick.Controls
import QtTest
import "../components/chat"
import "../utils" as L10n

Item {
    id: scene
    width: 900; height: 680
    ListModel { id: emptyMessages }
    Component { id: menusComponent; MessageContextMenus {} }
    Component { id: pickerComponent; EmojiPicker { parent: scene; x: 10; y: 10 } }
    Component {
        id: chatComponent
        ChatView {
            width: 850; height: 640
            messageModel: emptyMessages
            currentRoomId: "!fixture:test"
            autoLoadImages: false; autoLoadVideos: false
        }
    }
    TestCase {
        name: "QuickReactions"
        when: windowShown
        property var store: L10n.QuickReactionStore
        function visualChild(item,name) {
            if (!item) return null
            if (item.objectName===name) return item
            var children=item.children || []
            for(var i=0;i<children.length;i++) {
                var found=visualChild(children[i],name)
                if(found) return found
            }
            return null
        }
        function init() {
            store.restore("{}")
            failOnWarning(/Binding loop|ReferenceError|TypeError/)
        }
        function cleanup() { store.restore("{}"); store.persist() }
        function test_recencyIsIndependentOfFrequencyAndKeepsSixChoices() {
            for (var i=0;i<9;i++) store.recordUse("👍")
            store.recordUse("😂"); store.recordUse("❤️")
            compare(store.orderedKeys.slice(0,3).join(","),"❤️,😂,👍")
            store.recordUse("😂")
            compare(store.orderedKeys.slice(0,3).join(","),"😂,❤️,👍")
            compare(store.orderedKeys.length,6)
            for (var j=0;j<100;j++) store.recordUse("other"+j)
            compare(store.orderedKeys.slice(0,3).join(","),"😂,❤️,👍")
            verify(store.recent.length<=64)
        }
        function test_replacementPreservesUnicodeAndRejectsDuplicates() {
            store.recordUse("❤️"); store.recordUse("👍")
            verify(store.replaceKey("😢","👩🏽‍💻"))
            verify(store.replaceKey("😮","🇯🇵"))
            compare(store.orderedKeys.slice(0,2).join(","),"👍,❤️")
            verify(store.keys.indexOf("👩🏽‍💻")>=0)
            verify(!store.replaceKey("😂","👍"))
            verify(!store.replaceKey("😂",""))
            verify(!store.replaceKey("😂","x".repeat(65)))
            compare(store.keys.length,6)
            store.persist()
            var saved = store.settings.stateJson
            store.restore("broken")
            compare(store.keys.join(","),store.defaults.join(","))
            store.restore(saved)
            verify(store.keys.indexOf("👩🏽‍💻")>=0)
            verify(store.keys.indexOf("🇯🇵")>=0)
            compare(store.orderedKeys.slice(0,2).join(","),"👍,❤️")
        }
        function test_menuOpensEditorAndEditingDoesNotSendAReaction() {
            var menus = createTemporaryObject(menusComponent,scene)
            var sent = []
            menus.reactionRequested.connect(function(message,key){sent.push(key)})
            menus.openSingle(0,{event_id:"$fixture",body:"Hello",reactions:[]})
            var menu = findChild(menus,"messageSingleMenu")
            tryCompare(menu,"opened",true)
            menu.reactionsExpanded = true
            var edit = findChild(menus,"editQuickReactions")
            tryVerify(function(){return edit.visible})
            wait(150)
            mouseClick(edit,edit.width/2,edit.height/2)
            var picker = null
            tryVerify(function(){picker=findChild(menus,"quickReactionEditor"); return picker && picker.opened})
            var slot = visualChild(picker.contentItem,"quickSlot_😢")
            verify(slot)
            mouseClick(slot,slot.width/2,slot.height/2)
            compare(picker.quickReactionTarget,"😢")
            picker.activateEmoji("🔥")
            compare(sent.length,0)
            verify(store.keys.indexOf("🔥")>=0)
            verify(store.keys.indexOf("😢")<0)
            compare(picker.quickReactionTarget,"🔥")
            verify(picker.opened)
            picker.close()
            tryCompare(menu,"opened",false)
            menus.openSingle(0,{event_id:"$fixture",body:"Hello",reactions:[]})
            tryCompare(menu,"opened",true)
            menu.reactionsExpanded = true
            var button = visualChild(menu.contentItem,"quickReaction_🔥")
            verify(button)
            wait(150)
            mouseClick(button,button.width/2,button.height/2)
            compare(sent.join(","),"🔥")
            menu.close()
        }
        function test_additionReordersButRemovalDoesNot() {
            var chat = createTemporaryObject(chatComponent,scene)
            var commands = []
            chat.commandRequested.connect(function(command){commands.push(command)})
            chat.requestReactionToggle("$fixture","😂",{})
            compare(store.orderedKeys[0],"😂")
            chat.requestReactionToggle("$fixture","❤️",{})
            compare(store.orderedKeys[0],"❤️")
            chat.requestReactionToggle("$fixture","😂",{reacted:true,own_event_id:"$reaction"})
            compare(store.orderedKeys[0],"❤️")
            compare(commands[commands.length-1].reacted,true)
        }
        function test_normalEmojiPickerStillEmitsWithoutEditingQuickChoices() {
            var picker = createTemporaryObject(pickerComponent,scene)
            var chosen = []
            picker.emojiChosen.connect(function(key){chosen.push(key)})
            picker.activateEmoji("🔥")
            compare(chosen.join(","),"🔥")
            compare(store.keys.join(","),store.defaults.join(","))
        }
        function test_menuPositionsNewestOnTheLeft() {
            store.recordUse("😢");store.recordUse("🎉")
            var menus=createTemporaryObject(menusComponent,scene)
            menus.openSingle(0,{event_id:"$fixture",body:"Hello",reactions:[]})
            var menu=findChild(menus,"messageSingleMenu")
            tryCompare(menu,"opened",true)
            menu.reactionsExpanded=true
            wait(150)
            var newest=visualChild(menu.contentItem,"quickReaction_🎉")
            var older=visualChild(menu.contentItem,"quickReaction_😢")
            verify(newest.x<older.x)
            menu.close()
        }
        function test_translations() {
            var original=L10n.I18n.language
            var sources=["Быстрые реакции","Изменить набор", "Выберите реакцию сверху, затем новый эмодзи", "Заменить"]
            for(var i=0;i<L10n.I18n.supportedLanguages.length;i++) {
                var lang=L10n.I18n.supportedLanguages[i].code
                if(lang==="ru") continue
                L10n.I18n.setLanguage(lang)
                for(var j=0;j<sources.length;j++) verify(L10n.I18n.tr(sources[j])!==sources[j],lang)
            }
            L10n.I18n.setLanguage(original)
        }
    }
}
