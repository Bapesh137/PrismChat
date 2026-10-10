import QtQuick
import QtQuick.Controls
import QtTest

Item {
    ApplicationWindow {
        id: host
        width: 850
        height: 900
        visible: true
    }

    TestCase {
        name: "SettingsDialogGeometry"
        when: windowShown

        function init() {
            failOnWarning(/Binding loop|ReferenceError|TypeError/)
        }

        function test_dialogs_data() {
            var rows = []
            var pages = {
                "DevicesSettingsPage": ["renameDialog", "deleteConfirmDialog", "deleteAuthDialog", "deleteWebDialog"],
                "EncryptionSettingsPage": ["setupRecoveryDialog", "recoverKeysDialog", "changeRecoveryKeyDialog",
                    "repairBackupDialog", "resetIdentityDialog", "matrixPasswordDialog", "oauthApprovalDialog", "recoveryKeyDialog"]
            }
            for (var page in pages)
                for (var i = 0; i < pages[page].length; i++)
                    rows.push({tag: pages[page][i], page: page, dialog: pages[page][i]})
            return rows
        }

        function test_dialogs(data) {
            var component = Qt.createComponent(Qt.resolvedUrl("../settings/pages/" + data.page + ".qml"))
            compare(component.status, Component.Ready, component.errorString())
            var page = createTemporaryObject(component, host.contentItem, {width: 700, height: 800})
            verify(page)
            var dialog = findChild(page, data.dialog)
            verify(dialog !== null, data.dialog)
            for (var i = 0; i < 2; i++) {
                host.width = i === 0 ? 850 : 340
                dialog.open()
                tryCompare(dialog, "opened", true)
                waitForPolish(host.contentItem)
                tryVerify(function() { return dialog.width > 0 && dialog.width <= host.width - 32 }, 2000, data.dialog + " width")
                verify(dialog.height > 0 && dialog.height < host.height, data.dialog + " height")
                verify(dialog.contentItem.height > 0, data.dialog + " empty content")
                verify(dialog.contentItem.width <= dialog.availableWidth + 1, data.dialog + " content overflow")
                dialog.close()
                tryCompare(dialog, "opened", false)
            }
            host.width = 850
        }
    }
}
