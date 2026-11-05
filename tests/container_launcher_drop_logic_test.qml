import QtQuick
import QtTest
import "../contents/ui/config/code/configItems.js" as ConfigItems

TestCase {
    name: "ContainerLauncherDropLogic"

    function init() {
        failOnWarning(/.?/)
    }

    function launcher(overrides) {
        const result = {
            "name": "Writer",
            "icon": "libreoffice-writer",
            "command": "libreoffice --writer %U",
            "description": "Word processor",
            "storageId": "libreoffice-writer.desktop",
            "appId": "libreoffice-writer"
        }
        const source = overrides || {}
        const keys = Object.keys(source)
        for (let index = 0; index < keys.length; index++) {
            result[keys[index]] = source[keys[index]]
        }
        return result
    }

    function manualContainer(layout) {
        return {
            "type": "folder",
            "name": "Office",
            "icon": "folder-documents",
            "layout": layout,
            "sourceType": "manual",
            "apps": []
        }
    }

    function test_eachPresentationAcceptsTheSameManualContainerOperation() {
        const layouts = ["grid", "list", "detailed", "fan"]
        for (let index = 0; index < layouts.length; index++) {
            const original = [manualContainer(layouts[index])]
            const result = ConfigItems.addApplicationToManualContainer(
                original, 0, launcher())

            verify(result.changed)
            compare(result.status, "added")
            compare(original[0].apps.length, 0)
            compare(result.items[0].layout, layouts[index])
            compare(result.items[0].apps.length, 1)
            compare(result.items[0].apps[0].storageId,
                "libreoffice-writer.desktop")
            compare(result.items[0].apps[0].appId, "libreoffice-writer")
            compare(result.items[0].apps[0].name, "Writer")
            compare(result.items[0].apps[0].icon,
                "libreoffice-writer")
        }
    }

    function test_duplicateIdentityDoesNotMutateTheContainer() {
        const container = manualContainer("grid")
        container.apps = [launcher({
            "storageId": "LibreOffice-Writer.desktop",
            "appId": "LibreOffice-Writer"
        })]

        const result = ConfigItems.addApplicationToManualContainer(
            [container], 0, launcher())

        verify(!result.changed)
        compare(result.status, "duplicate")
        compare(result.items[0].apps.length, 1)
    }

    function test_managedContainerRejectsManualContent() {
        const container = manualContainer("list")
        container.sourceType = "category"

        const result = ConfigItems.addApplicationToManualContainer(
            [container], 0, launcher())

        verify(!result.changed)
        compare(result.status, "managed-container")
        compare(result.items[0].apps.length, 0)
    }

    function test_invalidLauncherAndStaleTargetAreRejected() {
        const invalidLauncher = ConfigItems.addApplicationToManualContainer(
            [manualContainer("detailed")], 0, { "name": "Missing ID" })
        verify(!invalidLauncher.changed)
        compare(invalidLauncher.status, "invalid-application")

        const invalidTarget = ConfigItems.addApplicationToManualContainer(
            [{ "type": "app", "name": "Writer" }], 0, launcher())
        verify(!invalidTarget.changed)
        compare(invalidTarget.status, "invalid-target")
    }

    function test_folderLayoutUpdateIsImmutableAndPresentationOnly() {
        const original = [manualContainer("grid")]
        original[0].apps = [launcher()]

        const result = ConfigItems.setFolderLayout(original, 0, "fan")

        verify(result.changed)
        compare(result.status, "updated")
        compare(original[0].layout, "grid")
        compare(result.items[0].layout, "fan")
        compare(result.items[0].apps.length, 1)
        compare(result.items[0].sourceType, "manual")
    }

    function test_batchIsOrderedDeduplicatedAndImmutable() {
        const original = [manualContainer("grid")]
        original[0].apps = [launcher()]
        const second = launcher({
            "storageId": "org.example.Calc.desktop", "appId": "org.example.Calc",
            "name": "Calc"
        })
        const result = ConfigItems.addApplicationToManualContainer(original, 0, {
            "applications": [launcher(), second, second]
        })
        verify(result.changed)
        compare(result.addedCount, 1)
        compare(result.application.name, "Calc")
        compare(result.container.apps.length, 2)
        compare(result.container.apps[1].storageId, second.storageId)
        compare(original[0].apps.length, 1)

        const duplicate = ConfigItems.addApplicationToManualContainer(
            result.items, 0, { "applications": [launcher(), second] })
        verify(!duplicate.changed)
        compare(duplicate.status, "duplicate")
        verify(duplicate.items === result.items)
        compare(duplicate.applicationCount, 2)
    }

    function test_batchFailureLeavesAllOriginalEntriesUntouched() {
        const original = [manualContainer("fan")]
        const invalid = ConfigItems.addApplicationToManualContainer(original, 0, {
            "applications": [launcher(), { "name": "Missing identity" }]
        })
        verify(!invalid.changed)
        compare(invalid.status, "invalid-application")
        verify(invalid.items === original)
        compare(original[0].apps.length, 0)
        const managed = [manualContainer("grid")]
        managed[0].sourceType = "folder"
        const rejected = ConfigItems.addApplicationToManualContainer(managed, 0, {
            "applications": [launcher(), launcher()]
        })
        compare(rejected.status, "managed-container")
        verify(rejected.items === managed)
        for (const applications of [[], new Array(65).fill(launcher())]) {
            const result = ConfigItems.addApplicationToManualContainer(
                original, 0, { "applications": applications })
            verify(!result.changed)
            verify(result.items === original)
        }
    }

    function test_dockBatchMovesExistingEntriesWithoutLosingTheirActions() {
        const a = { "type": "app", "storageId": "a.desktop", "actions": [{ "name": "Keep" }] }
        const b = { "type": "app", "storageId": "b.desktop" }
        const marker = { "type": "dynamic-apps" }
        const original = [a, marker, b]
        const result = ConfigItems.placeApplicationsOnDock(original, [
            { "storageId": "b.desktop", "existingIndex": 2 },
            { "storageId": "c.desktop", "existingIndex": -1 },
            { "storageId": "a.desktop", "existingIndex": 0 },
            { "storageId": "b.desktop", "existingIndex": 2 }
        ], 1)
        compare(result.count, 3)
        compare(result.items.length, 4)
        verify(result.items[0] === b)
        compare(result.items[1].storageId, "c.desktop")
        verify(result.items[2] === a)
        verify(result.items[3] === marker)
        compare(result.items[2].actions[0].name, "Keep")
        compare(original.length, 3)
        verify(original[0] === a)
        verify(original[2] === b)
    }

    function test_dockBatchInsertionBoundariesAndExistingPositions() {
        const items = ["a", "b", "c"].map(function(id) {
            return { "type": "app", "storageId": id + ".desktop" }
        })
        for (let target = 0; target <= items.length; target++) {
            const result = ConfigItems.placeApplicationsOnDock(items, [
                { "storageId": "a.desktop", "existingIndex": 0 },
                { "storageId": "c.desktop", "existingIndex": 2 }
            ], target)
            const expected = target <= 1
                ? ["a.desktop", "c.desktop", "b.desktop"]
                : ["b.desktop", "a.desktop", "c.desktop"]
            compare(result.items.map(function(item) { return item.storageId }), expected)
        }
        const appended = ConfigItems.placeApplicationsOnDock(items, [
            { "storageId": "d.desktop", "existingIndex": -1 },
            { "storageId": "e.desktop", "existingIndex": -1 }
        ], 999)
        compare(appended.items[3].storageId, "d.desktop")
        compare(appended.items[4].storageId, "e.desktop")
    }

    function test_folderLayoutUpdateRejectsInvalidInputsAndNoOp() {
        const original = [manualContainer("list")]
        const unchanged = ConfigItems.setFolderLayout(original, 0, "list")
        verify(!unchanged.changed)
        compare(unchanged.status, "unchanged")
        verify(unchanged.items === original)

        const invalidLayout = ConfigItems.setFolderLayout(
            original, 0, "radial")
        verify(!invalidLayout.changed)
        compare(invalidLayout.status, "invalid-layout")

        const invalidTarget = ConfigItems.setFolderLayout(
            [{ "type": "app" }], 0, "grid")
        verify(!invalidTarget.changed)
        compare(invalidTarget.status, "invalid-target")
    }
}
